// Explicit cloud-write acceptance against the disposable LAN server used by Emulator1.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { createHash, randomBytes } from 'node:crypto';
import dotenv from 'dotenv';
import postgres from 'postgres';
import {
	AbortMultipartUploadCommand,
	CreateMultipartUploadCommand,
	DeleteObjectCommand,
	DeleteObjectsCommand,
	ListMultipartUploadsCommand,
	ListObjectVersionsCommand
} from '@aws-sdk/client-s3';
import {
	backblazeS3Upload,
	createBackblazeS3Client,
	deleteBackblazeS3Version,
	findBackblazeS3Upload
} from '../../src/lib/server/backblazeS3';
import { ProviderRecoveryStorage } from '../../src/lib/server/recoveryStorage';

test(
	'local backend supports real legacy native uploads and negotiated S3 uploads',
	{ skip: process.env.FIFE_RUN_PROVIDER_WRITE_CHECKS !== '1', timeout: 180_000 },
	async () => {
		const fixture = JSON.parse(await readFile('/tmp/fife_b2_s3_server.json', 'utf8'));
		const database = new URL(fixture.databaseUrl);
		assert.equal(database.hostname, '127.0.0.1');
		assert.ok(database.port && database.port !== '5432');
		assert.ok(/^fife-provider-local-[a-f0-9-]+$/.test(fixture.remoteId));
		const inputs = dotenv.parse(await readFile('.env', 'utf8'));
		const app = dotenv.parse(await readFile('../.env', 'utf8'));
		const base = new URL(app.API_BASE_URL);
		assert.equal(base.port, String(fixture.port));
		assert.equal(inputs.LOCAL_TEST_AUTH_ENABLED, 'true');
		assert.equal(inputs.LOCAL_TEST_EMAIL, 'jeevan@jeero.one');
		const sql = postgres(fixture.databaseUrl, { max: 1 });
		let client: ReturnType<typeof createBackblazeS3Client> | undefined;
		const owned = new Set<string>();
		let bucket: string | undefined;
		const versions = async () => {
			assert.ok(client && bucket);
			const listed = await client.send(
				new ListObjectVersionsCommand({ Bucket: bucket, Prefix: `${fixture.remoteId}/` })
			);
			assert.ok(!listed.IsTruncated, 'Fixture prefix must stay bounded');
			return [...(listed.Versions ?? []), ...(listed.DeleteMarkers ?? [])]
				.filter((entry) => entry.Key && owned.has(entry.Key))
				.map((entry) => ({ Key: entry.Key!, VersionId: entry.VersionId! }));
		};
		try {
			const [storage] = await sql`
				select s."1" as id, c."6" as credentials from storage s
				join "user" u on s."4" = u."1" join credential c on s."5" = c."1"
				where u."4" = ${fixture.remoteId} and c."5" = 1 limit 1`;
			assert.ok(storage, 'Run the emulator bootstrap against the disposable server first');
			// Credential's provider/json columns differ from storage's compact columns.
			client = createBackblazeS3Client(storage.credentials);
			bucket = storage.credentials.bucketName;
			const api = async (path: string, body: object) => {
				const response = await fetch(new URL(`/api/b2/${path}`, base), {
					method: 'POST',
					headers: {
						'content-type': 'application/json',
						service: 'local-test',
						authorization: `Bearer ${inputs.LOCAL_TEST_AUTH_TOKEN}`,
						device_uuid: 'local-s3-emulator-device'
					},
					body: JSON.stringify(body),
					signal: AbortSignal.timeout(20_000)
				});
				assert.equal(response.status, 200);
				const result = await response.json();
				assert.equal(result.success === 1, true, 'Local API request must succeed');
				return result.data;
			};
			for (const protocol of ['native', 's3']) {
				const bytes = randomBytes(73),
					hash = createHash('sha256').update(bytes).digest('base64url'),
					name = `${hash}_1`,
					key = `${fixture.remoteId}/${name}`;
				owned.add(key);
				const integrity = {
					file_id: name,
					storage_id: storage.id,
					content_sha1: createHash('sha1').update(bytes).digest('hex'),
					content_md5: createHash('md5').update(bytes).digest('base64'),
					content_length: bytes.length
				};
				const descriptor = await api(
					'get-upload-url',
					protocol === 'native'
						? { storage_id: storage.id }
						: { ...integrity, upload_protocol: 's3' }
				);
				const target = new URL(descriptor.uploadUrl);
				assert.equal(target.protocol, 'https:');
				assert.ok(
					target.hostname.endsWith('.backblazeb2.com') ||
						(protocol === 'native' && target.hostname.endsWith('.backblaze.com'))
				);
				if (protocol === 's3') {
					assert.equal(descriptor.protocol, 's3');
					assert.equal(target.searchParams.get('X-Amz-Expires'), '900');
					const tampered = Buffer.from(bytes);
					tampered[0] ^= 1;
					const rejected = await fetch(target, {
						method: 'PUT',
						headers: descriptor.headers,
						body: tampered
					});
					assert.equal(rejected.status, 400, 'Provider must reject modified ciphertext');
					await rejected.arrayBuffer();
				}
				const upload = await fetch(target, {
					method: protocol === 'native' ? 'POST' : 'PUT',
					headers:
						protocol === 'native'
							? {
									authorization: descriptor.authorizationToken,
									'X-Bz-Content-Sha1': integrity.content_sha1,
									'X-Bz-File-Name': encodeURIComponent(key),
									'Content-Type': 'application/octet-stream'
								}
							: descriptor.headers,
					body: bytes,
					signal: AbortSignal.timeout(30_000)
				});
				assert.equal(upload.status, 200, 'Generated cloud fixture must upload');
				const version =
					protocol === 'native'
						? (await upload.json()).fileId
						: upload.headers.get('x-amz-version-id');
				if (protocol === 's3') await upload.arrayBuffer();
				assert.ok(typeof version === 'string' && version.length > 0);
				const recovered = await api('find-uploaded-file', integrity);
				assert.equal(
					recovered?.fileId === version,
					true,
					'Both upload formats must retain the same file identity'
				);
				const download = await fetch(await api('get-download-url', integrity));
				assert.equal(download.status, 200);
				assert.ok(Buffer.from(await download.arrayBuffer()).equals(bytes));
				assert.equal(await deleteBackblazeS3Version(storage.credentials, key, version), true);
				assert.equal(await api('find-uploaded-file', integrity), null);
			}
			const cleanupPrefix = `${fixture.remoteId}/vaults/${randomBytes(16).toString('hex')}/`;
			const name = `${randomBytes(32).toString('base64url')}_1`;
			const sentinel = `${fixture.remoteId}/${randomBytes(32).toString('base64url')}_1`;
			const bytes = Buffer.from('generated cleanup fixture');
			const integrity = {
				content_sha1: createHash('sha1').update(bytes).digest('hex'),
				content_md5: createHash('md5').update(bytes).digest('base64'),
				content_length: bytes.length
			};
			for (const key of [sentinel, cleanupPrefix + name, cleanupPrefix + name]) {
				owned.add(key);
				const descriptor = await backblazeS3Upload(storage.credentials, key, integrity);
				const result = await fetch(descriptor.uploadUrl, {
					method: 'PUT',
					headers: descriptor.headers,
					body: bytes,
					signal: AbortSignal.timeout(30_000)
				});
				assert.equal(result.status, 200);
				await result.arrayBuffer();
			}
			await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: cleanupPrefix + name }));
			const unfinishedKey = cleanupPrefix + name.replace(/_1$/, '_2');
			owned.add(unfinishedKey);
			await client.send(new CreateMultipartUploadCommand({ Bucket: bucket, Key: unfinishedKey }));
			const adapter = new ProviderRecoveryStorage();
			const target = { providerId: 1, prefix: cleanupPrefix, credentials: storage.credentials };
			await adapter.probe(target);
			let cursor = {},
				done = false;
			for (let step = 0; step < 20 && !done; step++) {
				({ cursor, done } = await adapter.step(target, cursor));
			}
			assert.equal(done, true, 'S3 cleanup must finish within the fixture bound');
			assert.equal((await versions()).filter((o) => o.Key.startsWith(cleanupPrefix)).length, 0);
			const remaining = await client.send(
				new ListMultipartUploadsCommand({ Bucket: bucket, Prefix: cleanupPrefix })
			);
			assert.equal(remaining.Uploads?.length ?? 0, 0);
			assert.ok(
				await findBackblazeS3Upload(
					storage.credentials,
					sentinel,
					integrity.content_sha1,
					bytes.length
				),
				'Cleanup must preserve a sibling object outside the retired prefix'
			);
		} finally {
			try {
				if (client && bucket) {
					const pending = await client.send(
						new ListMultipartUploadsCommand({ Bucket: bucket, Prefix: `${fixture.remoteId}/` })
					);
					assert.ok(!pending.IsTruncated);
					for (const upload of pending.Uploads ?? []) {
						if (upload.Key && owned.has(upload.Key))
							await client.send(
								new AbortMultipartUploadCommand({
									Bucket: bucket,
									Key: upload.Key,
									UploadId: upload.UploadId
								})
							);
					}
					const objects = await versions();
					if (objects.length) {
						const result = await client.send(
							new DeleteObjectsCommand({
								Bucket: bucket,
								Delete: { Objects: objects, Quiet: true }
							})
						);
						assert.ok(!result.Errors?.length, 'Generated fixture cleanup must succeed');
					}
					assert.equal((await versions()).length, 0);
				}
			} finally {
				client?.destroy();
				await sql.end();
			}
		}
	}
);
