import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { createServer } from 'vite';
import { eq } from 'drizzle-orm';
import { user, userDevice, vaultState } from '../src/lib/server/db/schema';
import { UserKeys, UserDeviceKeys } from '../src/lib/server/db/keys';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

test(
	'cached identity is separate from live device access',
	{
		skip: !recoveryTestUrl
	},
	async (t) => {
		const database = await createRecoveryDatabase();
		// These replace configuration only inside this test process, including the
		// virtual SvelteKit env module. No request uses real provider credentials.
		Object.assign(process.env, {
			DATABASE_URL: database.url,
			SUPABASE_URL: 'https://auth.example.test',
			SUPABASE_KEY: 'fixture-key',
			NEON_JWKS: 'https://auth.example.test/.well-known/jwks.json',
			REVENUECAT_SECRET_KEY: 'fixture-key',
			REVENUECAT_WEBHOOK_SECRET: 'fixture-webhook',
			FCM_KEY: 'fixture-fcm',
			LOCAL_TEST_AUTH_ENABLED: 'false',
			LOCAL_TEST_AUTH_TOKEN: 'fixture-local',
			LOCAL_TEST_USER_ID: 'fixture-local-user',
			LOCAL_TEST_EMAIL: 'fixture@example.test'
		});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		let closeRouteDatabase: (() => Promise<void>) | undefined;
		try {
			const [account] = await database.db
				.insert(user)
				.values({
					[UserKeys.REMOTE_AUTH_ID]: 'fixture-auth-user',
					[UserKeys.EMAIL]: 'fixture@example.test',
					[UserKeys.CIPHER]: 'fixture-cipher',
					[UserKeys.NONCE]: 'fixture-nonce'
				})
				.returning();
			const deviceId = 'fixture-device';
			await database.db.insert(userDevice).values({
				[UserDeviceKeys.USER_ID]: account[UserKeys.ID],
				[UserDeviceKeys.DEVICE_UUID]: deviceId,
				[UserDeviceKeys.TITLE]: 'Test device',
				[UserDeviceKeys.ACTIVE]: 1
			});
			const cachedIdentity = {
				authorized: true,
				userId: account[UserKeys.ID],
				remoteAuthId: 'fixture-auth-user',
				email: 'fixture@example.test'
			};
			const platform = {
				env: {
					HYPERDRIVE: { connectionString: database.url },
					FIFE_AUTH_CACHE: {
						get: async () => ({ ...cachedIdentity }),
						put: async () => {}
					}
				}
			};
			const route = await vite.ssrLoadModule('/src/routes/api/sync/+server.ts');
			const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
			closeRouteDatabase = () => dbModule.getDb(platform, true).$client.end();
			async function call(
				path: string,
				method: 'GET' | 'POST',
				uuid: string | null = deviceId,
				body: unknown = { table_maps: [] }
			) {
				const url = new URL(`https://app.example.test/api/${path}`);
				const request = new Request(url, {
					method,
					headers: {
						authorization: 'Bearer fixture-token',
						service: 'neon',
						...(uuid === null ? {} : { device_uuid: uuid }),
						'content-type': 'application/json'
					},
					...(method === 'POST' ? { body: JSON.stringify(body) } : {})
				});
				const routePath = path.split('?')[0];
				const handler =
					routePath === 'sync' ? route : await vite.ssrLoadModule(`/src/routes/api/${routePath}/+server.ts`);
				const response = await handler[method]({ request, url, platform });
				return response.json();
			}
			const revoked = { success: 0, message: 8, reason: 'device_revoked' };
			await t.test('an active device still reads and writes sync', async () => {
				assert.equal((await call('sync', 'GET')).success, 1);
				assert.deepEqual(await call('sync', 'POST'), { success: 1 });
			});
			await t.test('missing UUID is an input error, not revocation', async () => {
				assert.deepEqual(await call('sync', 'GET', null), { success: 0, message: 3 });
			});
			await t.test('inactive devices cannot sync or reactivate themselves', async () => {
				await database.db.update(userDevice).set({ [UserDeviceKeys.ACTIVE]: 0 });
				assert.deepEqual(await call('sync', 'GET'), revoked);
				assert.deepEqual(await call('sync', 'POST'), revoked);
				const [device] = await database.db.select().from(userDevice);
				assert.equal(device[UserDeviceKeys.ACTIVE], 0);
			});
			await database.db
				.delete(userDevice)
				.where(eq(userDevice[UserDeviceKeys.USER_ID], account[UserKeys.ID]));
			await t.test('deleted devices cannot sync through cached auth', async () => {
				assert.deepEqual(await call('sync', 'GET'), revoked);
				assert.deepEqual(await call('sync', 'POST'), revoked);
			});
			for (const path of [
				'get-file-parts',
				'get-upload-storage-provider',
				'storages/modify',
				'b2/get-upload-url',
				'b2/get-download-url',
				'b2/find-uploaded-file',
				'b2/add-account',
				...['s3', 'r2', 'oci', 'e2'].flatMap((provider) =>
					['get-upload-url', 'get-download-url', 'add-account'].map(
						(action) => `${provider}/${action}`
					)
				)
			]) {
				await t.test(`${path} denies retired devices before accessing provider data`, async () => {
					assert.deepEqual(await call(path, 'POST'), revoked);
				});
			}
			await t.test(
				'personal storage denies retired devices; onboarding catalog remains public',
				async () => {
					assert.deepEqual(await call('storages', 'GET'), revoked);
					const storageRoute = await vite.ssrLoadModule('/src/routes/api/storages/+server.ts');
					const url = new URL('https://app.example.test/api/storages');
					const response = await storageRoute.GET({ request: new Request(url), url, platform });
					assert.deepEqual(await response.json(), { success: 1, data: [] });
				}
			);
			await t.test('bootstrap key retrieval remains available before registration', async () => {
				assert.equal((await call('keys', 'GET', null)).success, 1);
			});
			await t.test('first registration without a caller UUID remains compatible', async () => {
				assert.equal((await call('devices', 'POST', null, {
					device_uuid: 'onboarding-device', title: 'First registration', type: 1
				})).success, 1);
				await database.db.delete(userDevice)
					.where(eq(userDevice[UserDeviceKeys.DEVICE_UUID], 'onboarding-device'));
			});
			await t.test('legacy first registration may already send its new UUID header', async () => {
				assert.equal((await call('devices', 'POST', 'legacy-onboarding-device', {
					device_uuid: 'legacy-onboarding-device', title: 'Legacy onboarding', type: 1
				})).success, 1);
				await database.db.delete(userDevice)
					.where(eq(userDevice[UserDeviceKeys.DEVICE_UUID], 'legacy-onboarding-device'));
			});
			await t.test('a known legacy caller revoked after bootstrap auth cannot write', async () => {
				const bootstrap = await vite.ssrLoadModule('/src/lib/server/vaultBootstrap.ts');
				const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
				const uuid = 'legacy-race-device';
				await database.db.insert(userDevice).values({
					[UserDeviceKeys.USER_ID]: account[UserKeys.ID],
					[UserDeviceKeys.DEVICE_UUID]: uuid,
					[UserDeviceKeys.TITLE]: 'Legacy race', [UserDeviceKeys.ACTIVE]: 1
				});
				const auth = await bootstrap.authorizeVaultBootstrap(database.db,
					{ ...cachedIdentity, deviceUuid: uuid },
					new Request('https://app.example.test/api/devices', { headers: { device_uuid: uuid } }));
				assert.equal(auth.authorized, true);
				await api.updateDeviceStatus(database.db, account[UserKeys.ID], uuid, 0);
				const result = await bootstrap.withBootstrapWrite(database.db, auth,
					(tx: typeof database.db) => api.addUpdateDevice(tx, account[UserKeys.ID], uuid, 'Legacy race', 1, '', 1));
				assert.deepEqual(await result.json(), revoked);
				await database.db.delete(userDevice)
					.where(eq(userDevice[UserDeviceKeys.DEVICE_UUID], uuid));
			});
			await t.test('another account cannot borrow an active device UUID', async () => {
				const [other] = await database.db
					.insert(user)
					.values({
						[UserKeys.REMOTE_AUTH_ID]: 'other-user',
						[UserKeys.EMAIL]: 'other@example.test',
						[UserKeys.CIPHER]: 'other-cipher',
						[UserKeys.NONCE]: 'other-nonce'
					})
					.returning();
				await database.db.insert(userDevice).values({
					[UserDeviceKeys.USER_ID]: other[UserKeys.ID],
					[UserDeviceKeys.DEVICE_UUID]: 'other-device',
					[UserDeviceKeys.TITLE]: 'Other device',
					[UserDeviceKeys.ACTIVE]: 1
				});
				assert.deepEqual(await call('sync', 'GET', 'other-device'), revoked);
			});
			const generation = randomUUID();
			await database.db.insert(vaultState).values({
				userId: account[UserKeys.ID], generation, ready: 1
			});
			await t.test('old clients receive their own removal signal after a reset', async () => {
				const own = await call(`devices?device_uuid=${deviceId}`, 'GET');
				assert.equal(own.success, 1);
				assert.equal(own.data?.active, 0);
				assert.deepEqual(await call('devices', 'GET'), revoked);
				assert.deepEqual(await call('devices?device_uuid=other-device', 'GET'), revoked);
				assert.equal((await call(`devices?device_uuid=${deviceId}`, 'GET', null)).success, 0);
			});
			await t.test('bootstrap writes recheck membership after initial authorization', async () => {
				const bootstrap = await vite.ssrLoadModule('/src/lib/server/vaultBootstrap.ts');
				const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
				await database.db.insert(userDevice).values({
					[UserDeviceKeys.USER_ID]: account[UserKeys.ID],
					[UserDeviceKeys.DEVICE_UUID]: deviceId,
					[UserDeviceKeys.TITLE]: 'Original device',
					[UserDeviceKeys.ACTIVE]: 1
				});
				const auth = await bootstrap.authorizeVaultBootstrap(database.db, cachedIdentity,
					new Request('https://app.example.test/api/devices', { headers: {
						device_uuid: deviceId, 'x-fife-vault-protocol': '1',
						'x-fife-vault-generation': generation
					} }));
				assert.equal(auth.authorized, true);
				await api.updateDeviceStatus(database.db, account[UserKeys.ID], deviceId, 0);
				const response = await bootstrap.withBootstrapWrite(database.db, auth,
					(tx: typeof database.db) => api.addUpdateDevice(tx, account[UserKeys.ID],
						deviceId, 'Reactivated', 1, '', 1));
				assert.deepEqual(await response.json(), revoked);
				const devices = await database.db.select().from(userDevice)
					.where(eq(userDevice[UserDeviceKeys.USER_ID], account[UserKeys.ID]));
				assert.equal(devices[0][UserDeviceKeys.ACTIVE], 0);
			});
			await t.test('a deleted account is rejected even with a cached identity', async () => {
				await database.db.delete(user).where(eq(user[UserKeys.ID], account[UserKeys.ID]));
				assert.deepEqual(await call('sync', 'GET'), {
					success: 0,
					message: 1,
					reason: 'account_removed'
				});
			});
		} finally {
			await closeRouteDatabase?.();
			await vite.close();
			await database.close();
		}
	}
);
