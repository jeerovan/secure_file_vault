import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import type { ClientRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { setTimeout as delay } from 'node:timers/promises';
import {
	GetObjectCommand,
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

/** Deliberately slow, real PUTs; never targets an existing account's prefix. */
export async function checkProviderInFlightUpload(
	target: RecoveryTarget,
	diagnostic: (message: string) => void
) {
	assert.equal(process.env.FIFE_RUN_PROVIDER_WRITE_CHECKS, '1');
	assert.equal(process.env.FIFE_RUN_PROVIDER_IN_FLIGHT_CHECKS, '1');
	assert.match(target.prefix, /^fife-provider-url-[a-f0-9-]{36}\/$/);
	const Bucket = target.credentials.bucketName as string;
	assert.ok(Bucket);
	const client = createRecoveryS3Client(target);
	const signer = createGenericS3Client(target.credentials as GenericS3Credentials);
	const cleanup = new ProviderRecoveryStorage();
	const bytes = randomBytes(64 * 1024);
	const Key = `${target.prefix}${createHash('sha256').update(bytes).digest('base64url')}_1`;
	const contentMd5 = createHash('md5').update(bytes).digest('base64');
	const options = () => ({ abortSignal: AbortSignal.timeout(20_000) });
	let request: ClientRequest | undefined;
	async function empty() {
		const current = await client.send(
			new ListObjectsV2Command({ Bucket, Prefix: target.prefix }),
			options()
		);
		assert.equal(current.Contents?.length ?? 0, 0);
		assert.equal(current.IsTruncated, false);
		if (target.providerId !== StorageProvider.CLOUDFLARE) {
			const versions = await client.send(
				new ListObjectVersionsCommand({ Bucket, Prefix: target.prefix }),
				options()
			);
			assert.equal(versions.Versions?.length ?? 0, 0);
			assert.equal(versions.DeleteMarkers?.length ?? 0, 0);
			assert.equal(versions.IsTruncated, false);
		}
		const multipart = await client.send(
			new ListMultipartUploadsCommand({ Bucket, Prefix: target.prefix }),
			options()
		);
		assert.equal(multipart.Uploads?.length ?? 0, 0);
		assert.equal(multipart.IsTruncated, false);
	}
	async function sweep() {
		let cursor: Record<string, unknown> = {};
		for (let step = 0; step < 40; step++) {
			const result = await cleanup.step(target, cursor);
			cursor = result.cursor;
			if (result.done) return;
		}
		assert.fail('Generated-prefix cleanup did not converge');
	}
	try {
		await cleanup.probe(target);
		await empty();
		const url = await getSignedUrl(
			signer,
			new PutObjectCommand({
				Bucket,
				Key,
				ContentType: 'application/octet-stream',
				ContentMD5: contentMd5
			}),
			{ expiresIn: 15 }
		);
		const startedAt = Date.now();
		const response = new Promise<{ status: number; body: string; closed: boolean }>((resolve) => {
			request = httpsRequest(
				url,
				{
					method: 'PUT',
					headers: {
						'content-type': 'application/octet-stream',
						'content-length': String(bytes.length),
						'content-md5': contentMd5
					}
				},
				(incoming) => {
					let body = '';
					incoming.setEncoding('utf8');
					incoming.on('data', (chunk: string) => {
						if (body.length < 4096) body += chunk;
					});
					incoming.on('end', () =>
						resolve({ status: incoming.statusCode ?? 0, body, closed: false })
					);
					incoming.on('error', () =>
						resolve({ status: incoming.statusCode ?? 0, body: '', closed: true })
					);
				}
			);
			request.on('error', () => resolve({ status: 0, body: '', closed: true }));
			request.setTimeout(45_000, () => request?.destroy());
		});
		// The first byte reaches the TLS socket while the signature is valid.
		await new Promise<void>((resolve, reject) =>
			request!.write(bytes.subarray(0, 1), (error) =>
				error ? reject(new Error('Fixture request could not start')) : resolve()
			)
		);
		assert.ok(Date.now() - startedAt < 10_000, 'Fixture must start before signature expiry');
		await sweep();
		await empty();
		await delay(Math.max(0, startedAt + 17_000 - Date.now()));
		// Expired new requests must be rejected while the original PUT is open.
		const retry = await fetch(url, {
			method: 'PUT',
			body: bytes,
			headers: { 'content-type': 'application/octet-stream', 'content-md5': contentMd5 },
			redirect: 'error',
			signal: AbortSignal.timeout(20_000)
		});
		assert.ok([401, 403].includes(retry.status));
		assert.match(await retry.text(), /expir(?:ed|ation)|ExpiredRequest/i);
		request!.end(bytes.subarray(1));
		const result = await response;
		const published = result.status >= 200 && result.status < 300 && !result.closed;
		if (published) {
			const downloaded = await client.send(new GetObjectCommand({ Bucket, Key }), options());
			assert.deepEqual(Buffer.from(await downloaded.Body!.transformToByteArray()), bytes);
		} else {
			assert.ok(
				result.closed || [400, 401, 403, 408].includes(result.status),
				'Unexpected delayed-upload outcome'
			);
			await empty();
		}
		diagnostic(
			`Delayed PUT after expiry and an empty sweep: ${published ? 'published; expiry alone does not drain active requests' : `rejected (HTTP ${result.status}, closed=${result.closed})`}`
		);
	} finally {
		request?.destroy();
		try {
			await sweep();
			await empty();
		} finally {
			client.destroy();
			signer.destroy();
		}
	}
}
