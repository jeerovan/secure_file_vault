import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { createServer as createHttpServer } from 'node:http';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRecoveryDatabase, recoveryTestUrl } from '../support/recoveryDatabase';
import {
	provider,
	recoveryWorkerState,
	user,
	vaultState,
	recoveryReset,
	recoveryCleanupTarget
} from '../../src/lib/server/db/schema';
import { ProviderKeys, UserKeys } from '../../src/lib/server/db/keys';

test(
	'compiled Worker serves the API and executes scheduled cleanup on an isolated database',
	{ skip: !recoveryTestUrl, timeout: 60_000 },
	async () => {
		const database = await createRecoveryDatabase();
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
		const outsideKey = `outside-user/${'B'.repeat(43)}_1`;
		let ownedDeleted = false;
		const cloudActions: string[] = [];
		const cloudMock = createHttpServer(async (request, response) => {
			try {
				const url = new URL(request.url!, 'http://fixture.test');
				assert.match(
					request.headers.authorization ?? '',
					/^AWS4-HMAC-SHA256 Credential=fixture-access\//
				);
				assert.equal(url.pathname, '/fixture-bucket/');
				response.setHeader('content-type', 'application/xml');
				if (url.searchParams.has('versions')) {
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
		await database.db
			.insert(recoveryReset)
			.values({
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
		await database.db
			.insert(recoveryCleanupTarget)
			.values({
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
		const child = spawn(
			process.execPath,
			[
				'node_modules/wrangler/bin/wrangler.js',
				'dev',
				'--local',
				'--config',
				'wrangler.toml',
				'--test-scheduled',
				'--ip',
				'127.0.0.1',
				'--port',
				String(port),
				'--inspector-port',
				'0',
				'--persist-to',
				join(directory, 'state')
			],
			{
				detached: true,
				env: {
					...process.env,
					WRANGLER_SEND_METRICS: 'false',
					CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE: localUrl.toString()
				},
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
			const scheduled = await fetch(
				`${base}/__scheduled?cron=${encodeURIComponent('*/5 * * * *')}`
			);
			assert.equal(scheduled.status, 200);
			for (let tick = 0; tick < 4; tick++) {
				const [operation] = await database.db.select().from(recoveryReset);
				if (operation.phase === 'ready') break;
				assert.equal(
					(await fetch(`${base}/__scheduled?cron=${encodeURIComponent('*/5 * * * *')}`)).status,
					200
				);
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
