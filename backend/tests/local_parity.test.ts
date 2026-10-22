import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { createServer } from 'vite';
import * as tables from '../src/lib/server/db/schema';
import { recoveryHash } from '../src/lib/server/recoverySession';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

async function fixture(body: (f: Awaited<ReturnType<typeof prepare>>) => Promise<void>) {
	const f = await prepare();
	try {
		await body(f);
	} finally {
		await f.close();
	}
}

async function prepare() {
	const database = await createRecoveryDatabase();
	Object.assign(process.env, {
		DATABASE_URL: database.url,
		FIFE_LOCAL_DATABASE_URL: database.url,
		SUPABASE_URL: 'https://auth.example.test',
		SUPABASE_KEY: 'fixture',
		NEON_JWKS: 'https://auth.example.test/.well-known/jwks.json',
		REVENUECAT_SECRET_KEY: 'fixture',
		REVENUECAT_WEBHOOK_SECRET: 'fixture',
		FCM_KEY: 'fixture',
		LOCAL_TEST_AUTH_ENABLED: 'true',
		LOCAL_TEST_AUTH_TOKEN: 'fixture-token',
		LOCAL_TEST_USER_ID: 'fixture-user',
		LOCAL_TEST_EMAIL: 'fixture@example.test',
		RECOVERY_RESET_ENABLED: 'true',
		RECOVERY_WORKER_READY: 'true',
		RECOVERY_RESET_EMAILS: 'fixture@example.test',
		RECOVERY_UPLOAD_ACCOUNTING_SINCE: '1970-01-01T00:00:00.000Z'
	});
	const vite = await createServer({
		root: process.cwd(),
		logLevel: 'silent',
		server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
	});
	const platform = {
		env: {
			HYPERDRIVE: { connectionString: database.url },
			FIFE_AUTH_CACHE: { get: async () => null, put: async () => {} }
		}
	};
	const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
	async function call(
		path: string,
		options: {
			method?: string;
			body?: unknown;
			session?: string;
			device?: string;
			token?: string;
			protocol?: string;
			recoveryProtocol?: string;
		} = {}
	) {
		const method = options.method ?? 'GET';
		const url = new URL(`http://local.test/api/${path}`);
		const request = new Request(url, {
			method,
			headers: {
				authorization: `Bearer ${options.token ?? 'fixture-token'}`,
				service: 'local-test',
				'x-fife-vault-protocol': options.protocol ?? '1',
				'x-fife-recovery-protocol': options.recoveryProtocol ?? '2',
				...(options.session ? { 'x-fife-session': options.session } : {}),
				...(options.device ? { device_uuid: options.device } : {})
			},
			...(options.body === undefined ? {} : { body: JSON.stringify(options.body) })
		});
		const route = await vite.ssrLoadModule(`/src/routes/api/${path.split('?')[0]}/+server.ts`);
		const response: Response = await route[method]({ request, url, platform });
		return { response, body: await response.json() };
	}
	async function signIn() {
		const reply = await call('local-test/session', { method: 'POST', body: {} });
		assert.equal(reply.body.success, 1);
		assert.equal(reply.response.headers.get('cache-control'), 'no-store');
		return reply.body.data.sessionToken as string;
	}
	return {
		database,
		vite,
		call,
		signIn,
		async close() {
			await dbModule.getDb(platform, true).$client.end();
			await vite.close();
			await database.close();
		}
	};
}

test(
	'local sign-in does not create a vault or accept an invalid authentication bypass',
	{ skip: !recoveryTestUrl },
	async () =>
		fixture(async ({ database, call, signIn }) => {
			const first = await signIn();
			assert.notEqual(await signIn(), first);
			assert.deepEqual(await database.db.select().from(tables.user), []);
			assert.equal(
				(await call('local-test/session', { method: 'POST', body: {}, token: 'wrong' })).body
					.success,
				0
			);
			assert.equal((await call('keys')).body.message, 1);
		})
);

test(
	'concurrent fresh account creation keeps only the first envelope',
	{ skip: !recoveryTestUrl },
	async () =>
		fixture(async ({ database, call, signIn }) => {
			const session = await signIn();
			const candidates = [1, 2].map((value) => ({
				cipher: Buffer.alloc(48, value).toString('base64'),
				nonce: Buffer.alloc(24, value).toString('base64')
			}));
			const replies = await Promise.all(
				candidates.map((body) => call('keys', { method: 'POST', session, body }))
			);
			assert.equal(replies.filter((r) => r.body.success === 1).length, 1);
			assert.equal(replies.filter((r) => r.body.success === 0).length, 1);
			const winner = candidates[replies.findIndex((r) => r.body.success === 1)];
			assert.equal((await database.db.select().from(tables.user)).length, 1);
			assert.equal((await database.db.select().from(tables.userData)).length, 1);
			assert.equal((await call('keys', { session })).body.data.cipher, winner.cipher);
			assert.equal((await call('keys', { method: 'POST', session, body: winner })).body.success, 1);
		})
);

