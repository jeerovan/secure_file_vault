import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';
import {
	user,
	userDevice,
	provider,
	credential,
	storage,
	file,
	part,
	item
} from '../src/lib/server/db/schema';
import { ErrorCode } from '../src/lib/server/db/keys';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

async function withVault(body: (fixture: Awaited<ReturnType<typeof prepare>>) => Promise<void>) {
	const fixture = await prepare();
	try {
		await body(fixture);
	} finally {
		await fixture.close();
	}
}

async function prepare() {
	const database = await createRecoveryDatabase();
	Object.assign(process.env, {
		DATABASE_URL: database.url,
		FIFE_LOCAL_DATABASE_URL: database.url,
		SUPABASE_URL: 'https://auth.example.test',
		SUPABASE_KEY: 'fixture-key',
		NEON_JWKS: 'https://auth.example.test/.well-known/jwks.json',
		REVENUECAT_SECRET_KEY: 'fixture-key',
		REVENUECAT_WEBHOOK_SECRET: 'fixture-webhook',
		FCM_KEY: 'fixture-fcm',
		LOCAL_TEST_AUTH_ENABLED: 'true',
		LOCAL_TEST_AUTH_TOKEN: 'fixture-local',
		LOCAL_TEST_USER_ID: 'fixture-local-user',
		LOCAL_TEST_EMAIL: 'fixture@example.test'
	});
	const vite = await createServer({
		root: process.cwd(),
		logLevel: 'silent',
		server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
	});
	const [account] = await database.db
		.insert(user)
		.values({
			'4': 'fixture-local-user',
			'5': 'fixture@example.test',
			'6': 'original-cipher',
			'7': 'original-nonce'
		})
		.returning();
	for (const id of ['mac', 'samsung', 'iphone']) {
		await database.db.insert(userDevice).values({ '4': account['1'], '5': id, '6': id, '9': 1 });
	}
	await database.db.insert(provider).values({ '1': 2, '4': 'Fixture B2', '5': 1000, '6': 1 });
	const [connection] = await database.db
		.insert(credential)
		.values({
			'4': account['1'],
			'5': 2,
			'6': { fixture: 'preserve credentials' }
		})
		.returning();
	const [bucket] = await database.db
		.insert(storage)
		.values({
			'4': account['1'],
			'5': connection['1'],
			'6': 1000,
			'7': 12,
			'9': {},
			'10': 0
		})
		.returning();
	const [uploaded] = await database.db
		.insert(file)
		.values({
			'4': account['1'],
			'5': 'samsung',
			'6': 'content',
			'7': 1,
			'8': 1,
			'9': 100,
			'10': 2,
			'11': bucket['1'],
			'12': { cloudObject: 'preserve uploaded object reference' }
		})
		.returning();
	await database.db.insert(part).values({
		'4': account['1'],
		'5': 'samsung',
		'6': uploaded['1'],
		'7': 1,
		'8': 12,
		'9': 'part-cipher',
		'10': 'part-nonce',
		'14': 1
	});
	await database.db.insert(item).values({
		'4': account['1'],
		'5': 'samsung',
		'6': 'folder/file',
		'7': 'text-cipher',
		'8': 'text-nonce',
		'9': 'key-cipher',
		'10': 'key-nonce'
	});
	const cached = {
		authorized: true,
		userId: account['1'],
		remoteAuthId: 'fixture-local-user',
		email: 'fixture@example.test'
	};
	const platform = {
		env: {
			HYPERDRIVE: { connectionString: database.url },
			FIFE_AUTH_CACHE: { get: async () => ({ ...cached }), put: async () => {} }
		}
	};
	const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
	async function snapshot() {
		return {
			users: await database.db.select().from(user),
			providers: await database.db.select().from(provider),
			credentials: await database.db.select().from(credential),
			storage: await database.db.select().from(storage),
			files: await database.db.select().from(file),
			parts: await database.db.select().from(part),
			items: await database.db.select().from(item)
		};
	}
	async function call(
		path: string,
		method = 'GET',
		body?: unknown,
		caller = 'mac',
		service = 'local-test',
		extra: Record<string, string> = {}
	) {
		const url = new URL(`https://app.example.test/api/${path}`);
		const request = new Request(url, {
			method,
			headers: {
				authorization: 'Bearer fixture-local',
				service,
				'content-type': 'application/json',
				...(caller ? { device_uuid: caller } : {}),
				...extra
			},
			...(body === undefined ? {} : { body: JSON.stringify(body) })
		});
		const route = await vite.ssrLoadModule(`/src/routes/api/${path.split('?')[0]}/+server.ts`);
		return (await route[method]({ request, url, platform })).json();
	}
	return {
		database,
		snapshot,
		call,
		async close() {
			await dbModule.getDb(platform, true).$client.end();
			await vite.close();
			await database.close();
		}
	};
}

