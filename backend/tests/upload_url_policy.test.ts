import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';
import { eq } from 'drizzle-orm';
import * as tables from '../src/lib/server/db/schema';
import {
	UserKeys as U,
	UserDeviceKeys as V,
	ProviderKeys as P,
	CredentialKeys as C,
	StorageKeys as S,
	StorageProvider,
	ErrorCode
} from '../src/lib/server/db/keys';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

test(
	'presigned upload routes preserve their contract with a 15-minute lifetime',
	{ skip: !recoveryTestUrl },
	async (t) => {
		const database = await createRecoveryDatabase();
		Object.assign(process.env, {
			DATABASE_URL: database.url,
			FIFE_LOCAL_DATABASE_URL: database.url,
			SUPABASE_URL: 'https://auth.example.test',
			SUPABASE_KEY: 'fixture',
			NEON_JWKS: 'https://auth.example.test/jwks',
			REVENUECAT_SECRET_KEY: 'fixture',
			REVENUECAT_WEBHOOK_SECRET: 'fixture',
			FCM_KEY: 'fixture',
			LOCAL_TEST_AUTH_ENABLED: 'false'
		});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		let closeRoutes: (() => Promise<void>) | undefined;
		try {
			const accounts = await database.db
				.insert(tables.user)
				.values(
					['first', 'second'].map((name) => ({
						[U.REMOTE_AUTH_ID]: `upload-policy-${name}`,
						[U.EMAIL]: `${name}@example.test`,
						[U.CIPHER]: 'fixture',
						[U.NONCE]: 'fixture'
					}))
				)
				.returning();
			for (const account of accounts)
				await database.db.insert(tables.userDevice).values({
					[V.USER_ID]: account[U.ID],
					[V.DEVICE_UUID]: 'fixture-device',
					[V.TITLE]: 'Fixture',
					[V.ACTIVE]: 1
				});
			const providers = [
				{ name: 'e2', id: StorageProvider.IDRIVE },
				{ name: 'r2', id: StorageProvider.CLOUDFLARE },
				{ name: 'oci', id: StorageProvider.OCI },
				{ name: 's3', id: StorageProvider.S3 }
			];
			const credentials = {
				appId: 'fixture-access',
				appKey: 'fixture-secret',
				bucketName: 'fixture-bucket',
				region: 'eu-central-1',
				accountId: 'fixture-account',
				namespace: 'fixture-namespace',
				endpoint: 'https://objects.example.test',
				forcePathStyle: true
			};
			const stores = new Map<string, number[]>();
			for (const provider of providers) {
				await database.db.insert(tables.provider).values({
					[P.ID]: provider.id,
					[P.TITLE]: provider.name,
					[P.FREE_BYTES]: 1024,
					[P.PRIORITY]: provider.id
				});
				const ids: number[] = [];
				for (const account of accounts) {
					const [credential] = await database.db
						.insert(tables.credential)
						.values({
							[C.USER_ID]: account[U.ID],
							[C.PROVIDER_ID]: provider.id,
							[C.CREDENTIALS]: credentials
						})
						.returning();
					const [storage] = await database.db
						.insert(tables.storage)
						.values({
							[S.USER_ID]: account[U.ID],
							[S.CREDENTIAL_ID]: credential[C.ID],
							[S.LIMIT_BYTES]: 1024,
							[S.LIMIT_FREE_BYTES]: 1024,
							[S.JSON]: {}
						})
						.returning();
					ids.push(storage[S.ID]);
				}
				stores.set(provider.name, ids);
			}
			const platform = {
				env: {
					HYPERDRIVE: { connectionString: database.url },
					FIFE_AUTH_CACHE: {
						get: async () => ({
							authorized: true,
							userId: accounts[0][U.ID],
							remoteAuthId: accounts[0][U.REMOTE_AUTH_ID],
							email: accounts[0][U.EMAIL]
						}),
						put: async () => {}
					}
				}
			};
			const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
			closeRoutes = () => dbModule.getDb(platform, true).$client.end();
			const part = `${'A'.repeat(43)}_1`;
			const handlers = new Map<string, any>();
			for (const provider of providers)
				handlers.set(
					provider.name,
					await vite.ssrLoadModule(`/src/routes/api/${provider.name}/get-upload-url/+server.ts`)
				);
			const call = async (name: string, body: unknown, headers: Record<string, string> = {}) => {
				const response = await handlers.get(name).POST({
					platform,
					request: new Request(`https://app.example.test/api/${name}/get-upload-url`, {
						method: 'POST',
						headers: {
							authorization: 'Bearer fixture-token',
							service: 'neon',
							device_uuid: 'fixture-device',
							'content-type': 'application/json',
							...headers
						},
						body: JSON.stringify(body)
					})
				});
				return response.json();
			};
			for (const provider of providers) {
				const input = { storage_id: stores.get(provider.name)![0], file_id: part };
				await t.test(
					`${provider.name} records the issued expiry without upgrading legacy users`,
					async () => {
						const before = Date.now();
						assert.equal((await call(provider.name, input)).success, 1);
						const recorded = await database.db.select().from(tables.vaultUploadCapability);
						assert.equal(recorded.length, 1);
						assert.equal(recorded[0].userId, accounts[0][U.ID]);
						assert.equal(recorded[0].generation, 'legacy');
						assert.ok(recorded[0].expiresAt >= before + 900_000);
						assert.ok(recorded[0].expiresAt <= Date.now() + 900_000);
						assert.deepEqual(await database.db.select().from(tables.vaultState), []);
					}
				);
				await t.test(
					`${provider.name} keeps the string URL contract and expires after 900 seconds`,
					async () => {
						const result = await call(provider.name, input);
						assert.equal(result.success, 1);
						assert.equal(typeof result.data, 'string');
						const url = new URL(result.data);
						assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
						assert.ok(url.pathname.endsWith(`/upload-policy-first/${part}`));
					}
				);
				await t.test(`${provider.name} does not sign a checksum of an absent body`, async () => {
					const result = await call(provider.name, input);
					assert.equal(result.success, 1);
					const query = new URL(result.data).searchParams;
					assert.equal(query.has('x-amz-checksum-crc32'), false);
					assert.equal(query.has('x-amz-checksum-sha256'), false);
				});
				await t.test(`${provider.name} rejects foreign and wrong-provider storage`, async () => {
					for (const storage_id of [
						stores.get(provider.name)![1],
						stores.get(provider.name === 'e2' ? 'r2' : 'e2')![0]
					]) {
						const result = await call(provider.name, { ...input, storage_id });
						assert.equal(result.success, 0);
						assert.equal(result.message, ErrorCode.NO_STORAGE);
					}
				});
				await t.test(`${provider.name} rejects malformed and out-of-prefix input`, async () => {
					for (const body of [null, [], 'invalid']) {
						const result = await call(provider.name, body);
						assert.equal(result.success, 0);
						assert.equal(result.message, ErrorCode.INVALID_JSON);
					}
					for (const file_id of ['../outside_1', 'another/path_1', `${part}/extra`]) {
						assert.equal((await call(provider.name, { ...input, file_id })).success, 0);
					}
				});
			}
			const generation = 'b'.repeat(32);
			await database.db.insert(tables.vaultState).values({ userId: accounts[0][U.ID], generation });
			for (const provider of providers)
				await t.test(`${provider.name} binds the URL to the active vault`, async () => {
					const input = { storage_id: stores.get(provider.name)![0], file_id: part };
					assert.equal((await call(provider.name, input)).success, 0);
					const result = await call(provider.name, input, {
						'x-fife-vault-protocol': '1',
						'x-fife-vault-generation': generation
					});
					assert.equal(result.success, 1);
					assert.ok(
						new URL(result.data).pathname.endsWith(
							`/upload-policy-first/vaults/${generation}/${part}`
						)
					);
				});
			await database.db
				.update(tables.userDevice)
				.set({ [V.ACTIVE]: 0 })
				.where(eq(tables.userDevice[V.USER_ID], accounts[0][U.ID]));
			for (const provider of providers)
				assert.equal(
					(
						await call(
							provider.name,
							{ storage_id: stores.get(provider.name)![0], file_id: part },
							{ 'x-fife-vault-protocol': '1', 'x-fife-vault-generation': generation }
						)
					).success,
					0
				);
		} finally {
			await closeRoutes?.();
			await vite.close();
			await database.close();
		}
	}
);
