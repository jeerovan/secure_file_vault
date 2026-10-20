import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';
import { S3Client, HeadBucketCommand } from '@aws-sdk/client-s3';
import { and, eq } from 'drizzle-orm';
import * as tables from '../src/lib/server/db/schema';
import {
	UserKeys as U,
	UserDeviceKeys as V,
	ProviderKeys as P,
	CredentialKeys as C,
	StorageKeys as S,
	StorageProvider
} from '../src/lib/server/db/keys';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

test(
	'provider registration persists discovered metadata for its authenticated user',
	{ skip: !recoveryTestUrl },
	async (t) => {
		const database = await createRecoveryDatabase();
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
			LOCAL_TEST_EMAIL: 'fixture@example.test',
			B2_KEY_ID: 'global-key-must-not-be-used',
			B2_APPLICATION_KEY: 'global-secret-must-not-be-used'
		});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		const originalFetch = globalThis.fetch;
		const originalSend = S3Client.prototype.send;
		let authMode = 'valid',
			providerUnavailable = false;
		let refreshGate: { appId: string; entered: () => void; wait: Promise<void> } | undefined;
		const capabilities = [
			'deleteFiles',
			'writeBuckets',
			'readBuckets',
			'readFiles',
			'shareFiles',
			'writeFiles',
			'listFiles'
		];
		globalThis.fetch = async (input, init) => {
			assert.equal(String(input), 'https://api.backblazeb2.com/b2api/v4/b2_authorize_account');
			const basic = new Headers(init?.headers).get('authorization')!;
			const [appId] = Buffer.from(basic.slice(6), 'base64').toString().split(':');
			assert.ok(appId.startsWith('fixture-'), 'Discovery must use the request credentials');
			assert.equal(init?.redirect, 'manual');
			const gate = refreshGate;
			if (appId === gate?.appId) {
				gate.entered();
				await gate.wait;
			}
			if (authMode === 'denied') return Response.json({ code: 'unauthorized' }, { status: 401 });
			if (authMode === 'malformed') return Response.json({ apiInfo: {} });
			return Response.json({
				accountId: `account-${appId}`,
				authorizationToken: `token-${appId}`,
				applicationKeyExpirationTimestamp: null,
				apiInfo: {
					storageApi: {
						apiUrl: 'https://api004.backblazeb2.com',
						downloadUrl: 'https://f004.backblazeb2.com',
						s3ApiUrl:
							authMode === 'unsafe-endpoint'
								? 'https://untrusted.example.test'
								: 'https://s3.us-west-004.backblazeb2.com',
						allowed: {
							capabilities,
							namePrefix: null,
							buckets:
								authMode === 'multiple-buckets'
									? [
											{ id: 'a', name: 'a' },
											{ id: 'b', name: 'b' }
										]
									: [{ id: `bucket-${appId}`, name: `bucket-${appId}` }]
						}
					}
				}
			});
		};
		S3Client.prototype.send = async function (command: unknown) {
			assert.ok(command instanceof HeadBucketCommand);
			if (providerUnavailable) throw new Error('fixture provider unavailable');
			return { $metadata: { httpStatusCode: 200 } };
		} as typeof S3Client.prototype.send;
		let closeRoutes: (() => Promise<void>) | undefined;
		try {
			const accounts = await database.db
				.insert(tables.user)
				.values(
					['first', 'second'].map((name) => ({
						[U.REMOTE_AUTH_ID]: `fixture-${name}`,
						[U.EMAIL]: `${name}@example.test`,
						[U.CIPHER]: 'fixture-cipher',
						[U.NONCE]: 'fixture-nonce'
					}))
				)
				.returning();
			for (const account of accounts)
				await database.db.insert(tables.userDevice).values({
					[V.USER_ID]: account[U.ID],
					[V.DEVICE_UUID]: `device-${account[U.ID]}`,
					[V.TITLE]: 'Fixture device',
					[V.ACTIVE]: 1
				});
			for (const id of [
				StorageProvider.BACKBLAZE,
				StorageProvider.IDRIVE,
				StorageProvider.CLOUDFLARE,
				StorageProvider.OCI,
				StorageProvider.S3
			])
				await database.db.insert(tables.provider).values({
					[P.ID]: id,
					[P.TITLE]: `Fixture ${id}`,
					[P.FREE_BYTES]: 1024,
					[P.PRIORITY]: id
				});
			let activeAccount = accounts[0];
			const platform = {
				env: {
					HYPERDRIVE: { connectionString: database.url },
					FIFE_AUTH_CACHE: {
						get: async () => ({
							authorized: true,
							userId: activeAccount[U.ID],
							remoteAuthId: activeAccount[U.REMOTE_AUTH_ID],
							email: activeAccount[U.EMAIL]
						}),
						put: async () => {}
					}
				}
			};
			const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
			closeRoutes = () => dbModule.getDb(platform, true).$client.end();
			const routes: Record<string, any> = {};
			for (const name of ['b2', 'e2', 'r2', 'oci', 's3'])
				routes[name] = await vite.ssrLoadModule(`/src/routes/api/${name}/add-account/+server.ts`);
			const variants = [
				{
					name: 'b2',
					id: StorageProvider.BACKBLAZE,
					extra: {},
					endpoint: 'https://s3.us-west-004.backblazeb2.com',
					region: 'us-west-004',
					style: true
				},
				{
					name: 'e2',
					id: StorageProvider.IDRIVE,
					extra: { region: 'eu-central-2' },
					endpoint: 'https://s3.eu-central-2.idrivee2.com',
					region: 'eu-central-2',
					style: true
				},
				{
					name: 'r2',
					id: StorageProvider.CLOUDFLARE,
					extra: { accountId: 'fixture-account' },
					endpoint: 'https://fixture-account.r2.cloudflarestorage.com',
					region: 'auto',
					style: false
				},
				{
					name: 'oci',
					id: StorageProvider.OCI,
					extra: { namespace: 'fixture-namespace', region: 'us-ashburn-1' },
					endpoint: 'https://fixture-namespace.compat.objectstorage.us-ashburn-1.oraclecloud.com',
					region: 'us-ashburn-1',
					style: true
				},
				{
					name: 's3',
					id: StorageProvider.S3,
					extra: {
						endpoint: 'https://objects.example.test',
						region: 'fixture-region',
						force_path_style: false
					},
					endpoint: 'https://objects.example.test',
					region: 'fixture-region',
					style: false
				}
			];
			async function call(name: string, body: unknown) {
				const request = new Request(`https://app.example.test/api/${name}/add-account`, {
					method: 'POST',
					headers: {
						authorization: 'Bearer fixture-token',
						service: 'neon',
						device_uuid: `device-${activeAccount[U.ID]}`,
						'content-type': 'application/json'
					},
					body: JSON.stringify(body)
				});
				const response = await routes[name].POST({ request, platform });
				return response.json();
			}
			async function credential(accountId: number, providerId: number) {
				const [row] = await database.db
					.select()
					.from(tables.credential)
					.where(
						and(
							eq(tables.credential[C.USER_ID], accountId),
							eq(tables.credential[C.PROVIDER_ID], providerId)
						)
					);
				return row;
			}
			for (const variant of variants) {
				await t.test(`${variant.name} saves user-specific S3 connection metadata`, async () => {
					for (const [index, account] of accounts.entries()) {
						activeAccount = account;
						const body = {
							app_id: `fixture-${variant.name}-${index}`,
							app_key: `fixture-secret-${index}`,
							...(variant.name === 'b2' ? {} : { bucket: `fixture-bucket-${index}` }),
							...variant.extra
						};
						assert.deepEqual(await call(variant.name, body), { success: 1 });
						const row = await credential(account[U.ID], variant.id);
						assert.equal(row[C.USER_ID], account[U.ID]);
						const data = row[C.CREDENTIALS] as Record<string, unknown>;
						assert.equal(data.appId, body.app_id);
						assert.equal(data.appKey, body.app_key);
						assert.equal(data.endpoint, variant.endpoint);
						assert.equal(data.region, variant.region);
						assert.equal(data.forcePathStyle, variant.style);
						const allocations = await database.db
							.select()
							.from(tables.storage)
							.where(eq(tables.storage[S.CREDENTIAL_ID], row[C.ID]));
						assert.equal(allocations.length, 1);
						assert.equal(allocations[0][S.USER_ID], account[U.ID]);
					}
					const otherBefore = await credential(accounts[1][U.ID], variant.id);
					activeAccount = accounts[0];
					assert.deepEqual(
						await call(variant.name, {
							app_id: `fixture-${variant.name}-replacement`,
							app_key: 'fixture-replacement-secret',
							...(variant.name === 'b2' ? {} : { bucket: 'fixture-replacement-bucket' }),
							...variant.extra
						}),
						{ success: 1 }
					);
					assert.deepEqual(await credential(accounts[1][U.ID], variant.id), otherBefore);
					const first = await credential(accounts[0][U.ID], variant.id);
					assert.equal((first[C.CREDENTIALS] as any).appId, `fixture-${variant.name}-replacement`);
					assert.equal(
						(
							await database.db
								.select()
								.from(tables.storage)
								.where(eq(tables.storage[S.CREDENTIAL_ID], first[C.ID]))
						).length,
						1
					);
				});
			}
			await t.test(
				'Backblaze token refresh preserves custom JSON and rediscovers S3 metadata',
				async () => {
					const row = await credential(accounts[0][U.ID], StorageProvider.BACKBLAZE);
					const data = { ...(row[C.CREDENTIALS] as any), migrationMarker: 'retain' };
					delete data.endpoint;
					delete data.region;
					delete data.forcePathStyle;
					await database.db
						.update(tables.credential)
						.set({ [C.CREDENTIALS]: data, [C.SERVER_UPDATED_AT]: Date.now() - 21 * 60 * 60_000 })
						.where(eq(tables.credential[C.ID], row[C.ID]));
					const [allocation] = await database.db
						.select()
						.from(tables.storage)
						.where(eq(tables.storage[S.CREDENTIAL_ID], row[C.ID]));
					const b2 = await vite.ssrLoadModule('/src/lib/server/backblaze.ts');
					const refreshed = await b2.authenticate(database.db, accounts[0][U.ID], allocation[S.ID]);
					assert.equal(refreshed.endpoint, 'https://s3.us-west-004.backblazeb2.com');
					assert.equal(refreshed.region, 'us-west-004');
					assert.equal(refreshed.migrationMarker, 'retain');
					assert.deepEqual(
						(await credential(accounts[0][U.ID], StorageProvider.BACKBLAZE))[C.CREDENTIALS],
						refreshed
					);
					assert.equal(
						await b2.authenticate(database.db, accounts[1][U.ID], allocation[S.ID]),
						undefined
					);
				}
			);
			await t.test(
				'failed refresh preserves the last successful metadata timestamp for retry',
				async () => {
					const row = await credential(accounts[0][U.ID], StorageProvider.BACKBLAZE);
					const oldTime = Date.now() - 21 * 60 * 60_000;
					await database.db
						.update(tables.credential)
						.set({ [C.SERVER_UPDATED_AT]: oldTime })
						.where(eq(tables.credential[C.ID], row[C.ID]));
					const [allocation] = await database.db
						.select()
						.from(tables.storage)
						.where(eq(tables.storage[S.CREDENTIAL_ID], row[C.ID]));
					const b2 = await vite.ssrLoadModule('/src/lib/server/backblaze.ts');
					authMode = 'denied';
					try {
						await b2.authenticate(database.db, accounts[0][U.ID], allocation[S.ID]);
						const after = await credential(accounts[0][U.ID], StorageProvider.BACKBLAZE);
						assert.deepEqual(after[C.CREDENTIALS], row[C.CREDENTIALS]);
						assert.equal(after[C.UPDATING], 0);
						assert.equal(after[C.SERVER_UPDATED_AT], oldTime);
					} finally {
						authMode = 'valid';
					}
				}
			);
			await t.test('an older refresh cannot overwrite newly connected credentials', async () => {
				activeAccount = accounts[0];
				const row = await credential(accounts[0][U.ID], StorageProvider.BACKBLAZE);
				await database.db
					.update(tables.credential)
					.set({ [C.SERVER_UPDATED_AT]: Date.now() - 21 * 60 * 60_000 })
					.where(eq(tables.credential[C.ID], row[C.ID]));
				const [allocation] = await database.db
					.select()
					.from(tables.storage)
					.where(eq(tables.storage[S.CREDENTIAL_ID], row[C.ID]));
				const b2 = await vite.ssrLoadModule('/src/lib/server/backblaze.ts');
				let enter!: () => void, release!: () => void;
				const entered = new Promise<void>((resolve) => {
					enter = resolve;
				});
				const wait = new Promise<void>((resolve) => {
					release = resolve;
				});
				refreshGate = { appId: (row[C.CREDENTIALS] as any).appId, entered: enter, wait };
				const pending = b2.authenticate(database.db, accounts[0][U.ID], allocation[S.ID]);
				try {
					await entered;
					assert.deepEqual(
						await call('b2', { app_id: 'fixture-b2-latest', app_key: 'fixture-latest-secret' }),
						{ success: 1 }
					);
				} finally {
					refreshGate = undefined;
					release();
				}
				const returned = await pending;
				const latest = await credential(accounts[0][U.ID], StorageProvider.BACKBLAZE);
				assert.equal((latest[C.CREDENTIALS] as any).appId, 'fixture-b2-latest');
				assert.equal(returned.appId, 'fixture-b2-latest');
				assert.equal(latest[C.UPDATING], 0);
			});
			for (const mode of ['denied', 'malformed', 'unsafe-endpoint', 'multiple-buckets']) {
				await t.test(
					`Backblaze ${mode} discovery leaves existing credentials unchanged`,
					async () => {
						activeAccount = accounts[0];
						authMode = mode;
						const before = await database.db.select().from(tables.credential);
						try {
							const result = await call('b2', {
								app_id: 'fixture-invalid',
								app_key: 'fixture-secret'
							});
							assert.equal(result.success, 0);
							assert.deepEqual(await database.db.select().from(tables.credential), before);
						} finally {
							authMode = 'valid';
						}
					}
				);
			}
			await t.test(
				'failed S3 verification leaves the previous credential JSON unchanged',
				async () => {
					const before = await database.db.select().from(tables.credential);
					providerUnavailable = true;
					try {
						for (const variant of variants) {
							assert.equal(
								(
									await call(variant.name, {
										app_id: 'fixture-invalid',
										app_key: 'fixture-secret',
										bucket: 'fixture-bucket',
										...variant.extra
									})
								).success,
								0
							);
						}
						assert.deepEqual(await database.db.select().from(tables.credential), before);
					} finally {
						providerUnavailable = false;
					}
				}
			);
		} finally {
			globalThis.fetch = originalFetch;
			S3Client.prototype.send = originalSend;
			await closeRoutes?.();
			await vite.close();
			await database.close();
		}
	}
);