test(
	'local recovery executes the production rollout, cleanup, retention and bootstrap policy',
	{ skip: !recoveryTestUrl },
	async () =>
		fixture(async ({ database, vite, call, signIn }) => {
			const session = await signIn();
			const retiredSession = await signIn();
			const cipher = Buffer.alloc(48, 1).toString('base64');
			const nonce = Buffer.alloc(24, 2).toString('base64');
			assert.equal(
				(await call('keys', { method: 'POST', session, body: { cipher, nonce } })).body.success,
				1
			);
			const [account] = await database.db.select().from(tables.user);
			await database.db
				.insert(tables.userDevice)
				.values({ '4': account['1'], '5': 'old-device', '6': 'old device', '9': 1 });
			await database.db
				.insert(tables.provider)
				.values({ '1': 6, '4': 'Fixture S3', '5': 1000, '6': 1 });
			const [credential] = await database.db
				.insert(tables.credential)
				.values({
					'4': account['1'],
					'5': 6,
					'6': {
						bucketName: 'fixture',
						endpoint: 'https://s3.example.test',
						region: 'us-east-1',
						appId: 'fixture',
						appKey: 'fixture'
					}
				})
				.returning();
			await database.db
				.insert(tables.storage)
				.values({ '4': account['1'], '5': credential['1'], '6': 1000, '7': 10, '9': {}, '10': 0 });
			await database.db.insert(tables.item).values({
				'4': account['1'],
				'5': 'old-device',
				'6': 'old-file',
				'7': 'cipher',
				'8': 'nonce',
				'9': 'key',
				'10': 'nonce'
			});
			const credentials = await database.db.select().from(tables.credential);
			const providers = await database.db.select().from(tables.provider);
			const challenge = Buffer.alloc(32, 3).toString('base64url');
			const preparation = {
				operationId: randomUUID(),
				deviceUuid: randomUUID(),
				expectedGeneration: 'legacy',
				challengeHash: await recoveryHash(challenge)
			};
			const prepare = (extra: Record<string, unknown> = {}) =>
				call('recovery-reset/prepare', { method: 'POST', session, body: preparation, ...extra });
			assert.equal((await call('keys', { session })).body.data.recovery_reset_available, false);
			assert.equal((await prepare()).body.message, 'recovery_unavailable');
			assert.deepEqual(await database.db.select().from(tables.recoveryReset), []);
			await database.db
				.insert(tables.recoveryWorkerState)
				.values({ id: 'cleanup', lastRunAt: Date.now() });
			assert.equal((await call('keys', { session })).body.data.recovery_reset_available, true);
			assert.equal((await prepare({ session: undefined })).body.message, 'sign_in_again');
			assert.equal((await prepare({ protocol: '0' })).body.message, 'client_update_required');
			assert.equal(
				(await prepare({ recoveryProtocol: '1' })).body.message,
				'client_update_required'
			);
			assert.equal((await prepare()).body.data.phase, 'prepared');
			const providerModule = await vite.ssrLoadModule('/src/lib/server/recoveryStorage.ts');
			let probes = 0;
			let deletes = 0;
			providerModule.ProviderRecoveryStorage.prototype.probe = async () => {
				probes++;
			};
			providerModule.ProviderRecoveryStorage.prototype.step = async () => {
				deletes++;
				return { cursor: {}, done: true };
			};
			const confirmation = {
				...preparation,
				challenge,
				cipher: Buffer.alloc(48, 4).toString('base64'),
				nonce,
				acknowledged: true
			};
			const recoveryModule = await vite.ssrLoadModule('/src/lib/server/recoverySession.ts');
			providerModule.ProviderRecoveryStorage.prototype.probe = async () => {
				throw new recoveryModule.RecoveryFault('storage_access_required');
			};
			assert.equal(
				(
					await call('recovery-reset/confirm', {
						method: 'POST',
						session,
						body: confirmation
					})
				).body.message,
				'storage_access_required'
			);
			assert.equal((await database.db.select().from(tables.userDevice)).length, 1);
			assert.equal((await database.db.select().from(tables.item)).length, 1);
			providerModule.ProviderRecoveryStorage.prototype.probe = async () => {
				probes++;
			};
			const committed = await call('recovery-reset/confirm', {
				method: 'POST',
				session,
				body: confirmation
			});
			assert.equal(committed.body.success, 1, committed.body.message);
			assert.equal(committed.body.data.phase, 'cleanup_pending');
			const [emptyAccount] = await database.db.select().from(tables.user);
			assert.equal(emptyAccount['6'], null);
			assert.equal(emptyAccount['7'], null);
			const [reset] = await database.db.select().from(tables.recoveryReset);
			assert.equal(committed.body.data.notBefore, reset.committedAt! + 15 * 60_000);
			assert.ok(probes > 0, 'Provider preflight must run for a local account');
			assert.deepEqual(await database.db.select().from(tables.credential), credentials);
			assert.deepEqual(await database.db.select().from(tables.provider), providers);
			assert.deepEqual(await database.db.select().from(tables.item), []);
			assert.deepEqual(await database.db.select().from(tables.userDevice), []);
			assert.equal(
				(await call('sync', { session, device: 'old-device' })).body.reason,
				'device_revoked'
			);
			assert.equal((await call('keys', { session })).body.reason, 'vault_reset_pending');
			const anotherSession = await signIn();
			const pendingStatus = await call('recovery-reset/status', { session: anotherSession });
			assert.equal(pendingStatus.body.data.vault_ready, false);
			assert.equal(pendingStatus.body.data.key_state, 'missing');
			assert.equal(pendingStatus.body.data.operation.operationId, preparation.operationId);
			assert.equal(
				(await call('keys', { session: anotherSession })).body.reason,
				'vault_reset_pending'
			);
			assert.equal(
				(
					await call('devices', {
						method: 'POST',
						session,
						body: { device_uuid: preparation.deviceUuid, title: 'new', type: 3 }
					})
				).body.reason,
				'vault_reset_pending'
			);
			const cleanupModule = await vite.ssrLoadModule('/src/lib/server/recoveryCleanup.ts');
			await cleanupModule.drainRecoveryCleanup(
				database.db,
				new providerModule.ProviderRecoveryStorage(),
				{ now: () => committed.body.data.notBefore + 1 }
			);
			assert.ok(deletes > 0, 'The regular cloud cleanup worker must complete before bootstrap');
			const state = (await database.db.select().from(tables.vaultState))[0];
			assert.equal(state.ready, 1);
			assert.equal((await call('keys', { session: retiredSession })).body.reason, 'vault_replaced');
			assert.equal(
				(await call('recovery-reset/status', { session: retiredSession })).body.message,
				'sign_in_again'
			);
			assert.equal((await call('keys', { session: await signIn() })).body.success, 1);
			assert.equal((await call('keys', { session })).body.data.vault_generation, state.generation);
			const fresh = await call('keys', { session: anotherSession });
			assert.equal(fresh.body.data.key_state, 'missing');
			assert.equal(fresh.body.data.cipher, null);
			assert.equal(
				(
					await call('devices', {
						method: 'POST',
						session: anotherSession,
						body: { device_uuid: 'premature', title: 'not initialized', type: 3 }
					})
				).body.reason,
				'vault_keys_missing'
			);
			assert.equal(
				(await call('keys', { session: anotherSession, recoveryProtocol: '1' })).body.reason,
				'client_update_required'
			);
			assert.equal(
				(
					await call('keys', {
						method: 'POST',
						session,
						body: {
							cipher: Buffer.alloc(48, 9).toString('base64'),
							nonce,
							expectedGeneration: 'legacy'
						}
					})
				).body.reason,
				'key_setup_conflict'
			);
			assert.equal(
				(await call('keys', { session })).body.data.cipher,
				null,
				'A delayed claim must not initialize a newer generation'
			);
			const candidateA = {
				cipher: Buffer.alloc(48, 5).toString('base64'),
				nonce,
				expectedGeneration: state.generation
			};
			const candidateB = {
				cipher: Buffer.alloc(48, 6).toString('base64'),
				nonce,
				expectedGeneration: state.generation
			};
			const replies = await Promise.all([
				call('keys', { method: 'POST', session, body: candidateA }),
				call('keys', { method: 'POST', session: anotherSession, body: candidateB })
			]);
			assert.equal(replies.filter((r) => r.body.success === 1).length, 1);
			assert.equal(replies.filter((r) => r.body.reason === 'key_setup_conflict').length, 1);
			const winner = replies[0].body.success === 1 ? candidateA : candidateB;
			assert.equal((await call('keys', { session })).body.data.cipher, winner.cipher);
			assert.equal(
				(await call('keys', { session: anotherSession })).body.data.cipher,
				winner.cipher
			);
			assert.equal((await call('keys', { method: 'POST', session, body: winner })).body.success, 1);
			assert.equal(
				(await call('recovery-reset/confirm', { method: 'POST', session, body: confirmation })).body
					.success,
				1
			);
			assert.equal(
				(await call('keys', { session })).body.data.cipher,
				winner.cipher,
				'Delayed confirmation cannot replace the winner'
			);
			assert.equal(
				(
					await call('devices', {
						method: 'POST',
						session,
						body: {
							device_uuid: preparation.deviceUuid,
							title: 'new',
							type: 3,
							notificationId: 'stored-notification-token'
						}
					})
				).body.success,
				1
			);
			const current = (await database.db.select().from(tables.userDevice))[0];
			assert.equal(current['8'], 'stored-notification-token');
			assert.equal(
				(await database.db.select().from(tables.user).where(eq(tables.user['1'], account['1'])))[0][
					'6'
				],
				winner.cipher
			);
			assert.deepEqual(await database.db.select().from(tables.credential), credentials);
		})
);
