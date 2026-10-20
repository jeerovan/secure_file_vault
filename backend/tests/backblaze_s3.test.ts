import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';
import { HeadObjectCommand, DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { eq } from 'drizzle-orm';
import * as tables from '../src/lib/server/db/schema';
import {
	UserKeys as U,
	UserDeviceKeys as V,
	ProviderKeys as P,
	CredentialKeys as C,
	StorageKeys as S,
	FileKeys as F,
	PartKeys as B,
	StorageProvider,
	ErrorCode
} from '../src/lib/server/db/keys';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

test(
	'Backblaze S3 migration preserves the legacy client contract',
	{ skip: !recoveryTestUrl },
	async (t) => {
		const database = await createRecoveryDatabase();
		Object.assign(process.env, {
			DATABASE_URL: database.url,
			SUPABASE_URL: 'https://auth.example.test',
			SUPABASE_KEY: 'fixture',
			NEON_JWKS: 'https://auth.example.test/jwks',
			REVENUECAT_SECRET_KEY: 'fixture',
			REVENUECAT_WEBHOOK_SECRET: 'fixture',
			FCM_KEY: 'fixture',
			LOCAL_TEST_AUTH_ENABLED: 'false'
		});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		const originalFetch = globalThis.fetch,
			originalSend = S3Client.prototype.send;
		const nativeCalls: string[] = [],
			commands: { name: string; input: any }[] = [];
		let headMode: 'match' | 'missing' | 'denied' = 'match';
		let closeRoutes: (() => Promise<void>) | undefined;
		const partName = `${'A'.repeat(43)}_1`,
			sha1 = 'a'.repeat(40),
			md5 = Buffer.alloc(16, 3).toString('base64');
		const credentials = {
			appId: 'fixture-access',
			appKey: 'fixture-secret',
			accountId: 'fixture-account',
			authorizationToken: 'fixture-native-token',
			apiUrl: 'https://api004.backblazeb2.com',
			downloadUrl: 'https://f004.backblazeb2.com',
			bucketId: 'fixture-bucket-id',
			bucketName: 'fixture-bucket',
			s3ApiUrl: 'https://s3.us-west-004.backblazeb2.com',
			endpoint: 'https://s3.us-west-004.backblazeb2.com',
			region: 'us-west-004',
			forcePathStyle: true
		};
		globalThis.fetch = async (input) => {
			const endpoint = new URL(String(input)).pathname.split('/').at(-1)!;
			nativeCalls.push(endpoint);
			if (endpoint === 'b2_get_upload_url')
				return Response.json({
					uploadUrl: 'https://native.example.test/upload',
					authorizationToken: 'fixture-upload-token'
				});
			if (endpoint === 'b2_list_file_names')
				return Response.json({
					files: [
						{
							fileId: 'fixture-version',
							fileName: `fixture-first/${partName}`,
							contentSha1: sha1,
							contentLength: 37,
							action: 'upload'
						}
					]
				});
			if (endpoint === 'b2_delete_file_version')
				return Response.json({ fileId: 'fixture-version' });
			throw new Error('Unexpected native API call in migration fixture');
		};
		S3Client.prototype.send = async function (command: any) {
			commands.push({ name: command.constructor.name, input: command.input });
			if (command instanceof HeadObjectCommand) {
				if (headMode !== 'match')
					throw Object.assign(new Error('fixture provider failure'), {
						name: headMode === 'missing' ? 'NotFound' : 'AccessDenied',
						$metadata: { httpStatusCode: headMode === 'missing' ? 404 : 403 }
					});
				return { VersionId: 'fixture-version', Metadata: { sha1 }, ContentLength: 37 };
			}
			if (command instanceof DeleteObjectCommand) return { $metadata: { httpStatusCode: 204 } };
			throw new Error('Unexpected S3 command in migration fixture');
		} as typeof S3Client.prototype.send;
		try {
			const accounts = await database.db
				.insert(tables.user)
				.values(
					['first', 'second'].map((name) => ({
						[U.REMOTE_AUTH_ID]: `fixture-${name}`,
						[U.EMAIL]: `${name}@example.test`,
						[U.CIPHER]: 'fixture',
						[U.NONCE]: 'fixture'
					}))
				)
				.returning();
			for (const account of accounts)
				await database.db.insert(tables.userDevice).values({
					[V.USER_ID]: account[U.ID],
					[V.DEVICE_UUID]: 'fixture-device',
					[V.TITLE]: 'Fixture',
					[V.ACTIVE]: 1
				});
			await database.db.insert(tables.provider).values({
				[P.ID]: StorageProvider.BACKBLAZE,
				[P.TITLE]: 'Backblaze',
				[P.FREE_BYTES]: 1000,
				[P.PRIORITY]: 1
			});
			const stores: any[] = [];
			for (const account of accounts) {
				const [credential] = await database.db
					.insert(tables.credential)
					.values({
						[C.USER_ID]: account[U.ID],
						[C.PROVIDER_ID]: StorageProvider.BACKBLAZE,
						[C.CREDENTIALS]: credentials
					})
					.returning();
				const [storage] = await database.db
					.insert(tables.storage)
					.values({
						[S.USER_ID]: account[U.ID],
						[S.CREDENTIAL_ID]: credential[C.ID],
						[S.LIMIT_BYTES]: 1000,
						[S.LIMIT_FREE_BYTES]: 1000,
						[S.JSON]: {}
					})
					.returning();
				stores.push(storage);
			}
			const platform = {
				env: {
					HYPERDRIVE: { connectionString: database.url },
					FIFE_AUTH_CACHE: {
						get: async () => ({
							authorized: true,
							userId: accounts[0][U.ID],
							remoteAuthId: accounts[0][U.REMOTE_AUTH_ID],
							email: accounts[0][U.EMAIL]
						}),
						put: async () => {}
					}
				}
			};
			const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
			closeRoutes = () => dbModule.getDb(platform, true).$client.end();
			const routes: Record<string, any> = {};
			for (const name of ['get-upload-url', 'get-download-url', 'find-uploaded-file'])
				routes[name] = await vite.ssrLoadModule(`/src/routes/api/b2/${name}/+server.ts`);
			const call = async (name: string, body: unknown, headers: Record<string, string> = {}) => {
				const request = new Request(`https://app.example.test/api/b2/${name}`, {
					method: 'POST',
					headers: {
						authorization: 'Bearer fixture-token',
						service: 'neon',
						device_uuid: 'fixture-device',
						'content-type': 'application/json',
						...headers
					},
					body: JSON.stringify(body)
				});
				return (await routes[name].POST({ request, platform })).json();
			};
			const input = {
				storage_id: stores[0][S.ID],
				upload_protocol: 's3',
				file_id: partName,
				content_sha1: sha1,
				content_md5: md5,
				content_length: 37
			};
			await t.test('older clients still receive native POST authorization fields', async () => {
				const issuedAt = Date.now();
				const result = await call('get-upload-url', { storage_id: stores[0][S.ID] });
				assert.equal(result.success, 1);
				assert.equal(result.data.uploadUrl, 'https://native.example.test/upload');
				assert.equal(result.data.authorizationToken, 'fixture-upload-token');
				const [capability] = await database.db.select().from(tables.vaultUploadCapability);
				assert.ok(capability);
				assert.equal(capability.generation, 'legacy');
				assert.ok(capability.expiresAt >= issuedAt + 86400_000);
			});
			await t.test(
				'updated clients receive a scoped S3 PUT URL with integrity headers and 15-minute expiry',
				async () => {
					const nativeBefore = nativeCalls.length;
					const result = await call('get-upload-url', input);
					assert.equal(result.success, 1);
					assert.equal(result.data.protocol, 's3');
					assert.equal(result.data.method, 'PUT');
					const url = new URL(result.data.uploadUrl);
					assert.equal(url.origin, credentials.endpoint);
					assert.equal(
						decodeURIComponent(url.pathname),
						`/fixture-bucket/fixture-first/${partName}`
					);
					assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
					for (const header of ['content-md5', 'content-length', 'content-type', 'x-amz-meta-sha1'])
						assert.ok(url.searchParams.get('X-Amz-SignedHeaders')?.split(';').includes(header));
					assert.equal(result.data.headers['Content-MD5'], md5);
					assert.equal(result.data.headers['x-amz-meta-sha1'], sha1);
					assert.equal(nativeCalls.length, nativeBefore);
					const [capability] = await database.db.select().from(tables.vaultUploadCapability);
					assert.ok(
						capability.expiresAt >= Date.now() + 86000_000,
						'A new short-lived URL must not replace the earlier native token expiry'
					);
				}
			);
			await t.test(
				'invalid S3 capabilities cannot fall back to reusable native authorization',
				async () => {
					for (const change of [
						{ file_id: '../escape' },
						{ content_length: -1 },
						{ content_length: 101 * 1024 * 1024 + 1 },
						{ content_length: 1.5 },
						{ content_sha1: 'bad' },
						{ content_md5: 'bad' },
						{ upload_protocol: 'unknown' }
					]) {
						const nativeBefore = nativeCalls.length;
						assert.equal((await call('get-upload-url', { ...input, ...change })).success, 0);
						assert.equal(nativeCalls.length, nativeBefore);
					}
					assert.equal(
						(await call('get-upload-url', { ...input, storage_id: stores[1][S.ID] })).success,
						0
					);
				}
			);
			await t.test('S3 recovery matches the actual object length, SHA1 and version', async () => {
				const nativeBefore = nativeCalls.length;
				assert.deepEqual(await call('find-uploaded-file', input), {
					success: 1,
					data: { fileId: 'fixture-version' }
				});
				assert.ok(
					commands.some(
						(command) =>
							command.name === 'HeadObjectCommand' &&
							command.input.Key === `fixture-first/${partName}`
					)
				);
				assert.equal(nativeCalls.length, nativeBefore);
				assert.equal(
					(await call('find-uploaded-file', { ...input, content_sha1: 'b'.repeat(40) })).data,
					null
				);
				assert.equal(
					(await call('find-uploaded-file', { ...input, content_length: 38 })).data,
					null
				);
				headMode = 'missing';
				assert.deepEqual(await call('find-uploaded-file', input), { success: 1, data: null });
				headMode = 'denied';
				assert.equal((await call('find-uploaded-file', input)).success, 0);
				headMode = 'match';
			});
			await t.test(
				'new reset manifests preserve per-user S3 settings for version cleanup',
				async () => {
					const module = await vite.ssrLoadModule('/src/lib/server/recoveryReset.ts');
					const targets = await module.recoveryTargets(
						database.db,
						accounts[0][U.ID],
						'fixture-first/'
					);
					assert.equal(targets.length, 1);
					assert.equal(targets[0].credentials.s3ApiUrl, credentials.endpoint);
					assert.equal(targets[0].credentials.region, credentials.region);
					assert.equal(targets[0].credentials.forcePathStyle, true);
				}
			);
			await t.test(
				'downloads retain the existing string response and a scoped S3 URL',
				async () => {
					const result = await call('get-download-url', {
						storage_id: stores[0][S.ID],
						file_id: partName
					});
					assert.equal(result.success, 1);
					assert.equal(typeof result.data, 'string');
					assert.equal(
						decodeURIComponent(new URL(result.data).pathname).endsWith(
							`/fixture-first/${partName}`
						),
						true
					);
				}
			);
			await t.test(
				'deletion uses the exact stored native-compatible S3 version and is idempotent',
				async () => {
					const [file] = await database.db
						.insert(tables.file)
						.values({
							[F.USER_ID]: accounts[0][U.ID],
							[F.DEVICE_UUID]: 'fixture-device',
							[F.FILE_HASH]: 'A'.repeat(43),
							[F.PARTS]: 1,
							[F.PROVIDER_ID]: StorageProvider.BACKBLAZE,
							[F.STORAGE_ID]: stores[0][S.ID]
						})
						.returning();
					await database.db.insert(tables.part).values({
						[B.USER_ID]: accounts[0][U.ID],
						[B.DEVICE_UUID]: 'fixture-device',
						[B.FILE_ID]: file[F.ID],
						[B.PART_NUMBER]: 1,
						[B.PART_SIZE]: 37,
						[B.JSON]: { fileId: 'fixture-version' }
					});
					await database.db
						.update(tables.storage)
						.set({ [S.USED_BYTES]: 37 })
						.where(eq(tables.storage[S.ID], stores[0][S.ID]));
					const worker = await vite.ssrLoadModule('/src/lib/server/deleteWorker.ts');
					const nativeBefore = nativeCalls.length;
					await worker.deleteFileFromStorage(database.db, file);
					assert.ok(
						commands.some(
							(command) =>
								command.name === 'DeleteObjectCommand' &&
								command.input.Key === `fixture-first/${partName}` &&
								command.input.VersionId === 'fixture-version'
						)
					);
					assert.equal(nativeCalls.length, nativeBefore);
					await worker.deleteFileFromStorage(database.db, file);
					const [storage] = await database.db
						.select()
						.from(tables.storage)
						.where(eq(tables.storage[S.ID], stores[0][S.ID]));
					assert.equal(storage[S.USED_BYTES], 0);
				}
			);
			await t.test('revoked devices cannot obtain either upload protocol', async () => {
				await database.db
					.update(tables.userDevice)
					.set({ [V.ACTIVE]: 0 })
					.where(eq(tables.userDevice[V.USER_ID], accounts[0][U.ID]));
				for (const body of [input, { storage_id: stores[0][S.ID] }])
					assert.equal((await call('get-upload-url', body)).message, ErrorCode.NO_DEVICE);
			});
		} finally {
			globalThis.fetch = originalFetch;
			S3Client.prototype.send = originalSend;
			await closeRoutes?.();
			await vite.close();
			await database.close();
		}
	}
);
