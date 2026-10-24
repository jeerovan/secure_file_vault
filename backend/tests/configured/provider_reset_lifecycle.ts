import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { spawn, type ChildProcess } from 'node:child_process';
import { and, eq, ne } from 'drizzle-orm';
import type { ViteDevServer } from 'vite';
import {
	HeadObjectCommand,
	ListMultipartUploadsCommand,
	ListObjectsV2Command,
	ListObjectVersionsCommand
} from '@aws-sdk/client-s3';
import type { Db } from '../../src/lib/server/db';
import * as tables from '../../src/lib/server/db/schema';
import {
	UserKeys as U,
	UserDeviceKeys as V,
	CredentialKeys as C,
	StorageKeys as S,
	FileKeys as F,
	PartKeys as P,
	ItemKeys as I
} from '../../src/lib/server/db/keys';
import {
	createRecoveryS3Client,
	ProviderRecoveryStorage,
	type RecoveryTarget
} from '../../src/lib/server/recoveryStorage';

/** Real provider I/O; Neon proof is a fixture. The optional real-time run uses
 * the actual local cleanup launcher and its unmodified five-minute cadence. */
export async function checkProviderResetLifecycle(input: {
	db: Db;
	vite: ViteDevServer;
	databaseUrl: string;
	providerName: string;
	providerId: number;
	credentials: Record<string, unknown>;
	diagnostic: (message: string) => void;
	onCleanupVerified: () => void;
}) {
	assert.equal(process.env.FIFE_RUN_PROVIDER_WRITE_CHECKS, '1');
	assert.equal(process.env.FIFE_RUN_PROVIDER_RESET_CHECKS, '1');
	const realTime = process.env.FIFE_RUN_PROVIDER_REAL_TIME_RESET_CHECKS === '1';
	const databaseUrl = new URL(input.databaseUrl);
	assert.equal(databaseUrl.hostname, '127.0.0.1');
	assert.ok(databaseUrl.port && databaseUrl.port !== '5432');
	assert.match(databaseUrl.pathname, /^\/fife_recovery_[a-f0-9]{32}$/);
	const { db, vite } = input;
	const remoteId = `fife-provider-url-${randomUUID()}`;
	const target: RecoveryTarget = {
		providerId: input.providerId,
		prefix: `${remoteId}/`,
		credentials: input.credentials
	};
	input.diagnostic(`Generated reset cloud prefix: ${target.prefix}`);
	const cloud = new ProviderRecoveryStorage();
	const client = createRecoveryS3Client(target);
	const Bucket = input.credentials.bucketName as string;
	const options = () => ({ abortSignal: AbortSignal.timeout(20_000) });
	const [account] = await db
		.insert(tables.user)
		.values({
			[U.REMOTE_AUTH_ID]: remoteId,
			[U.EMAIL]: 'jeevan@jeero.one',
			[U.CIPHER]: randomBytes(48).toString('base64'),
			[U.NONCE]: randomBytes(24).toString('base64')
		})
		.returning();
	const userId = account[U.ID];
	const [credential] = await db
		.insert(tables.credential)
		.values({
			[C.USER_ID]: userId,
			[C.PROVIDER_ID]: input.providerId,
			[C.CREDENTIALS]: input.credentials
		})
		.returning();
	const [connection] = await db
		.insert(tables.storage)
		.values({
			[S.USER_ID]: userId,
			[S.CREDENTIAL_ID]: credential[C.ID],
			[S.LIMIT_BYTES]: 10 * 1024 ** 3,
			[S.LIMIT_FREE_BYTES]: 10 * 1024 ** 3,
			[S.PRIORITY]: 42,
			[S.JSON]: { title: 'Retained fixture connection' }
		})
		.returning();
	await db.insert(tables.userDevice).values({
		[V.USER_ID]: userId,
		[V.DEVICE_UUID]: 'retired-fixture-device',
		[V.TITLE]: 'Retiring device',
		[V.ACTIVE]: 1
	});
	const platform = {
		env: {
			HYPERDRIVE: { connectionString: input.databaseUrl },
			FIFE_AUTH_CACHE: {
				get: async () => ({
					authorized: true,
					userId,
					remoteAuthId: remoteId,
					email: account[U.EMAIL]
				}),
				put: async () => {}
			}
		}
	};
	const originalFetch = globalThis.fetch;
	const sessionCreatedAt = Date.now() - 60_000;
	globalThis.fetch = async (url, init) => {
		const hostname = new URL(url instanceof Request ? url.url : String(url)).hostname;
		if (hostname !== 'auth.example.test') return originalFetch(url, init);
		const old = new Headers(init?.headers).get('Cookie')?.includes('retired-session');
		return Response.json({
			session: {
				userId: remoteId,
				createdAt: new Date(sessionCreatedAt - (old ? 86400_000 : 0)).toISOString(),
				expiresAt: new Date(Date.now() + 7 * 86400_000).toISOString()
			},
			user: { id: remoteId, email: account[U.EMAIL], emailVerified: true }
		});
	};
	let stage = 'initial-upload';
	let failure: Error | undefined;
	let worker: ChildProcess | undefined;
	let workerLog = '';
	const oldHeaders = { device_uuid: 'retired-fixture-device' };
	const bootstrap = {
		'x-fife-vault-protocol': '1',
		'x-fife-recovery-protocol': '2',
		'x-fife-session': 'initiating-session'
	};
	async function call(path: string, body?: unknown, headers: Record<string, string> = {}) {
		const url = new URL(`https://local.example.test/api/${path}`);
		const route = await vite.ssrLoadModule(`/src/routes/api/${url.pathname.slice(5)}/+server.ts`);
		const response: Response = await route[body === undefined ? 'GET' : 'POST']({
			platform,
			url,
			request: new Request(url, {
				method: body === undefined ? 'GET' : 'POST',
				headers: {
					authorization: 'Bearer fixture-token',
					service: 'neon',
					'content-type': 'application/json',
					'x-fife-managed-uploads': '1',
					...headers
				},
				...(body === undefined ? {} : { body: JSON.stringify(body) })
			})
		});
		return { status: response.status, body: await response.json() };
	}
	const managed = await vite.ssrLoadModule('/src/lib/server/managedUpload.ts');
	const ports = await vite.ssrLoadModule('/src/lib/server/managedUploadStorage.ts');
	const resets = await vite.ssrLoadModule('/src/lib/server/recoveryCleanup.ts');
	const hash = (bytes: Buffer, algorithm: string, encoding: 'hex' | 'base64' | 'base64url') =>
		createHash(algorithm).update(bytes).digest(encoding);
	async function upload(
		bytes: Buffer,
		headers: Record<string, string>,
		keyLabel: string,
		complete = true
	) {
		const fileHash = hash(bytes, 'sha256', 'base64url');
		const changed = await call(
			'sync',
			{
				table_maps: [
					{
						table: 'files',
						changes: [
							{
								id: fileHash,
								updated_at: Date.now(),
								item_count: 1,
								parts: 1,
								uploaded_at: 0,
								deleted: 0,
								data: {}
							}
						]
					}
				]
			},
			headers
		);
		assert.equal(changed.body.success, 1, 'Normal file synchronization must succeed');
		const allocated = await call(
			'get-upload-storage-provider',
			{
				file_hash: fileHash,
				file_size: bytes.length
			},
			headers
		);
		assert.equal(allocated.body.success, 1, 'Normal storage allocation must succeed');
		assert.equal(allocated.body.data.storage_id, connection[S.ID], 'Reuse the retained connection');
		const request = {
			id: randomUUID(),
			receipt: randomBytes(32).toString('base64url'),
			storage_id: connection[S.ID],
			file_id: `${fileHash}_1`,
			content_length: bytes.length,
			content_sha1: hash(bytes, 'sha1', 'hex'),
			content_md5: hash(bytes, 'md5', 'base64'),
			part_metadata: { cipher: `${keyLabel}-encrypted-key`, nonce: `${keyLabel}-nonce` }
		};
		const prepared = await call('uploads/prepare', request, headers);
		assert.equal(prepared.status, 200);
		assert.equal(prepared.body.data?.state, 'upload');
		const uploaded = await originalFetch(prepared.body.data.uploadUrl, {
			method: 'PUT',
			headers: prepared.body.data.headers,
			body: new Uint8Array(bytes),
			redirect: 'error',
			signal: AbortSignal.timeout(30_000)
		});
		assert.equal(uploaded.ok, true, 'Configured provider must accept the encrypted-part fixture');
		await uploaded.arrayBuffer();
		const result = complete ? await call('uploads/complete', request, headers) : undefined;
		if (result) assert.equal(result.body.data?.state, 'complete');
		const [manifest] = await db
			.select()
			.from(tables.vaultUpload)
			.where(eq(tables.vaultUpload.id, request.id));
		assert.ok(manifest.objectKey.startsWith(target.prefix));
		return { request, result, objectKey: manifest.objectKey };
	}
	async function independentlyEmpty(prefix: string) {
		const query = { Bucket, Prefix: prefix, MaxKeys: 1 };
		const objects = await client.send(new ListObjectsV2Command(query), options());
		assert.equal(objects.IsTruncated, false);
		assert.equal(objects.Contents?.length ?? 0, 0);
		const uploads = await client.send(
			new ListMultipartUploadsCommand({ Bucket, Prefix: prefix, MaxUploads: 1 }),
			options()
		);
		assert.equal(uploads.IsTruncated, false);
		assert.equal(uploads.Uploads?.length ?? 0, 0);
		if (input.providerId !== 3) {
			const versions = await client.send(new ListObjectVersionsCommand(query), options());
			assert.equal(versions.IsTruncated, false);
			assert.equal(versions.Versions?.length ?? 0, 0);
			assert.equal(versions.DeleteMarkers?.length ?? 0, 0);
		}
	}
	async function drainRetired() {
		const others = await db
			.select({ id: tables.vaultUpload.id })
			.from(tables.vaultUpload)
			.where(and(ne(tables.vaultUpload.userId, userId), ne(tables.vaultUpload.phase, 'deleted')));
		assert.equal(others.length, 0, 'Do not drain another fixture account');
		for (let attempt = 0; attempt < 40; attempt++) {
			await db
				.update(tables.vaultUpload)
				.set({ nextAttemptAt: 0 })
				.where(and(eq(tables.vaultUpload.userId, userId), eq(tables.vaultUpload.retired, 1)));
			await managed.drainManagedUploads(db, new ports.ProviderManagedUploadStorage(), { limit: 8 });
			const pending = await db
				.select({ id: tables.vaultUpload.id })
				.from(tables.vaultUpload)
				.where(
					and(
						eq(tables.vaultUpload.userId, userId),
						ne(tables.vaultUpload.phase, 'deleted'),
						eq(tables.vaultUpload.retired, 1)
					)
				);
			if (!pending.length) return;
			await delay(250);
		}
		assert.fail('Preserve unresolved upload cleanup records');
	}
	try {
		if (realTime) {
			worker = spawn(process.execPath, ['--import', 'tsx', 'scripts/local_cleanup_worker.ts'], {
				env: { ...process.env, FIFE_LOCAL_DATABASE_URL: input.databaseUrl },
				stdio: ['ignore', 'pipe', 'pipe']
			});
			worker.stdout!.on('data', (data) => {
				workerLog += String(data);
			});
			worker.stderr!.on('data', (data) => {
				workerLog += String(data);
			});
			for (let attempt = 0; attempt < 100; attempt++) {
				const [heartbeat] = await db.select().from(tables.recoveryWorkerState);
				if (heartbeat && workerLog.includes('Cleanup cycle completed')) break;
				assert.equal(worker.exitCode, null, 'The actual local cleanup launcher must stay running');
				await delay(100);
			}
			assert.ok(
				workerLog.includes('Cleanup cycle completed'),
				'Observe an actual startup heartbeat'
			);
		} else {
			await db
				.insert(tables.recoveryWorkerState)
				.values({ id: 'cleanup', lastRunAt: Date.now() })
				.onConflictDoUpdate({
					target: tables.recoveryWorkerState.id,
					set: { lastRunAt: Date.now() }
				});
		}
		const bytes = randomBytes(131_073);
		const old = await upload(bytes, oldHeaders, 'old-vault');
		const unfinished = await upload(randomBytes(32_769), oldHeaders, 'unfinished', false);
		const [credentialsBeforeReset] = await db
			.select()
			.from(tables.credential)
			.where(eq(tables.credential[C.ID], credential[C.ID]));
		await db.insert(tables.item).values({
			[I.USER_ID]: userId,
			[I.DEVICE_UUID]: oldHeaders.device_uuid,
			[I.ITEM_ID]: randomUUID(),
			[I.TEXT_CIPHER]: 'old-item-encrypted-text',
			[I.TEXT_NONCE]: 'old-item-nonce',
			[I.KEY_CIPHER]: 'old-item-encrypted-key',
			[I.KEY_NONCE]: 'old-item-key-nonce',
			[I.CLIENT_UPDATED_AT]: Date.now()
		});
		stage = 'reset-confirmation';
		const operationId = randomUUID(),
			challenge = randomBytes(32).toString('base64url');
		const envelope = {
			cipher: randomBytes(48).toString('base64'),
			nonce: randomBytes(24).toString('base64')
		};
		const prepared = await call(
			'recovery-reset/prepare',
			{
				operationId,
				expectedGeneration: 'legacy',
				challengeHash: hash(Buffer.from(challenge), 'sha256', 'hex')
			},
			bootstrap
		);
		assert.equal(prepared.body.data?.phase, 'prepared');
		const confirmation = { operationId, challenge, ...envelope };
		const committed = await call('recovery-reset/confirm', confirmation, bootstrap);
		assert.equal(committed.body.data?.phase, 'cleanup_pending');
		const generation = committed.body.data.generation as string;
		const deadline = committed.body.data.notBefore as number;
		const [committedReset] = await db
			.select()
			.from(tables.recoveryReset)
			.where(eq(tables.recoveryReset.id, operationId));
		const [capability] = await db
			.select()
			.from(tables.vaultUploadCapability)
			.where(eq(tables.vaultUploadCapability.userId, userId));
		assert.equal(
			deadline,
			Math.max(committedReset.committedAt! + 15 * 60_000, capability?.expiresAt ?? 0),
			'A fresh accounted vault waits fifteen minutes or its longest recorded grant'
		);
		const statusPath = `recovery-reset/status?operation_id=${operationId}`;
		assert.equal(
			(await call(statusPath, undefined, bootstrap)).body.data?.operation.phase,
			'cleanup_pending'
		);
		for (const table of [
			tables.file,
			tables.part,
			tables.item,
			tables.tempStorage,
			tables.userDevice
		]) {
			const owner = table === tables.userDevice ? V.USER_ID : F.USER_ID;
			assert.equal(
				(
					await db
						.select()
						.from(table)
						.where(eq((table as any)[owner], userId))
				).length,
				0
			);
		}
		assert.equal(
			(
				await call(
					'devices',
					{ device_uuid: 'fresh-fixture-device', title: 'Fresh device', type: 1, active: 1 },
					bootstrap
				)
			).body.reason,
			'vault_reset_pending'
		);
		assert.equal(
			(await call('uploads/complete', unfinished.request, oldHeaders)).body.reason,
			'device_revoked'
		);
		assert.equal(
			(await call('sync', { table_maps: [] }, oldHeaders)).body.reason,
			'device_revoked'
		);
		const revoked = await call('devices?device_uuid=retired-fixture-device', undefined, oldHeaders);
		assert.equal(revoked.body.success, 1);
		assert.equal(
			revoked.body.data.active,
			0,
			'Older clients receive authoritative own-device removal'
		);
		stage = 'old-vault-cleanup';
		let workerNow: number;
		if (realTime) {
			const started = Date.now();
			let lastMinute = -1;
			while (true) {
				assert.equal(worker!.exitCode, null, 'The local scheduler must remain running');
				const state = (await call(statusPath, undefined, bootstrap)).body.data.operation;
				if (state.phase === 'ready') break;
				assert.equal(state.phase, 'cleanup_pending');
				assert.equal((await call('keys', undefined, bootstrap)).body.reason, 'vault_reset_pending');
				const minute = Math.floor((Date.now() - started) / 60_000);
				if (minute !== lastMinute) {
					lastMinute = minute;
					input.diagnostic(
						`Real-time reset minute ${minute}: cleanup pending; natural worker cycles ${(workerLog.match(/Cleanup cycle completed/g) ?? []).length}`
					);
				}
				assert.ok(
					Date.now() - started < 40 * 60_000,
					'Real-time reset must finish within the bounded provider verification window'
				);
				await delay(5_000);
			}
			assert.ok(
				Date.now() >= deadline,
				'An empty cloud cannot bypass the actual fifteen-minute wait'
			);
			assert.ok(Date.now() - committedReset.committedAt! >= 15 * 60_000);
			assert.ok(
				(workerLog.match(/Cleanup cycle completed/g) ?? []).length >= 4,
				'Observe startup plus at least three natural five-minute cleanup cycles'
			);
			input.diagnostic(
				`Real-time reset ready after ${Math.round((Date.now() - committedReset.committedAt!) / 1_000)} seconds; no clock or persisted deadline was advanced.`
			);
			workerNow = Date.now();
		} else {
			let sweeps = 0;
			const observeCloud = {
				probe: cloud.probe.bind(cloud),
				step: async (...args: Parameters<typeof cloud.step>) => {
					sweeps++;
					return cloud.step(...args);
				}
			};
			await resets.drainRecoveryCleanup(db, observeCloud, { limit: 8 });
			assert.equal(sweeps, 0, 'Unresolved uploads must fence the broad prefix sweep');
			await drainRetired();
			await resets.drainRecoveryCleanup(db, observeCloud, { limit: 8 });
			assert.equal(
				(await call(statusPath, undefined, bootstrap)).body.data.operation.phase,
				'cleanup_pending',
				'An empty provider must not bypass the deadline'
			);
			await independentlyEmpty(target.prefix);
			// Advance only the injected cleanup-worker clock; no deadline or runtime clock is changed.
			workerNow = deadline + 1;
			let failOnce = true;
			const transientCloud = {
				probe: cloud.probe.bind(cloud),
				step: async (...args: Parameters<typeof cloud.step>) => {
					if (failOnce) {
						failOnce = false;
						throw new Error('fixture provider unavailable');
					}
					return cloud.step(...args);
				}
			};
			await resets.drainRecoveryCleanup(db, transientCloud, { now: () => workerNow, limit: 1 });
			assert.equal(
				(await call(statusPath, undefined, bootstrap)).body.data.operation.phase,
				'cleanup_pending',
				'Provider verification failure must block readiness after the deadline'
			);
			workerNow += 60_001;
			for (let pass = 0; pass < 30; pass++) {
				await resets.drainRecoveryCleanup(db, cloud, { now: () => workerNow++, limit: 8 });
				if ((await call(statusPath, undefined, bootstrap)).body.data.operation.phase === 'ready')
					break;
			}
			assert.equal(
				(await call(statusPath, undefined, bootstrap)).body.data.operation.phase,
				'ready'
			);
		}
		await independentlyEmpty(target.prefix);
		stage = 'new-vault-bootstrap';
		const keys = await call('keys', undefined, bootstrap);
		assert.equal(keys.body.success, 1, 'The initiating session remains authenticated');
		assert.equal(keys.body.data.cipher, null);
		assert.equal(keys.body.data.nonce, null);
		assert.equal(
			(await call('keys', { ...envelope, expectedGeneration: generation }, bootstrap)).body.success,
			1
		);
		assert.equal((await call('keys', undefined, bootstrap)).body.data.cipher, envelope.cipher);
		assert.equal(
			(await call('keys', undefined, { ...bootstrap, 'x-fife-session': 'retired-session' })).body
				.reason,
			'vault_replaced'
		);
		assert.equal(
			(
				await call(
					'devices',
					{ device_uuid: 'fresh-fixture-device', title: 'Fresh device', type: 1, active: 1 },
					bootstrap
				)
			).body.success,
			1
		);
		const headers = {
			device_uuid: 'fresh-fixture-device',
			'x-fife-vault-protocol': '1',
			'x-fife-vault-generation': generation
		};
		assert.equal((await call('sync', undefined, headers)).body.success, 1);
		const connected = await call('storages', undefined, headers);
		assert.equal(connected.body.success, 1);
		assert.equal(connected.body.data.filter((row: { added: number }) => row.added === 1).length, 1);
		assert.ok(
			connected.body.data.some(
				(row: { id: number; added: number; used: number }) =>
					row.id === input.providerId && row.added === 1 && row.used === 0
			),
			'The new device sees the retained provider without adding it again'
		);
		const [retained] = await db
			.select()
			.from(tables.storage)
			.where(eq(tables.storage[S.ID], connection[S.ID]));
		assert.equal(retained[S.CREDENTIAL_ID], credential[C.ID]);
		assert.equal(retained[S.USED_BYTES], 0);
		assert.equal(retained[S.PRIORITY], 42);
		assert.ok(
			JSON.stringify(retained[S.JSON]) === JSON.stringify(connection[S.JSON]),
			'Retain connection configuration'
		);
		const [saved] = await db
			.select()
			.from(tables.credential)
			.where(eq(tables.credential[C.ID], credential[C.ID]));
		assert.ok(
			JSON.stringify(saved[C.CREDENTIALS]) ===
				JSON.stringify(credentialsBeforeReset[C.CREDENTIALS]),
			'Retain provider credential JSON'
		);
		stage = 'new-vault-transfer';
		const fresh = await upload(bytes, headers, 'fresh-vault');
		assert.equal(
			fresh.request.file_id,
			old.request.file_id,
			'Exercise logical-part reuse across generations'
		);
		assert.ok(fresh.objectKey.startsWith(`${target.prefix}vaults/${generation}/`));
		assert.notEqual(fresh.objectKey, old.objectKey);
		assert.ok(
			fresh.result?.body.data.part[P.CIPHER] === 'fresh-vault-encrypted-key',
			'Do not reuse retired encryption keys'
		);
		const receipt = await call('uploads/report', old.request);
		assert.equal(receipt.status, 200);
		assert.equal(receipt.body.data.state, 'deleted');
		await managed.drainManagedUploads(db, new ports.ProviderManagedUploadStorage(), {
			now: () => workerNow,
			limit: 8
		});
		const live = await call('uploads/report', fresh.request);
		assert.equal(
			live.body.data.state,
			'committed',
			'Protect the new live object from cleanup receipts'
		);
		const download = await call(
			`${input.providerName}/get-download-url`,
			{ storage_id: connection[S.ID], file_id: fresh.request.file_id },
			headers
		);
		assert.equal(download.body.success, 1);
		assert.equal(typeof download.body.data, 'string', 'Preserve URL-string downloads');
		const restored = await originalFetch(download.body.data, {
			redirect: 'error',
			signal: AbortSignal.timeout(30_000)
		});
		assert.equal(restored.ok, true);
		assert.equal(
			hash(Buffer.from(await restored.arrayBuffer()), 'sha256', 'hex'),
			hash(bytes, 'sha256', 'hex')
		);
		const head = await client.send(
			new HeadObjectCommand({ Bucket, Key: fresh.objectKey }),
			options()
		);
		assert.equal(head.ContentLength, bytes.length);
		assert.equal(
			(await call('recovery-reset/confirm', confirmation, bootstrap)).body.data.phase,
			'ready'
		);
		assert.equal(
			(await call('uploads/complete', old.request, oldHeaders)).body.reason,
			'device_revoked'
		);
		const replayed = await call('uploads/complete', fresh.request, headers);
		assert.equal(
			replayed.body.data?.state,
			'complete',
			'A repeated reset confirmation must preserve the new vault'
		);
		assert.ok(replayed.body.data.part[P.CIPHER] === 'fresh-vault-encrypted-key');
		assert.equal(
			(await db.select().from(tables.userDevice).where(eq(tables.userDevice[V.USER_ID], userId)))
				.length,
			1
		);
		assert.equal(
			(await db.select().from(tables.storage).where(eq(tables.storage[S.USER_ID], userId))).length,
			1
		);
	} catch (error) {
		// Never include credentials, signed URLs, envelopes or raw provider exceptions.
		const detail =
			error instanceof assert.AssertionError ? error.message.split('\n')[0] : 'dependency failure';
		const location =
			error instanceof Error
				? error.stack
						?.match(/provider_reset_lifecycle\.ts:(\d+):(\d+)/)
						?.slice(1)
						.join(':')
				: undefined;
		failure = new Error(
			`Reset lifecycle failed at ${stage}${location ? ` (line ${location})` : ''}: ${detail}`
		);
	} finally {
		if (worker && worker.exitCode === null) {
			worker.kill('SIGTERM');
			await Promise.race([new Promise((resolve) => worker!.once('exit', resolve)), delay(10_000)]);
			if (worker.exitCode === null) worker.kill('SIGKILL');
		}
		globalThis.fetch = originalFetch;
		try {
			await db
				.update(tables.vaultUpload)
				.set({ retired: 1, nextAttemptAt: 0 })
				.where(eq(tables.vaultUpload.userId, userId));
			await drainRetired();
			const [state] = await db
				.select()
				.from(tables.vaultState)
				.where(eq(tables.vaultState.userId, userId));
			const targets = [target];
			if (state) targets.push({ ...target, prefix: `${target.prefix}vaults/${state.generation}/` });
			for (const current of targets) {
				let cursor = {},
					done = false;
				for (let pass = 0; pass < 200 && !done; pass++)
					({ cursor, done } = await cloud.step(current, cursor));
				assert.ok(done, 'Provider teardown must finish');
			}
			await independentlyEmpty(target.prefix);
			await db.delete(tables.user).where(eq(tables.user[U.ID], userId));
			input.diagnostic(
				'Legacy and new-generation objects, versions and multipart uploads are independently verified absent; disposable reset account removed.'
			);
			input.onCleanupVerified();
		} catch {
			failure ??= new Error(
				'Reset lifecycle cloud cleanup remains unverified; preserve disposable SQL'
			);
		} finally {
			client.destroy();
		}
	}
	if (failure) throw failure;
}
