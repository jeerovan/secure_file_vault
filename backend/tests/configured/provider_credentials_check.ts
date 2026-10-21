// Provider checks use disposable local SQL; opt-in writes stay under fixture prefixes.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import dotenv from 'dotenv';
import { createServer } from 'vite';
import { and, eq } from 'drizzle-orm';
import * as tables from '../../src/lib/server/db/schema';
import {
	UserKeys as U,
	UserDeviceKeys as V,
	ProviderKeys as P,
	CredentialKeys as C,
	StorageKeys as S,
	StorageProvider
} from '../../src/lib/server/db/keys';
import { createRecoveryDatabase, recoveryTestUrl } from '../support/recoveryDatabase';
import { checkProviderTransfers } from './provider_transfers';
import { checkProviderInFlightUpload } from './provider_in_flight';
import { checkManagedProviderUploads } from './provider_managed_uploads';
import { checkProviderResetLifecycle } from './provider_reset_lifecycle';

const writes = process.env.FIFE_RUN_PROVIDER_WRITE_CHECKS === '1';

test(
	'configured provider credentials register through the local backend',
	{ skip: !recoveryTestUrl || (!writes && process.env.FIFE_RUN_PROVIDER_READ_CHECKS !== '1') },
	async (t) => {
		const inputs = dotenv.parse(await readFile('.env', 'utf8'));
		const providers = [
			{
				name: 'b2',
				id: StorageProvider.BACKBLAZE,
				fields: { app_id: 'B2_KEY_ID', app_key: 'B2_APPLICATION_KEY' }
			},
			{
				name: 'e2',
				id: StorageProvider.IDRIVE,
				fields: {
					region: 'E2_REGION',
					bucket: 'E2_BUCKET_NAME',
					app_id: 'E2_ACCESS_KEY_ID',
					app_key: 'E2_SECRET_ACCESS_KEY'
				}
			},
			{
				name: 'r2',
				id: StorageProvider.CLOUDFLARE,
				fields: {
					accountId: 'R2_ACCOUNT_ID',
					bucket: 'R2_BUCKET_NAME',
					app_id: 'R2_ACCESS_KEY_ID',
					app_key: 'R2_SECRET_ACCESS_KEY'
				}
			},
			{
				name: 'oci',
				id: StorageProvider.OCI,
				fields: {
					namespace: 'OCI_NAMESPACE',
					region: 'OCI_REGION',
					bucket: 'OCI_BUCKET_NAME',
					app_id: 'OCI_ACCESS_KEY_ID',
					app_key: 'OCI_SECRET_ACCESS_KEY'
				}
			},
			{
				name: 's3',
				id: StorageProvider.S3,
				fields: {
					endpoint: 'S3_ENDPOINT',
					region: 'S3_REGION',
					bucket: 'S3_BUCKET_NAME',
					app_id: 'S3_ACCESS_KEY_ID',
					app_key: 'S3_SECRET_ACCESS_KEY'
				}
			}
		];
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
			LOCAL_TEST_AUTH_ENABLED: 'false',
			LOCAL_TEST_AUTH_TOKEN: 'fixture-local',
			LOCAL_TEST_USER_ID: 'fixture-local-user',
			LOCAL_TEST_EMAIL: 'fixture@example.test'
		});
		if (process.env.FIFE_RUN_PROVIDER_RESET_CHECKS === '1')
			Object.assign(process.env, {
				RECOVERY_RESET_ENABLED: 'true',
				RECOVERY_WORKER_READY: 'true',
				RECOVERY_RESET_EMAILS: 'jeevan@jeero.one'
			});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		let closeRoutes: (() => Promise<void>) | undefined;
		const managedCleanupPending = new Set<string>();
		try {
			const [account] = await database.db
				.insert(tables.user)
				.values({
					[U.REMOTE_AUTH_ID]: writes
						? `fife-provider-url-${randomUUID()}`
						: 'local-provider-read-check',
					[U.EMAIL]: 'fixture@example.test',
					[U.CIPHER]: 'fixture-cipher',
					[U.NONCE]: 'fixture-nonce'
				})
				.returning();
			if (writes) t.diagnostic(`Generated cloud prefix: ${account[U.REMOTE_AUTH_ID]}/`);
			if (process.env.FIFE_RUN_PROVIDER_RESET_CHECKS === '1')
				await database.db.insert(tables.user).values({
					[U.REMOTE_AUTH_ID]: 'fife',
					[U.EMAIL]: 'service@example.test',
					[U.CIPHER]: 'fixture-service-envelope',
					[U.NONCE]: 'fixture-service-nonce'
				});
			await database.db.insert(tables.userDevice).values({
				[V.USER_ID]: account[U.ID],
				[V.DEVICE_UUID]: 'fixture-device',
				[V.TITLE]: 'Local read check',
				[V.ACTIVE]: 1
			});
			for (const provider of providers)
				await database.db.insert(tables.provider).values({
					[P.ID]: provider.id,
					[P.TITLE]: provider.name,
					[P.FREE_BYTES]: 1024,
					[P.PRIORITY]: provider.id
				});
			const platform = {
				env: {
					HYPERDRIVE: { connectionString: database.url },
					FIFE_AUTH_CACHE: {
						get: async () => ({
							authorized: true,
							userId: account[U.ID],
							remoteAuthId: account[U.REMOTE_AUTH_ID],
							email: account[U.EMAIL]
						}),
						put: async () => {}
					}
				}
			};
			const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
			closeRoutes = () => dbModule.getDb(platform, true).$client.end();
			const selected = process.env.FIFE_PROVIDER_TEST_NAMES?.split(',');
			for (const provider of providers.filter(
				(provider) => !selected || selected.includes(provider.name)
			)) {
				const fields = Object.entries(provider.fields) as [string, string][];
				const missing = fields.filter(([, name]) => !inputs[name]?.trim()).map(([, name]) => name);
				await t.test(
					`${provider.name} discovers and stores its own metadata`,
					{ skip: missing.length ? `Configure ${missing.join(', ')}` : false },
					async (providerTest) => {
						const body: Record<string, unknown> = Object.fromEntries(
							fields.map(([field, name]) => [field, inputs[name]])
						);
						if (provider.name === 's3')
							body.force_path_style = inputs.S3_FORCE_PATH_STYLE !== 'false';
						const handler = await vite.ssrLoadModule(
							`/src/routes/api/${provider.name}/add-account/+server.ts`
						);
						const request = new Request(
							`https://local.example.test/api/${provider.name}/add-account`,
							{
								method: 'POST',
								headers: {
									authorization: 'Bearer fixture-token',
									service: 'neon',
									device_uuid: 'fixture-device',
									'content-type': 'application/json'
								},
								body: JSON.stringify(body)
							}
						);
						const result = await (await handler.POST({ request, platform })).json();
						assert.equal(
							result.success === 1,
							true,
							`Provider verification failed (safe code: ${typeof result.message === 'number' ? result.message : 'unavailable'})`
						);
						const [row] = await database.db
							.select()
							.from(tables.credential)
							.where(
								and(
									eq(tables.credential[C.USER_ID], account[U.ID]),
									eq(tables.credential[C.PROVIDER_ID], provider.id)
								)
							);
						const data = row?.[C.CREDENTIALS] as Record<string, unknown> | undefined;
						assert.equal(
							Boolean(
								data &&
								data.appId === body.app_id &&
								data.appKey === body.app_key &&
								typeof data.endpoint === 'string' &&
								typeof data.region === 'string' &&
								typeof data.forcePathStyle === 'boolean'
							),
							true,
							'Verified credentials/metadata must be persisted only in the local user row'
						);
						if (writes) {
							const [storage] = await database.db
								.select()
								.from(tables.storage)
								.where(eq(tables.storage[S.CREDENTIAL_ID], row[C.ID]));
							assert.ok(storage);
							if (process.env.FIFE_RUN_PROVIDER_RESET_CHECKS === '1') {
								await providerTest.test(
									`${provider.name} resets and reuses its retained connection`,
									async (resetTest) => {
										managedCleanupPending.add(provider.name);
										await checkProviderResetLifecycle({
											db: database.db,
											vite,
											databaseUrl: database.url,
											providerName: provider.name,
											providerId: provider.id,
											credentials: data!,
											diagnostic: (message) => resetTest.diagnostic(message),
											onCleanupVerified: () => {
												managedCleanupPending.delete(provider.name);
											}
										});
									}
								);
								return;
							}
							if (process.env.FIFE_RUN_PROVIDER_MANAGED_CHECKS === '1') {
								const managed = await vite.ssrLoadModule('/src/lib/server/managedUpload.ts');
								const ports = await vite.ssrLoadModule('/src/lib/server/managedUploadStorage.ts');
								await providerTest.test(
									`${provider.name} manages completion, late bodies and abandoned uploads`,
									async () => {
										managedCleanupPending.add(provider.name);
										await checkManagedProviderUploads({
											onCleanupVerified: () => {
												managedCleanupPending.delete(provider.name);
											},
											db: database.db,
											userId: account[U.ID],
											storageId: storage[S.ID],
											target: {
												providerId: provider.id,
												prefix: `${account[U.REMOTE_AUTH_ID]}/`,
												credentials: data!
											},
											drain: (now) =>
												managed.drainManagedUploads(
													database.db,
													new ports.ProviderManagedUploadStorage(),
													{ now: () => now, limit: 10 }
												),
											download: async (file_id) => {
												const route = await vite.ssrLoadModule(
													`/src/routes/api/${provider.name}/get-download-url/+server.ts`
												);
												const response = await route.POST({
													platform,
													request: new Request('https://local.example.test/api/download', {
														method: 'POST',
														headers: {
															authorization: 'Bearer fixture-token',
															service: 'neon',
															device_uuid: 'fixture-device',
															'content-type': 'application/json'
														},
														body: JSON.stringify({ file_id, storage_id: storage[S.ID] })
													})
												});
												return response.json();
											},
											call: async (action, payload) => {
												const route = await vite.ssrLoadModule(
													`/src/routes/api/uploads/${action}/+server.ts`
												);
												const response = await route.POST({
													platform,
													request: new Request(`https://local.example.test/api/uploads/${action}`, {
														method: 'POST',
														headers: {
															authorization: 'Bearer fixture-token',
															service: 'neon',
															device_uuid: 'fixture-device',
															'content-type': 'application/json'
														},
														body: JSON.stringify(payload)
													})
												});
												return { status: response.status, body: await response.json() };
											}
										});
									}
								);
								return;
							}
							if (process.env.FIFE_RUN_PROVIDER_IN_FLIGHT_CHECKS === '1') {
								await providerTest.test(
									`${provider.name} finishes a PUT across expiry and cleanup`,
									async (inFlightTest) => {
										await checkProviderInFlightUpload(
											{
												providerId: provider.id,
												prefix: `${account[U.REMOTE_AUTH_ID]}/`,
												credentials: data!
											},
											(message) => inFlightTest.diagnostic(message)
										);
									}
								);
								return;
							}
							await providerTest.test(
								`${provider.name} transfers, expires and cleans up generated objects`,
								async () => {
									await checkProviderTransfers({
										providerId: provider.id,
										prefix: `${account[U.REMOTE_AUTH_ID]}/`,
										credentials: data!,
										call: async (action, payload) => {
											const route = await vite.ssrLoadModule(
												`/src/routes/api/${provider.name}/${action}/+server.ts`
											);
											return (
												await route.POST({
													platform,
													request: new Request(
														`https://local.example.test/api/${provider.name}/${action}`,
														{
															method: 'POST',
															headers: {
																authorization: 'Bearer fixture-token',
																service: 'neon',
																device_uuid: 'fixture-device',
																'content-type': 'application/json'
															},
															body: JSON.stringify({ storage_id: storage[S.ID], ...payload })
														}
													)
												})
											).json();
										}
									});
								}
							);
						}
					}
				);
			}
		} finally {
			await closeRoutes?.();
			await vite.close();
			if (managedCleanupPending.size) {
				await writeFile(
					`/tmp/fife-provider-cleanup-${randomUUID()}.json`,
					JSON.stringify({
						databaseUrl: database.url,
						providers: [...managedCleanupPending]
					}),
					{ mode: 0o600 }
				);
				t.diagnostic(
					'Cloud verification incomplete; private disposable SQL cleanup records retained for retry.'
				);
			}
			await database.close({ preserve: managedCleanupPending.size > 0 });
		}
	}
);
