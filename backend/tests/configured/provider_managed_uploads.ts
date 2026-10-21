import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import https from 'node:https';
import { setTimeout as delay } from 'node:timers/promises';
import {
	GetObjectCommand,
	HeadObjectCommand,
	ListMultipartUploadsCommand,
	ListObjectVersionsCommand,
	ListObjectsV2Command
} from '@aws-sdk/client-s3';
import type { Db } from '../../src/lib/server/db';
import { file } from '../../src/lib/server/db/schema';
import { and, eq } from 'drizzle-orm';
import { FileKeys as F, StorageProvider } from '../../src/lib/server/db/keys';
import {
	createRecoveryS3Client,
	ProviderRecoveryStorage,
	type RecoveryTarget
} from '../../src/lib/server/recoveryStorage';

export async function checkManagedProviderUploads(input: {
	db: Db;
	userId: number;
	storageId: number;
	target: RecoveryTarget;
	call: (
		action: 'prepare' | 'complete' | 'report',
		body: Record<string, unknown>
	) => Promise<{ status: number; body: any }>;
	drain: (now: number) => Promise<unknown>;
	download: (partName: string) => Promise<{ success: number; data?: unknown }>;
	onCleanupVerified?: () => void;
}) {
	assert.equal(process.env.FIFE_RUN_PROVIDER_WRITE_CHECKS, '1');
	assert.match(input.target.prefix, /^fife-provider-url-[a-f0-9-]{36}\/$/);
	const { target } = input;
	const client = createRecoveryS3Client(target),
		cleanup = new ProviderRecoveryStorage();
	const Bucket = target.credentials.bucketName as string;
	const requestOptions = () => ({ abortSignal: AbortSignal.timeout(20_000) });
	async function resumeIo<T>(action: () => Promise<T>): Promise<T> {
		for (let attempt = 0; ; attempt++) {
			try {
				return await action();
			} catch (error) {
				const e = error as {
					code?: string;
					name?: string;
					$metadata?: { httpStatusCode?: number };
				};
				const retryable =
					['storage_cleanup_blocked', 'storage_unavailable'].includes(e.code ?? '') ||
					['TimeoutError', 'AbortError', 'ECONNRESET', 'ETIMEDOUT'].includes(
						e.name ?? e.code ?? ''
					) ||
					(e.$metadata?.httpStatusCode ?? 0) >= 500;
				if (attempt >= 2 || !retryable) throw error;
				await delay(1_000);
			}
		}
	}
	const missing = async (Key: string) => {
		try {
			await client.send(new HeadObjectCommand({ Bucket, Key }), requestOptions());
			return false;
		} catch (e) {
			if ((e as any).$metadata?.httpStatusCode === 404) return true;
			throw new Error('Fixture HEAD unavailable');
		}
	};
	async function prepare(length = 131_073) {
		const bytes = randomBytes(length),
			hash = createHash('sha256').update(bytes).digest('base64url');
		const body = {
			id: randomUUID(),
			receipt: randomBytes(32).toString('base64url'),
			storage_id: input.storageId,
			file_id: `${hash}_1`,
			content_length: bytes.length,
			content_sha1: createHash('sha1').update(bytes).digest('hex'),
			content_md5: createHash('md5').update(bytes).digest('base64'),
			part_metadata: { cipher: 'fixture-encrypted-key', nonce: 'fixture-nonce' }
		};
		await input.db.insert(file).values({
			[F.USER_ID]: input.userId,
			[F.DEVICE_UUID]: 'fixture-device',
			[F.FILE_HASH]: hash,
			[F.STORAGE_ID]: input.storageId,
			[F.PROVIDER_ID]: target.providerId
		});
		const result = await input.call('prepare', body);
		assert.equal(
			result.status,
			200,
			`Managed initiation failed (safe code: ${result.body.message ?? 'unavailable'})`
		);
		assert.equal(result.body.success, 1);
		assert.equal(result.body.data.state, 'upload');
		return {
			body,
			bytes,
			descriptor: result.body.data,
			Key: `${target.prefix}${body.file_id}~${body.id}`
		};
	}
	async function drainUntilDeleted(body: Record<string, unknown>) {
		for (let i = 0; i < 6; i++) {
			await input.drain(Date.now() + (i + 1) * 120_001);
			const reply = await input.call('report', body);
			if (reply.status === 200 && reply.body.data?.state === 'deleted') return;
			await delay(250);
		}
		assert.fail('Managed cleanup did not produce a verified deleted acknowledgement');
	}
	try {
		const normal = await prepare();
		const uploaded = await fetch(normal.descriptor.uploadUrl, {
			method: 'PUT',
			headers: normal.descriptor.headers,
			body: normal.bytes,
			redirect: 'error',
			signal: AbortSignal.timeout(30_000)
		});
		assert.equal(uploaded.ok, true, `Managed part upload failed (HTTP ${uploaded.status})`);
		await uploaded.arrayBuffer();
		assert.equal(
			await missing(normal.Key),
			true,
			'Uploading a part must not publish a completed object'
		);
		const completed = await input.call('complete', normal.body);
		assert.equal(completed.status, 200);
		assert.equal(
			completed.body.data?.state,
			'complete',
			'Only server finalization publishes an object'
		);
		if ([StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(target.providerId))
			assert.ok(completed.body.data.fileId);
		assert.equal((await input.call('complete', normal.body)).body.data?.state, 'complete');
		const oldRead = await input.download(normal.body.file_id);
		assert.equal(oldRead.success, 1);
		assert.equal(typeof oldRead.data, 'string', 'Legacy download response remains a URL string');
		const legacyDownload = await fetch(oldRead.data as string, {
			redirect: 'error',
			signal: AbortSignal.timeout(30_000)
		});
		assert.equal(legacyDownload.ok, true);
		assert.deepEqual(Buffer.from(await legacyDownload.arrayBuffer()), normal.bytes);
		const restored = await client.send(
			new GetObjectCommand({ Bucket, Key: normal.Key }),
			requestOptions()
		);
		assert.equal(
			createHash('sha256')
				.update(await restored.Body!.transformToByteArray())
				.digest('hex'),
			createHash('sha256').update(normal.bytes).digest('hex')
		);
		const protectedFile = await input.call('report', normal.body);
		assert.equal(protectedFile.status, 200);
		assert.equal(protectedFile.body.data?.state, 'committed');
		await input.drain(Date.now() + 48 * 60 * 60_000);
		assert.equal(
			await missing(normal.Key),
			false,
			'Live committed objects cannot be garbage-collected by age'
		);
		await input.db
			.update(file)
			.set({ [F.DELETED]: 1 })
			.where(
				and(
					eq(file[F.USER_ID], input.userId),
					eq(file[F.FILE_HASH], normal.body.file_id.slice(0, 43))
				)
			);
		assert.equal((await input.call('report', normal.body)).status, 202);
		await drainUntilDeleted(normal.body);
		assert.equal(await missing(normal.Key), true);

		// Keep a real UploadPart body unfinished while retirement/abort runs.
		const late = await prepare(256 * 1024 + 19);
		let request!: ReturnType<typeof https.request>;
		const outcome = new Promise<number>((resolve) => {
			request = https.request(
				late.descriptor.uploadUrl,
				{ method: 'PUT', headers: late.descriptor.headers },
				(response) => {
					response.resume();
					response.on('end', () => resolve(response.statusCode ?? 0));
				}
			);
			request.on('error', () => resolve(0));
			request.setTimeout(20_000, () => request.destroy());
			request.flushHeaders();
			request.write(late.bytes.subarray(0, 64 * 1024));
		});
		try {
			await delay(1_000);
			assert.equal(await missing(late.Key), true);
			assert.equal((await input.call('report', late.body)).body.data?.state, 'cleanup_pending');
			await input.drain(Date.now() + 1);
			request.end(late.bytes.subarray(64 * 1024));
			await outcome;
			await drainUntilDeleted(late.body);
			assert.equal((await input.call('complete', late.body)).body.data?.state, 'deleted');
			assert.equal(await missing(late.Key), true, 'A late body cannot publish after retirement');
		} finally {
			request.destroy();
		}

		// No completion callback: the server still knows how to abort the upload.
		const abandoned = await prepare(17);
		await fetch(abandoned.descriptor.uploadUrl, {
			method: 'PUT',
			headers: abandoned.descriptor.headers,
			body: abandoned.bytes,
			redirect: 'error',
			signal: AbortSignal.timeout(30_000)
		}).then(async (r) => {
			assert.equal(r.ok, true);
			await r.arrayBuffer();
		});
		for (let i = 0; i < 8; i++) {
			await input.drain(Date.now() + 24 * 60 * 60_000 + (i + 1) * 120_001);
		}
		const abandonedResult = await input.call('report', abandoned.body);
		assert.equal(abandonedResult.status, 200);
		assert.equal(
			abandonedResult.body.data?.state,
			'deleted',
			'Cleanup must finish without a client callback'
		);
		assert.equal(await missing(abandoned.Key), true);
	} finally {
		try {
			let cursor: Record<string, unknown> = {};
			for (let i = 0; i < 100; i++) {
				const r = await resumeIo(() => cleanup.step(target, cursor));
				cursor = r.cursor;
				if (r.done) break;
			}
			const unfinished = await resumeIo(() =>
				client.send(
					new ListMultipartUploadsCommand({ Bucket, Prefix: target.prefix }),
					requestOptions()
				)
			);
			assert.equal(unfinished.IsTruncated, false);
			assert.equal(unfinished.Uploads?.length ?? 0, 0);
			const objects = await resumeIo(() =>
				client.send(new ListObjectsV2Command({ Bucket, Prefix: target.prefix }), requestOptions())
			);
			assert.equal(objects.IsTruncated, false);
			assert.equal(objects.Contents?.length ?? 0, 0);
			if (target.providerId !== StorageProvider.CLOUDFLARE) {
				const versions = await resumeIo(() =>
					client.send(
						new ListObjectVersionsCommand({ Bucket, Prefix: target.prefix }),
						requestOptions()
					)
				);
				assert.equal(versions.IsTruncated, false);
				assert.equal(versions.Versions?.length ?? 0, 0);
				assert.equal(versions.DeleteMarkers?.length ?? 0, 0);
			}
			input.onCleanupVerified?.();
		} finally {
			client.destroy();
		}
	}
}
