import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createServer } from 'node:net';
import { createServer as createHttpServer } from 'node:http';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import { createRecoveryDatabase, recoveryTestUrl } from '../support/recoveryDatabase';
import {
	provider,
	recoveryWorkerState,
	user,
	vaultState,
	recoveryReset,
	recoveryCleanupTarget,
	vaultUpload,
	credential,
	storage,
	userDevice,
	file,
	part
} from '../../src/lib/server/db/schema';
import {
	ProviderKeys,
	UserKeys,
	CredentialKeys,
	StorageKeys,
	UserDeviceKeys,
	FileKeys,
	PartKeys
} from '../../src/lib/server/db/keys';

test(
	'compiled fallback Worker reads managed files, guards deferred keys and continues scheduled cleanup',
	{ skip: !recoveryTestUrl, timeout: 60_000 },
	async () => {
		const database = await createRecoveryDatabase();
		const workerConfig = process.env.FIFE_RECOVERY_WORKER_TEST_CONFIG ?? 'wrangler.toml';
		const directory = await mkdtemp(join(tmpdir(), 'fife-recovery-worker-'));
		const portServer = createServer();
		await new Promise<void>((resolve) => portServer.listen(0, '127.0.0.1', resolve));
		const port = (portServer.address() as { port: number }).port;
		await new Promise<void>((resolve) => portServer.close(() => resolve()));
		const localUrl = new URL(database.url);
		localUrl.password = 'fixture-only';
		const sentinel = `fixture-${crypto.randomUUID()}`;
		const prefix = 'fixture-user/';
		const ownedKey = `${prefix}${'A'.repeat(43)}_1`;
		const managedKey = `${prefix}${'C'.repeat(43)}_1`;
		const outsideKey = `outside-user/${'B'.repeat(43)}_1`;
		const readerRemoteId = `reader-${crypto.randomUUID()}`;
		const logicalPart = `${'D'.repeat(43)}_1`;
		const downloadedKey = `${readerRemoteId}/${logicalPart}~${crypto.randomUUID()}`;
		const downloadedBytes = Buffer.from(
			'managed bytes remain available while initiation is paused'
		);
		let ownedDeleted = false;
		const cloudActions: string[] = [];
		const cloudMock = createHttpServer(async (request, response) => {
			try {
				const url = new URL(request.url!, 'http://fixture.test');
				if (request.method === 'GET' && url.pathname === `/fixture-bucket/${downloadedKey}`) {
					assert.match(url.searchParams.get('X-Amz-Credential') ?? '', /^fixture-access\//);
					response.end(downloadedBytes);
					return;
				}
				assert.match(
					request.headers.authorization ?? '',
					/^AWS4-HMAC-SHA256 Credential=fixture-access\//
				);
				response.setHeader('content-type', 'application/xml');
				if (url.pathname === `/fixture-bucket/${managedKey}`) {
					if (
						request.method === 'DELETE' &&
						url.searchParams.get('uploadId') === 'fixture-upload'
					) {
						cloudActions.push('managed-abort');
						response.statusCode = 204;
						response.end();
						return;
					}
					response.statusCode = 404;
					if (request.method === 'HEAD') response.end();
					else {
						cloudActions.push('managed-terminal');
						response.end('<Error><Code>NoSuchUpload</Code></Error>');
					}
					return;
				}
				assert.equal(url.pathname, '/fixture-bucket/');
				if (url.searchParams.has('versions')) {
					if (url.searchParams.get('prefix') === managedKey) {
						cloudActions.push('managed-versions');
						response.end(
							'<ListVersionsResult><IsTruncated>false</IsTruncated></ListVersionsResult>'
						);
						return;
					}
					cloudActions.push('versions');
					assert.equal(url.searchParams.get('prefix'), prefix);
					response.end(
						`<ListVersionsResult><IsTruncated>false</IsTruncated>${ownedDeleted ? '' : `<Version><Key>${ownedKey}</Key><VersionId>owned-version</VersionId></Version>`}<Version><Key>${outsideKey}</Key><VersionId>outside-version</VersionId></Version></ListVersionsResult>`
					);
					return;
				}
				if (url.searchParams.has('uploads')) {
					cloudActions.push('uploads');
					assert.equal(url.searchParams.get('prefix'), prefix);
					response.end(
						'<ListMultipartUploadsResult><IsTruncated>false</IsTruncated></ListMultipartUploadsResult>'
					);
					return;
				}
				assert.equal(request.method, 'POST');
				assert.ok(url.searchParams.has('delete'));
				const chunks: Buffer[] = [];
				for await (const chunk of request) chunks.push(Buffer.from(chunk));
				const body = Buffer.concat(chunks).toString();
				assert.ok(body.includes(`<Key>${ownedKey}</Key>`));
				assert.ok(body.includes('<VersionId>owned-version</VersionId>'));
				assert.equal(body.includes(outsideKey), false);
				ownedDeleted = true;
				cloudActions.push('delete');
				response.end('<DeleteResult/>');
			} catch {
				response.statusCode = 500;
				response.end('<Error><Code>FixtureFailure</Code></Error>');
			}
		});
		await new Promise<void>((resolve) => cloudMock.listen(0, '127.0.0.1', resolve));
		const cloudPort = (cloudMock.address() as { port: number }).port;
		const [account] = await database.db
			.insert(user)
			.values({
				[UserKeys.REMOTE_AUTH_ID]: sentinel,
				[UserKeys.EMAIL]: `${sentinel}@example.test`,
				[UserKeys.CIPHER]: 'fixture-cipher',
				[UserKeys.NONCE]: 'fixture-nonce'
			})
			.returning();
		await database.db
			.insert(vaultState)
			.values({ userId: account[UserKeys.ID], generation: 'next-generation', ready: 0 });
		const operationId = crypto.randomUUID(),
			now = Date.now();
		await database.db.insert(vaultUpload).values({
			id: crypto.randomUUID(),
			userId: account[UserKeys.ID],
			deviceUuid: 'retired-device',
			generation: 'legacy',
			storageId: 1,
			providerId: 6,
			objectKey: managedKey,
			partName: `${'C'.repeat(43)}_1`,
			contentLength: 17,
			sha1: 'a'.repeat(40),
			md5: 'AAAAAAAAAAAAAAAAAAAAAA==',
			receiptHash: 'fixture-receipt',
			uploadId: 'fixture-upload',
			phase: 'cleanup',
			retired: 1,
			operationId,
			createdAt: now - 60_000,
			updatedAt: now - 60_000,
			credentials: {
				appId: 'fixture-access',
				appKey: 'fixture-secret',
				bucketName: 'fixture-bucket',
				region: 'fixture-region',
				endpoint: `http://127.0.0.1:${cloudPort}`,
				forcePathStyle: true
			}
		});
		await database.db.insert(recoveryReset).values({
			id: operationId,
			userId: account[UserKeys.ID],
			expectedGeneration: 'legacy',
			nextGeneration: 'next-generation',
			sessionHash: 'fixture-session',
			challengeHash: 'fixture-challenge',
			createdAt: now - 60_000,
			expiresAt: now + 60_000,
			committedAt: now - 30_000,
			notBefore: now - 1,
			phase: 'cleanup_pending'
		});
		await database.db.insert(recoveryCleanupTarget).values({
			id: crypto.randomUUID(),
			operationId,
			providerId: 6,
			prefix,
			credentials: {
				appId: 'fixture-access',
				appKey: 'fixture-secret',
				bucketName: 'fixture-bucket',
				region: 'fixture-region',
				endpoint: `http://127.0.0.1:${cloudPort}`,
				forcePathStyle: true
			}
		});
		await database.db.insert(provider).values({
			[ProviderKeys.ID]: 937000001,
			[ProviderKeys.TITLE]: sentinel,
			[ProviderKeys.FREE_BYTES]: 1024,
			[ProviderKeys.PRIORITY]: 0
		});
		// No real credentials or authentication bypass is added to the Worker.
		// Only its isolated local KV contains these pre-verified fixture identities.
		await database.db.insert(provider).values({
			[ProviderKeys.ID]: 6,
			[ProviderKeys.TITLE]: 'Fixture S3',
			[ProviderKeys.FREE_BYTES]: 1024,
			[ProviderKeys.PRIORITY]: 0
		});
		const [reader] = await database.db
			.insert(user)
			.values({
				[UserKeys.REMOTE_AUTH_ID]: readerRemoteId,
				[UserKeys.EMAIL]: `${readerRemoteId}@example.test`,
				[UserKeys.CIPHER]: 'existing-cipher',
				[UserKeys.NONCE]: 'existing-nonce'
			})
			.returning();
		const [deferred] = await database.db
			.insert(user)
			.values({
				[UserKeys.REMOTE_AUTH_ID]: `deferred-${sentinel}`,
				[UserKeys.EMAIL]: `deferred-${sentinel}@example.test`,
				[UserKeys.CIPHER]: null,
				[UserKeys.NONCE]: null
			})
			.returning();
		await database.db.insert(vaultState).values({
			userId: deferred[UserKeys.ID],
			generation: 'awaiting-new-keys',
			ready: 1
		});
		await database.db.insert(userDevice).values({
			[UserDeviceKeys.USER_ID]: reader[UserKeys.ID],
			[UserDeviceKeys.DEVICE_UUID]: 'released-client',
			[UserDeviceKeys.TITLE]: 'Released client fixture',
			[UserDeviceKeys.ACTIVE]: 1
		});
		const [readerCredential] = await database.db
			.insert(credential)
			.values({
				[CredentialKeys.USER_ID]: reader[UserKeys.ID],
				[CredentialKeys.PROVIDER_ID]: 6,
				[CredentialKeys.CREDENTIALS]: {
					appId: 'fixture-access',
					appKey: 'fixture-secret',
					bucketName: 'fixture-bucket',
					region: 'fixture-region',
					endpoint: `http://127.0.0.1:${cloudPort}`,
					forcePathStyle: true
				}
			})
			.returning();
		const [readerStorage] = await database.db
			.insert(storage)
			.values({
				[StorageKeys.USER_ID]: reader[UserKeys.ID],
				[StorageKeys.CREDENTIAL_ID]: readerCredential[CredentialKeys.ID],
				[StorageKeys.LIMIT_BYTES]: 1024,
				[StorageKeys.LIMIT_FREE_BYTES]: 1024,
				[StorageKeys.JSON]: {}
			})
			.returning();
		const [readerFile] = await database.db
			.insert(file)
			.values({
				[FileKeys.USER_ID]: reader[UserKeys.ID],
				[FileKeys.DEVICE_UUID]: 'released-client',
				[FileKeys.FILE_HASH]: 'D'.repeat(43),
				[FileKeys.STORAGE_ID]: readerStorage[StorageKeys.ID],
				[FileKeys.PROVIDER_ID]: 6
			})
			.returning();
		await database.db.insert(part).values({
			[PartKeys.USER_ID]: reader[UserKeys.ID],
			[PartKeys.DEVICE_UUID]: 'released-client',
			[PartKeys.FILE_ID]: readerFile[FileKeys.ID],
			[PartKeys.PART_NUMBER]: 1,
			[PartKeys.UPLOADED]: 1,
			[PartKeys.JSON]: { managedObjectKey: downloadedKey }
		});
		const envFile = join(directory, 'worker.env');
		await writeFile(
			envFile,
			[
				'MANAGED_UPLOADS_ENABLED=false',
				'RECOVERY_RESET_ENABLED=false',
				'RECOVERY_WORKER_READY=false',
				'RECOVERY_RESET_EMAILS='
			].join('\n'),
			{ mode: 0o600 }
		);
		const childEnv = {
			...process.env,
			WRANGLER_SEND_METRICS: 'false',
			CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE: localUrl.toString()
		};
		const tokens = { reader: crypto.randomUUID(), deferred: crypto.randomUUID() };
		for (const [name, identity] of [
			['reader', reader],
			['deferred', deferred]
		] as const) {
			const path = join(directory, `${name}-auth.json`);
			await writeFile(
				path,
				JSON.stringify({
					authorized: true,
					userId: identity[UserKeys.ID],
					remoteAuthId: identity[UserKeys.REMOTE_AUTH_ID],
					email: identity[UserKeys.EMAIL]
				}),
				{ mode: 0o600 }
			);
			const seeded = spawnSync(
				process.execPath,
				[
					'node_modules/wrangler/bin/wrangler.js',
					'kv',
					'key',
					'put',
					`auth:${createHash('sha256').update(tokens[name]).digest('hex')}`,
					'--path',
					path,
					'--binding',
					'FIFE_AUTH_CACHE',
					'--local',
					'--config',
					workerConfig,
					'--env-file',
					envFile,
					'--persist-to',
					join(directory, 'state')
				],
				{ env: childEnv, encoding: 'utf8' }
			);
			assert.equal(seeded.status, 0, 'Seed only the isolated local authentication cache');
		}
		const child = spawn(
			process.execPath,
			[
				'--import',
				'tsx',
				'tests/support/compiledWorkerRunner.ts',
				workerConfig,
				envFile,
				join(directory, 'state'),
				String(port),
				join(directory, 'worker-control.json')
			],
			{
				detached: true,
				env: childEnv,
				stdio: ['ignore', 'pipe', 'pipe']
			}
		);
		let logs = '';
		child.stdout.on('data', (data) => {
			logs += String(data);
		});
		child.stderr.on('data', (data) => {
			logs += String(data);
		});
		const base = `http://127.0.0.1:${port}`;
		try {
			let ready = false;
			for (let i = 0; i < 300; i++) {
				if (child.exitCode !== null) break;
				if (logs.includes('Ready on')) {
					ready = true;
					break;
				}
				await new Promise((resolve) => setTimeout(resolve, 100));
			}
			assert.equal(ready, true, 'The local compiled Worker must start');
			const response = await fetch(`${base}/api/storages`);
			const catalog = await response.json();
			// Verify the exact fixture database mapping before invoking any Cron work.
			assert.ok(
				catalog.data?.some(
					(entry: { id: number; title: string }) =>
						entry.id === 937000001 && entry.title === sentinel
				),
				'Worker must use its isolated fixture database'
			);
			const disabled = await fetch(`${base}/api/uploads/protocol`, { method: 'POST' });
			assert.equal(disabled.status, 404);
			assert.equal(disabled.headers.get('cache-control'), 'no-store');
			const downloaded = await fetch(`${base}/api/s3/get-download-url`, {
				method: 'POST',
				headers: {
					authorization: `Bearer ${tokens.reader}`,
					device_uuid: 'released-client',
					'content-type': 'application/json'
				},
				body: JSON.stringify({ file_id: logicalPart, storage_id: readerStorage[StorageKeys.ID] })
			});
			const descriptor = (await downloaded.json()) as { success: number; data: string };
			assert.equal(descriptor.success, 1);
			assert.equal(typeof descriptor.data, 'string', 'Keep the released download URL contract');
			assert.equal(new URL(descriptor.data).pathname, `/fixture-bucket/${downloadedKey}`);
			assert.deepEqual(
				Buffer.from(await (await fetch(descriptor.data)).arrayBuffer()),
				downloadedBytes
			);
			for (const method of ['GET', 'POST']) {
				const response = await fetch(`${base}/api/keys`, {
					method,
					headers: {
						authorization: `Bearer ${tokens.deferred}`,
						'content-type': 'application/json'
					},
					...(method === 'POST'
						? { body: JSON.stringify({ cipher: 'obsolete-client', nonce: 'obsolete-nonce' }) }
						: {})
				});
				assert.deepEqual(await response.json(), {
					success: 0,
					message: 18,
					reason: 'client_update_required'
				});
			}
			const [stillDeferred] = await database.db
				.select()
				.from(user)
				.where(eq(user[UserKeys.ID], deferred[UserKeys.ID]));
			assert.equal(stillDeferred[UserKeys.CIPHER], null);
			assert.equal(stillDeferred[UserKeys.NONCE], null);
			const control = JSON.parse(await readFile(join(directory, 'worker-control.json'), 'utf8'));
			assert.equal(new URL(control.innerUrl).hostname, '127.0.0.1');
			assert.equal(new URL(control.innerUrl).protocol, 'http:');
			// Skip Wrangler's outer fetch proxy and Miniflare's assets proxy.
			// Dispatch a native event directly to the actual Worker, without
			// rebundling or adding test middleware to the frozen package.
			const triggerScheduled = () =>
				fetch(
					`${control.innerUrl}/cdn-cgi/handler/scheduled?cron=${encodeURIComponent('*/5 * * * *')}`,
					{
						headers: { ...control.headers, 'MF-Route-Override': control.workerName }
					}
				);
			const scheduled = await triggerScheduled();
			assert.equal(scheduled.status, 200, await scheduled.text());
			const [checkpoint] = await database.db.select().from(vaultUpload);
			assert.equal(checkpoint.phase, 'cleanup');
			assert.equal(
				checkpoint.cleanupCursor.settled,
				true,
				'Cron must commit terminal-upload proof before deleting objects'
			);
			assert.equal(ownedDeleted, false, 'Reset prefix sweep must wait for the managed upload');
			for (let tick = 0; tick < 4; tick++) {
				await database.db
					.update(vaultUpload)
					.set({ nextAttemptAt: 0 })
					.where(eq(vaultUpload.id, checkpoint.id));
				const [operation] = await database.db.select().from(recoveryReset);
				if (operation.phase === 'ready') break;
				assert.equal((await triggerScheduled()).status, 200);
			}
			const [operation] = await database.db.select().from(recoveryReset);
			assert.equal(
				operation.phase,
				'ready',
				'The deployed bundling path must parse provider XML and complete deletion'
			);
			assert.equal(ownedDeleted, true);
			assert.ok(cloudActions.includes('delete'));
			assert.ok(cloudActions.includes('uploads'));
			assert.ok(cloudActions.includes('managed-abort'));
			assert.ok(cloudActions.includes('managed-terminal'));
			assert.ok(cloudActions.includes('managed-versions'));
			const [deletedUpload] = await database.db.select().from(vaultUpload);
			assert.equal(deletedUpload.phase, 'deleted');
			assert.equal(deletedUpload.contentLength, 0);
			assert.deepEqual(deletedUpload.credentials, {});
			const [worker] = await database.db.select().from(recoveryWorkerState);
			assert.equal(worker.id, 'cleanup');
			assert.ok(Date.now() - worker.lastRunAt < 30_000);
		} catch (error) {
			await writeFile('/tmp/fife_recovery_worker_smoke.log', logs, { mode: 0o600 });
			throw error;
		} finally {
			if (child.pid) {
				try {
					process.kill(-child.pid, 'SIGTERM');
				} catch {
					/* already exited */
				}
				if (child.exitCode === null) await new Promise((resolve) => child.once('exit', resolve));
			}
			await database.close();
			cloudMock.closeAllConnections();
			await new Promise<void>((resolve) => cloudMock.close(() => resolve()));
			await rm(directory, { recursive: true, force: true });
		}
	}
);
