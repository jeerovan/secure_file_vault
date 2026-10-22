import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';
import { recoveryWorkerState, user } from '../src/lib/server/db/schema';
import { UserKeys } from '../src/lib/server/db/keys';

test(
	'manual cleanup command attaches without resetting the local vault',
	{ skip: !recoveryTestUrl, timeout: 30_000 },
	async () => {
		const scripts = JSON.parse(await readFile('package.json', 'utf8')).scripts;
		assert.equal(
			typeof scripts['cleanup:local'],
			'string',
			'A manual local cleanup command must be available'
		);
		const database = await createRecoveryDatabase();
		const directory = await mkdtemp(join(tmpdir(), 'fife-local-cleanup-'));
		try {
			await database.db.insert(user).values({
				[UserKeys.REMOTE_AUTH_ID]: 'preserved-vault',
				[UserKeys.EMAIL]: 'fixture@example.test',
				[UserKeys.CIPHER]: 'original-cipher',
				[UserKeys.NONCE]: 'original-nonce'
			});
			const original = await database.db.select().from(user);
			const controlFile = join(directory, 'server.json');
			await writeFile(
				controlFile,
				JSON.stringify({
					databaseUrl: database.url,
					processId: process.pid,
					port: 5173,
					remoteId: `fife-provider-local-${randomUUID()}`
				}),
				{ mode: 0o600 }
			);
			const child = spawn(
				process.execPath,
				[
					'--import',
					'tsx',
					'scripts/local_cleanup_worker.ts',
					'--control-file',
					controlFile,
					'--once'
				],
				{
					cwd: process.cwd(),
					env: {
						...process.env,
						FIFE_LOCAL_DATABASE_URL: '',
						DATABASE_URL: 'postgres://secret:never-use@production.invalid/prod'
					},
					stdio: ['ignore', 'pipe', 'pipe']
				}
			);
			let logs = '';
			child.stdout.on('data', (chunk) => {
				logs += chunk;
			});
			child.stderr.on('data', (chunk) => {
				logs += chunk;
			});
			const code = await new Promise((resolve, reject) => {
				child.once('exit', resolve);
				child.once('error', reject);
			});
			assert.equal(code, 0, logs);
			assert.match(logs, /Cleanup cycle completed/);
			assert.ok(!logs.includes(database.url));
			assert.ok(!logs.includes('secret'));
			const [heartbeat] = await database.db.select().from(recoveryWorkerState);
			assert.equal(heartbeat.id, 'cleanup');
			assert.ok(Date.now() - heartbeat.lastRunAt < 10_000);
			assert.deepEqual(await database.db.select().from(user), original);
			const continuous = spawn(
				process.execPath,
				['--import', 'tsx', 'scripts/local_cleanup_worker.ts', '--control-file', controlFile],
				{ env: { ...process.env, FIFE_LOCAL_DATABASE_URL: '' }, stdio: ['ignore', 'pipe', 'pipe'] }
			);
			const finished = new Promise((resolve, reject) => {
				continuous.once('exit', resolve);
				continuous.once('error', reject);
			});
			try {
				let ready = false;
				for (let attempt = 0; attempt < 100; attempt++) {
					const [current] = await database.db.select().from(recoveryWorkerState);
					if (current.lastRunAt > heartbeat.lastRunAt) {
						ready = true;
						break;
					}
					if (continuous.exitCode !== null) break;
					await new Promise((resolve) => setTimeout(resolve, 50));
				}
				assert.equal(
					ready,
					true,
					'The continuous executable must run an initial real cleanup cycle'
				);
				continuous.kill('SIGTERM');
				assert.equal(await finished, 0, 'SIGTERM must close the worker gracefully');
				assert.deepEqual(await database.db.select().from(user), original);
			} finally {
				if (continuous.exitCode === null) {
					continuous.kill('SIGKILL');
					await finished;
				}
			}
		} finally {
			await rm(directory, { recursive: true, force: true });
			await database.close();
		}
	}
);

test('local cleanup accepts only explicitly selected loopback databases', async () => {
	const { validateLocalDatabaseUrl } = await import('../scripts/localCleanup');
	for (const value of [
		'postgres://user:secret@production.example/fife',
		'postgres://user@127.0.0.1.evil.test/fife',
		'postgres://user@192.168.1.2/fife',
		'postgres://user@localhost/fife?host=production.example',
		'postgres://user@localhost/fife#ignored',
		'postgres://user@localhost/postgres',
		'postgres://user@localhost/template1',
		'postgres://user@localhost/',
		'not-a-url',
		'https://localhost/fife'
	])
		assert.throws(() => validateLocalDatabaseUrl(value), /local PostgreSQL database/);
	assert.equal(
		validateLocalDatabaseUrl('postgres://user@localhost:5432/fife'),
		'postgres://user@localhost:5432/fife'
	);
});

