import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import {
	ListMultipartUploadsCommand,
	ListObjectsV2Command,
	ListObjectVersionsCommand,
	PutObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { StorageProvider } from '../../src/lib/server/db/keys';
import { createGenericS3Client, type GenericS3Credentials } from '../../src/lib/server/s3';
import {
	createRecoveryS3Client,
	ProviderRecoveryStorage,
	type RecoveryTarget
} from '../../src/lib/server/recoveryStorage';

// Imported only by the explicitly opted-in configured-credentials runner.
// Cloud mutations are restricted to canonical part names under a generated UUID.
export async function checkProviderTransfers(
	target: RecoveryTarget & {
		call: (action: string, body: Record<string, unknown>) => Promise<any>;
	}
) {
	assert.equal(process.env.FIFE_RUN_PROVIDER_WRITE_CHECKS, '1');
	assert.match(target.prefix, /^fife-provider-url-[a-f0-9-]{36}\/$/);
	const Bucket = target.credentials.bucketName as string;
	assert.ok(Bucket);
	const client = createRecoveryS3Client(target);
	const signingClient = createGenericS3Client(target.credentials as GenericS3Credentials);
	const cleanup = new ProviderRecoveryStorage();
	const sendOptions = () => ({ abortSignal: AbortSignal.timeout(20_000) });
	// The production cleanup worker also resumes retryable steps. Exercise that
	// boundary here while keeping every assertion and final empty-prefix check.
	async function resumeIo<T>(action: () => Promise<T>): Promise<T> {
		for (let attempt = 0; ; attempt++) {
			try {
				return await action();
			} catch (error) {
				const fault = error as {
					code?: string;
					name?: string;
					$metadata?: { httpStatusCode?: number };
				};
				const retryable =
					['storage_access_required', 'storage_cleanup_blocked', 'storage_unavailable'].includes(
						fault.code ?? ''
					) ||
					['AbortError', 'TimeoutError'].includes(fault.name ?? '') ||
					(fault.$metadata?.httpStatusCode ?? 0) >= 500;
				if (attempt >= 2 || !retryable) throw error;
				await delay(1_000);
			}
		}
	}
	const digest = (bytes: Uint8Array, algorithm = 'sha256') =>
		createHash(algorithm).update(bytes).digest('hex');
	const put = (url: string, bytes: Uint8Array, headers: Record<string, string>) =>
		fetch(url, {
			method: 'PUT',
			body: bytes as BodyInit,
			headers,
			redirect: 'error',
			signal: AbortSignal.timeout(30_000)
		});
	try {
		await resumeIo(() => cleanup.probe(target));
		if (target.providerId === StorageProvider.BACKBLAZE) {
			const bytes = randomBytes(37);
			const file_id = `${createHash('sha256').update(bytes).digest('base64url')}_1`;
			const legacy = await target.call('get-upload-url', {});
			assert.equal(legacy.success, 1, 'Older clients must still obtain native B2 authorization');
			assert.equal(typeof legacy.data.uploadUrl, 'string');
			assert.equal(typeof legacy.data.authorizationToken, 'string');
			const uploaded = await fetch(legacy.data.uploadUrl, {
				method: 'POST',
				body: bytes,
				redirect: 'error',
				signal: AbortSignal.timeout(30_000),
				headers: {
					authorization: legacy.data.authorizationToken,
					'X-Bz-File-Name': encodeURIComponent(`${target.prefix}${file_id}`),
					'X-Bz-Content-Sha1': digest(bytes, 'sha1'),
					'Content-Type': 'application/octet-stream',
					'Content-Length': String(bytes.length)
				}
			});
			assert.equal(uploaded.status, 200, 'Older native B2 upload must still work');
			assert.equal((await uploaded.json()).contentSha1, digest(bytes, 'sha1'));
			const download = await target.call('get-download-url', { file_id });
			assert.equal(download.success, 1);
			const response = await fetch(download.data, {
				redirect: 'error',
				signal: AbortSignal.timeout(30_000)
			});
			assert.equal(response.status, 200);
			assert.equal(digest(new Uint8Array(await response.arrayBuffer())), digest(bytes));
		}
		// Two distinct snapshots model immutable objects before and after an edit.
		for (const length of [4097, 8193]) {
			const bytes = randomBytes(length);
			const file_id = `${createHash('sha256').update(bytes).digest('base64url')}_1`;
			const result = await target.call('get-upload-url', {
				file_id,
				...(target.providerId === StorageProvider.BACKBLAZE
					? {
							upload_protocol: 's3',
							content_length: bytes.length,
							content_sha1: digest(bytes, 'sha1'),
							content_md5: createHash('md5').update(bytes).digest('base64')
						}
					: {})
			});
			assert.equal(result.success, 1, 'Local upload route rejected fixture request');
			const url = typeof result.data === 'string' ? result.data : result.data.uploadUrl;
			assert.equal(new URL(url).searchParams.get('X-Amz-Expires'), '900');
			const headers =
				typeof result.data === 'string'
					? {
							'Content-Type': 'application/octet-stream',
							'Content-Length': String(bytes.length)
						}
					: result.data.headers;
			const uploaded = await put(url, bytes, headers);
			assert.equal(uploaded.ok, true, `Generated upload failed (HTTP ${uploaded.status})`);
			await uploaded.arrayBuffer();
			const download = await target.call('get-download-url', { file_id });
			assert.equal(download.success, 1, 'Local download route rejected fixture request');
			const response = await fetch(download.data, {
				redirect: 'error',
				signal: AbortSignal.timeout(30_000)
			});
			assert.equal(response.status, 200);
			assert.equal(digest(new Uint8Array(await response.arrayBuffer())), digest(bytes));
		}
		// A real short-lived signature proves provider expiry enforcement without
		// changing the application's 900-second policy or waiting 15 minutes.
		const bytes = randomBytes(17);
		const Key = `${target.prefix}${createHash('sha256').update(bytes).digest('base64url')}_1`;
		const expired = await getSignedUrl(
			signingClient,
			new PutObjectCommand({
				Bucket,
				Key,
				ContentType: 'application/octet-stream',
				ContentMD5: createHash('md5').update(bytes).digest('base64')
			}),
			{ expiresIn: 10 }
		);
		const headers = {
			'Content-Type': 'application/octet-stream',
			'Content-Length': String(bytes.length),
			'Content-MD5': createHash('md5').update(bytes).digest('base64')
		};
		const initial = await put(expired, bytes, headers);
		assert.equal(
			initial.ok,
			true,
			`Short-lived signature failed before expiry (HTTP ${initial.status})`
		);
		await initial.arrayBuffer();
		await delay(11_000);
		const rejected = await put(expired, bytes, headers);
		const rejection = await rejected.text();
		assert.ok([401, 403].includes(rejected.status), 'Expired upload must be rejected');
		assert.equal(
			/expir(?:ed|ation)|ExpiredRequest/i.test(rejection),
			true,
			'Provider must identify expiry rather than a bad signature'
		);
	} finally {
		try {
			let cursor: Record<string, unknown> = {};
			let done = false;
			for (let attempt = 0; attempt < 40 && !done; attempt++) {
				const step = await resumeIo(() => cleanup.step(target, cursor));
				cursor = step.cursor;
				done = step.done;
			}
			assert.equal(done, true, 'Generated-prefix cleanup did not finish');
			const current = await client.send(
				new ListObjectsV2Command({ Bucket, Prefix: target.prefix }),
				sendOptions()
			);
			assert.equal(current.Contents?.length ?? 0, 0);
			assert.equal(current.IsTruncated, false);
			if (target.providerId !== StorageProvider.CLOUDFLARE) {
				const versions = await client.send(
					new ListObjectVersionsCommand({ Bucket, Prefix: target.prefix }),
					sendOptions()
				);
				assert.equal(versions.Versions?.length ?? 0, 0);
				assert.equal(versions.DeleteMarkers?.length ?? 0, 0);
				assert.equal(versions.IsTruncated, false);
			}
			const uploads = await client.send(
				new ListMultipartUploadsCommand({ Bucket, Prefix: target.prefix }),
				sendOptions()
			);
			assert.equal(uploads.Uploads?.length ?? 0, 0);
			assert.equal(uploads.IsTruncated, false);
		} finally {
			client.destroy();
			signingClient.destroy();
		}
	}
}