test(
	'legacy local-test reset calls are device-only logout without fixture opt-in',
	{ skip: !recoveryTestUrl },
	async () =>
		withVault(async ({ call, snapshot, database }) => {
			const before = await snapshot();
			assert.deepEqual(await call('local-test/reset', 'POST', {}), { success: 1 });
			assert.deepEqual(
				await snapshot(),
				before,
				'Ordinary logout must retain account keys, file/part metadata and provider credentials'
			);
			const devices = await database.db.select().from(userDevice);
			assert.deepEqual(devices.map((row) => row['5']).sort(), ['iphone', 'samsung']);
		})
);

for (const service of ['local-test', 'neon']) {
	test(
		`${service}: remote logout then final-device sign-out retains the recovery envelope`,
		{ skip: !recoveryTestUrl },
		async () =>
			withVault(async ({ call, snapshot, database }) => {
				const before = await snapshot();
				for (const remote of ['samsung', 'iphone']) {
					assert.equal(
						(await call(`devices?device_uuid=${remote}`, 'DELETE', undefined, 'mac', service))
							.success,
						1
					);
					const status = await call(
						`devices?device_uuid=${remote}`,
						'GET',
						undefined,
						remote,
						service
					);
					assert.equal(status.success, 1);
					assert.equal(status.data.id, remote);
					assert.equal(status.data.active, 0);
				}
				assert.deepEqual(await snapshot(), before);
				assert.deepEqual(await call('signout', 'POST', { device_uuid: 'mac' }, 'mac', service), {
					success: 1
				});
				assert.equal(
					(await database.db.select().from(userDevice)).filter((row) => row['9'] === 1).length,
					0
				);
				assert.deepEqual(await snapshot(), before);
				// The same identity signing in again has no registered device UUID yet.
				const keys = await call('keys', 'GET', undefined, '', service);
				assert.equal(keys.success, 1);
				assert.equal(keys.data.cipher, 'original-cipher');
				assert.equal(keys.data.nonce, 'original-nonce');
				assert.deepEqual(
					await call('keys', 'POST', { cipher: 'replacement', nonce: 'replacement' }, '', service),
					{ success: 0, message: ErrorCode.INVALID_DATA }
				);
				assert.deepEqual(await call('signout', 'POST', { device_uuid: 'mac' }, 'mac', service), {
					success: 1
				});
				assert.deepEqual(await snapshot(), before);
			})
	);
}

test(
	'invalid fixture reset flags cannot erase a vault; explicit isolated cleanup remains available',
	{ skip: !recoveryTestUrl },
	async () =>
		withVault(async ({ call, snapshot, database }) => {
			const before = await snapshot();
			for (const value of ['', 'true', '0']) {
				assert.equal(
					(
						await call('local-test/reset', 'POST', {}, 'mac', 'local-test', {
							'x-fife-fixture-reset': value
						})
					).success,
					1
				);
				assert.deepEqual(await snapshot(), before);
			}
			assert.equal(
				(
					await call('local-test/reset', 'POST', {}, 'samsung', 'neon', {
						'x-fife-fixture-reset': '1'
					})
				).success,
				0
			);
			assert.deepEqual(await snapshot(), before);
			assert.deepEqual(
				await call('local-test/reset', 'POST', {}, 'samsung', 'local-test', {
					'x-fife-fixture-reset': '1'
				}),
				{ success: 1 }
			);
			assert.deepEqual(await database.db.select().from(user), []);
			assert.deepEqual(await database.db.select().from(credential), []);
		})
);

test(
	'legacy local sign-out before device registration leaves the account and devices intact',
	{ skip: !recoveryTestUrl },
	async () =>
		withVault(async ({ call, snapshot, database }) => {
			const before = await snapshot();
			const devices = await database.db.select().from(userDevice);
			assert.deepEqual(await call('local-test/reset', 'POST', {}, ''), { success: 1 });
			assert.deepEqual(await snapshot(), before);
			assert.deepEqual(await database.db.select().from(userDevice), devices);
		})
);