test('attached cleanup rejects a replaced or stopped local server', async () => {
	const { resolveLocalCleanupTarget } = await import('../scripts/localCleanup');
	const directory = await mkdtemp(join(tmpdir(), 'fife-cleanup-control-'));
	try {
		const controlFile = join(directory, 'server.json');
		const original = {
			databaseUrl: `postgres://fixture@127.0.0.1:59999/fife_recovery_${'a'.repeat(32)}`,
			processId: process.pid,
			port: 5173,
			remoteId: `fife-provider-local-${randomUUID()}`
		};
		await writeFile(controlFile, JSON.stringify(original));
		const target = await resolveLocalCleanupTarget({ controlFile });
		await target.verify();
		await writeFile(
			controlFile,
			JSON.stringify({ ...original, remoteId: `fife-provider-local-${randomUUID()}` })
		);
		await assert.rejects(target.verify(), /local server/);
		await writeFile(controlFile, JSON.stringify({ ...original, processId: 2147483647 }));
		await assert.rejects(resolveLocalCleanupTarget({ controlFile }), /local server/);
		await writeFile(
			controlFile,
			JSON.stringify({ ...original, databaseUrl: 'postgres://fixture@localhost:5432/fife' })
		);
		await assert.rejects(resolveLocalCleanupTarget({ controlFile }), /disposable/);
	} finally {
		await rm(directory, { recursive: true, force: true });
	}
});

test('cleanup scheduler runs immediately, never overlaps, retries failures and drains on stop', async (t) => {
	const { startLocalCleanupSchedule, CLEANUP_INTERVAL_MS } =
		await import('../scripts/localCleanup');
	assert.equal(CLEANUP_INTERVAL_MS, 5 * 60_000);
	t.mock.timers.enable({ apis: ['setInterval'] });
	let calls = 0,
		failures = 0,
		successes = 0;
	let release!: () => void;
	const schedule = startLocalCleanupSchedule(
		async () => {
			calls++;
			if (calls === 1) {
				await new Promise<void>((resolve) => {
					release = resolve;
				});
				throw new Error('private provider error');
			}
			if (calls === 3)
				await new Promise<void>((resolve) => {
					release = resolve;
				});
		},
		{
			onFailure: () => {
				failures++;
			},
			onSuccess: () => {
				successes++;
			}
		}
	);
	assert.equal(calls, 1);
	t.mock.timers.tick(CLEANUP_INTERVAL_MS * 2);
	assert.equal(calls, 1, 'A slow cleanup must not overlap another cycle');
	release();
	await schedule.firstRun;
	assert.equal(failures, 1);
	t.mock.timers.tick(CLEANUP_INTERVAL_MS);
	await Promise.resolve();
	await Promise.resolve();
	assert.equal(calls, 2);
	assert.equal(successes, 1);
	t.mock.timers.tick(CLEANUP_INTERVAL_MS);
	assert.equal(calls, 3);
	let stopped = false;
	const stopping = schedule.stop().then(() => {
		stopped = true;
	});
	await Promise.resolve();
	assert.equal(stopped, false, 'Stop must wait for in-flight cleanup');
	release();
	await stopping;
	t.mock.timers.tick(CLEANUP_INTERVAL_MS * 5);
	assert.equal(calls, 3);
	assert.equal(successes, 2);
});

test(
	'failed cleanup does not refresh heartbeat and recovery becomes available only after a successful tick',
	{ skip: !recoveryTestUrl },
	async () => {
		const { runCleanupTick } = await import('../src/lib/server/cleanupWorker');
		const { recoveryAvailable } = await import('../src/lib/server/recoveryAvailability');
		const database = await createRecoveryDatabase();
		try {
			const flags = {
				RECOVERY_RESET_ENABLED: 'true',
				RECOVERY_WORKER_READY: 'true',
				RECOVERY_RESET_EMAILS: 'fixture@example.test'
			};
			assert.equal(await recoveryAvailable(database.db, flags, 'fixture@example.test'), false);
			await database.db.$client.unsafe(
				'ALTER TABLE vault_upload RENAME TO unavailable_vault_upload'
			);
			await assert.rejects(runCleanupTick(database.db), {
				message: 'Recovery cleanup tick failed'
			});
			assert.deepEqual(await database.db.select().from(recoveryWorkerState), []);
			await database.db.$client.unsafe(
				'ALTER TABLE unavailable_vault_upload RENAME TO vault_upload'
			);
			await runCleanupTick(database.db);
			assert.equal(await recoveryAvailable(database.db, flags, 'fixture@example.test'), true);
			assert.equal(await recoveryAvailable(database.db, flags, 'other@example.test'), false);
		} finally {
			await database.close();
		}
	}
);
