import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';
import { and, eq, sql } from 'drizzle-orm';
import { setTimeout as delay } from 'node:timers/promises';
import * as tables from '../src/lib/server/db/schema';
import {
	UserKeys as U,
	UserDataKeys as D,
	UserDeviceKeys as V,
	CredentialKeys as C,
	StorageKeys as S,
	TempStorageKeys as T,
	ProviderKeys as P,
	FileKeys as F,
	PartKeys as A,
	ItemKeys as I
} from '../src/lib/server/db/keys';
import { recoveryHash, RecoveryFault } from '../src/lib/server/recoverySession';
import type { RecoveryStorage } from '../src/lib/server/recoveryStorage';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

test(
	'reset transactions and durable cleanup use isolated PostgreSQL',
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
			RECOVERY_RESET_ENABLED: 'true',
			RECOVERY_WORKER_READY: 'true',
			RECOVERY_RESET_EMAILS: 'fixture@example.test'
		});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		const core = await vite.ssrLoadModule('/src/lib/server/recoveryReset.ts');
		const cleanup = await vite.ssrLoadModule('/src/lib/server/recoveryCleanup.ts');
		const uploads = await vite.ssrLoadModule('/src/lib/server/uploadCapability.ts');
		const { db } = database;
		const oldCipher = Buffer.alloc(48, 1).toString('base64');
		const newCipher = Buffer.alloc(48, 2).toString('base64');
		const nonce = Buffer.alloc(24, 3).toString('base64');
		const challenge = Buffer.alloc(32, 4).toString('base64url');
		let now = Date.parse('2026-10-19T12:00:00Z');
		let closeRouteDatabase: (() => Promise<void>) | undefined;
		const cloud: RecoveryStorage = {
			async probe() {},
			async step() {
				return { cursor: {}, done: true };
			}
		};
		async function seed(adapter = cloud, uploadAccountingSince?: number) {
			await db.delete(tables.user);
			await db.delete(tables.provider);
			now = Date.parse('2026-10-19T12:00:00Z');
			for (const id of [1, 6])
				await db.insert(tables.provider).values({
					[P.ID]: id,
					[P.TITLE]: `Fixture ${id}`,
					[P.FREE_BYTES]: 1024,
					[P.PRIORITY]: id
				});
			const accounts = await db
				.insert(tables.user)
				.values([
					{
						[U.REMOTE_AUTH_ID]: 'fixture-user',
						[U.EMAIL]: 'fixture@example.test',
						[U.CIPHER]: oldCipher,
						[U.NONCE]: nonce
					},
					{
						[U.REMOTE_AUTH_ID]: 'other-user',
						[U.EMAIL]: 'other@example.test',
						[U.CIPHER]: oldCipher,
						[U.NONCE]: nonce
					},
					{
						[U.REMOTE_AUTH_ID]: 'fife',
						[U.EMAIL]: 'service@example.test',
						[U.CIPHER]: oldCipher,
						[U.NONCE]: nonce
					}
				])
				.returning();
			const [account, other, service] = accounts;
			const [shared, owned] = await db
				.insert(tables.credential)
				.values([
					{
						[C.USER_ID]: service[U.ID],
						[C.PROVIDER_ID]: 1,
						[C.CREDENTIALS]: {
							appId: 'shared-id',
							appKey: 'shared-key',
							bucketName: 'shared-bucket',
							bucketId: 'shared-bucket-id',
							authorizationToken: 'must-not-copy-provider-token'
						}
					},
					{
						[C.USER_ID]: account[U.ID],
						[C.PROVIDER_ID]: 6,
						[C.CREDENTIALS]: {
							appId: 'owned-id',
							appKey: 'owned-key',
							bucketName: 'customer-bucket',
							region: 'auto',
							endpoint: 'https://s3.example.test',
							forcePathStyle: true
						}
					}
				])
				.returning();
			const allocations = await db
				.insert(tables.storage)
				.values([
					{
						[S.USER_ID]: account[U.ID],
						[S.CREDENTIAL_ID]: shared[C.ID],
						[S.LIMIT_BYTES]: 1024,
						[S.LIMIT_FREE_BYTES]: 1024,
						[S.JSON]: {}
					},
					{
						[S.USER_ID]: account[U.ID],
						[S.CREDENTIAL_ID]: owned[C.ID],
						[S.LIMIT_BYTES]: 1024,
						[S.LIMIT_FREE_BYTES]: 1024,
						[S.JSON]: {}
					},
					{
						[S.USER_ID]: other[U.ID],
						[S.CREDENTIAL_ID]: shared[C.ID],
						[S.LIMIT_BYTES]: 1024,
						[S.LIMIT_FREE_BYTES]: 1024,
						[S.JSON]: {}
					}
				])
				.returning();
			await db.insert(tables.userData).values({
				[D.USER_ID]: account[U.ID],
				[D.DEVICE_UUID]: 'old-device',
				[D.USER_NAME]: 'old-name',
				[D.PROFILE_IMAGE]: 'old-image',
				[D.PRO_ID]: 'paid-association',
				[D.PLAN_EXPIRES_AT]: now + 30 * 86400_000
			});
			await db.insert(tables.userDevice).values([
				{ [V.USER_ID]: account[U.ID], [V.DEVICE_UUID]: 'old-device', [V.TITLE]: 'Old device' },
				{
					[V.USER_ID]: account[U.ID],
					[V.DEVICE_UUID]: 'old-device-two',
					[V.TITLE]: 'Second old device'
				},
				{ [V.USER_ID]: other[U.ID], [V.DEVICE_UUID]: 'other-device', [V.TITLE]: 'Other device' }
			]);
			const [file] = await db
				.insert(tables.file)
				.values({
					[F.USER_ID]: account[U.ID],
					[F.DEVICE_UUID]: 'old-device',
					[F.FILE_HASH]: 'a'.repeat(43),
					[F.CLIENT_UPDATED_AT]: 100,
					[F.STORAGE_ID]: allocations[1][S.ID],
					[F.PROVIDER_ID]: 6
				})
				.returning();
			await db.insert(tables.part).values({
				[A.USER_ID]: account[U.ID],
				[A.DEVICE_UUID]: 'old-device',
				[A.FILE_ID]: file[F.ID],
				[A.PART_NUMBER]: 1,
				[A.PART_SIZE]: 10
			});
			await db.insert(tables.item).values({
				[I.USER_ID]: account[U.ID],
				[I.DEVICE_UUID]: 'old-device',
				[I.ITEM_ID]: 'old-item',
				[I.TEXT_CIPHER]: 'cipher',
				[I.TEXT_NONCE]: 'nonce',
				[I.KEY_CIPHER]: 'cipher',
				[I.KEY_NONCE]: 'nonce'
			});
			const session = {
				userId: 'fixture-user',
				email: 'fixture@example.test',
				createdAt: now - 60_000,
				expiresAt: now + 30 * 86400_000,
				hash: await recoveryHash('fixture-session')
			};
			const controller = new core.RecoveryResetService(
				db,
				account[U.ID],
				session,
				adapter,
				() => now,
				uploadAccountingSince
			);
			const operationId = crypto.randomUUID();
			const preparation = {
				operationId,
				expectedGeneration: 'legacy',
				challengeHash: await recoveryHash(challenge)
			};
			const confirmation = { operationId, challenge, cipher: newCipher, nonce };
			return {
				account,
				other,
				service,
				shared,
				owned,
				allocations,
				session,
				controller,
				operationId,
				preparation,
				confirmation
			};
		}
		async function currentUser(id: number) {
			return (await db.select().from(tables.user).where(eq(tables.user[U.ID], id)))[0];
		}
		try {
			await t.test(
				'reset leaves no replacement key envelope before explicit key creation',
				async () => {
					const f = await seed(cloud, 0);
					await f.controller.prepare(f.preparation);
					const result = await f.controller.confirm(f.confirmation);
					assert.equal(result.phase, 'cleanup_pending');
					const account = await currentUser(f.account[U.ID]);
					assert.equal(account[U.CIPHER], null);
					assert.equal(account[U.NONCE], null);
				}
			);
			await t.test(
				'reset retains in-flight uploads and cannot finish until their cleanup is verified',
				async () => {
					const f = await seed();
					const id = crypto.randomUUID();
					await db.insert(tables.vaultUpload).values({
						id,
						userId: f.account[U.ID],
						deviceUuid: 'old-device',
						generation: 'legacy',
						storageId: f.allocations[1][S.ID],
						providerId: 6,
						objectKey: `fixture-user/${'a'.repeat(43)}_1`,
						partName: `${'a'.repeat(43)}_1`,
						credentials: f.owned[C.CREDENTIALS] as Record<string, unknown>,
						receiptHash: '0'.repeat(64),
						contentLength: 10,
						sha1: 'a'.repeat(40),
						md5: 'AAAAAAAAAAAAAAAAAAAAAA==',
						uploadId: 'provider-upload',
						phase: 'uploading',
						createdAt: now,
						updatedAt: now
					});
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					const [tracked] = await db.select().from(tables.vaultUpload);
					assert.equal(tracked.retired, 1);
					assert.equal(tracked.operationId, f.operationId);
					assert.equal(tracked.uploadId, 'provider-upload');
					assert.deepEqual(
						await db.select().from(tables.part).where(eq(tables.part[A.USER_ID], f.account[U.ID])),
						[]
					);
					now = committed.notBefore + 1;
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 });
					assert.equal((await f.controller.status(f.operationId)).phase, 'cleanup_pending');
					assert.equal((await db.select().from(tables.vaultState))[0].ready, 0);
					await db
						.update(tables.vaultUpload)
						.set({ phase: 'deleted' })
						.where(eq(tables.vaultUpload.id, id));
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 });
					assert.equal((await f.controller.status(f.operationId)).phase, 'ready');
				}
			);
			const authorization = (userId: number) => ({
				authorized: true,
				userId,
				deviceUuid: 'old-device',
				vaultProtocol: 0,
				vaultGeneration: 'untrusted-stale-value'
			});
			await t.test(
				'reset waits for issuance to commit its expiry under the account lock',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					let entered!: () => void, release!: () => void;
					const issued = new Promise<void>((resolve) => (entered = resolve));
					const hold = new Promise<void>((resolve) => (release = resolve));
					let issuerPid = 0;
					const pendingUpload = uploads.withUploadAuthorization(
						db,
						authorization(f.account[U.ID]),
						48 * 3600,
						async (tx: any) => {
							issuerPid = Number((await tx.execute(sql`SELECT pg_backend_pid() AS pid`))[0].pid);
							entered();
							await hold;
							return Response.json({ success: 1, data: 'fixture-url' });
						},
						() => now
					);
					await Promise.race([
						issued,
						pendingUpload.then(() => {
							throw new Error('Issuance ended before entering the provider callback');
						})
					]);
					let settled = false;
					const pendingReset = f.controller.confirm(f.confirmation).finally(() => (settled = true));
					void pendingReset.catch(() => {});
					try {
						let blocked = false;
						for (let attempt = 0; attempt < 500 && !blocked && !settled; attempt++) {
							const [waiting] =
								await db.$client`SELECT count(*)::int AS count FROM pg_stat_activity WHERE datname=current_database() AND ${issuerPid} = ANY(pg_blocking_pids(pid))`;
							blocked = waiting.count > 0;
							if (!blocked) await delay(10);
						}
						assert.equal(
							blocked,
							true,
							'Reset must wait on the same account lock held during issuance'
						);
						assert.equal(settled, false);
					} finally {
						release();
						await Promise.allSettled([pendingUpload, pendingReset]);
					}
					const [response, committed] = await Promise.all([pendingUpload, pendingReset]);
					assert.equal((await response.json()).success, 1);
					const [record] = await db.select().from(tables.vaultUploadCapability);
					assert.equal(record.generation, 'legacy', 'Use the freshly authorized generation');
					assert.equal(record.expiresAt, now + 48 * 3600_000);
					assert.equal(committed.notBefore, record.expiresAt);
				}
			);
			await t.test(
				'a winning reset prevents the old request from invoking provider issuance',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					await f.controller.confirm(f.confirmation);
					let called = false;
					const response = await uploads.withUploadAuthorization(
						db,
						authorization(f.account[U.ID]),
						900,
						async () => {
							called = true;
							return Response.json({ success: 1 });
						}
					);
					assert.equal(called, false);
					assert.equal((await response.json()).success, 0);
					assert.deepEqual(await db.select().from(tables.vaultUploadCapability), []);
				}
			);
			await t.test('failed issuance or accounting cannot expose a success response', async () => {
				const f = await seed(),
					auth = authorization(f.account[U.ID]);
				const failure = await uploads.withUploadAuthorization(db, auth, 900, async () =>
					Response.json({ success: 0, message: 15 })
				);
				assert.equal((await failure.json()).success, 0);
				await assert.rejects(
					uploads.withUploadAuthorization(db, auth, 900, async () => {
						throw new Error('fixture-provider-failed');
					}),
					/fixture-provider-failed/
				);
				assert.deepEqual(await db.select().from(tables.vaultUploadCapability), []);
				await db.$client.unsafe(
					`CREATE FUNCTION reject_fixture_capability() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture-accounting-failed'; END $$`
				);
				await db.$client.unsafe(
					'CREATE TRIGGER reject_fixture_capability BEFORE INSERT ON vault_upload_capability FOR EACH ROW EXECUTE FUNCTION reject_fixture_capability()'
				);
				try {
					await assert.rejects(
						uploads.withUploadAuthorization(db, auth, 900, async (tx: any) => {
							await tx
								.update(tables.user)
								.set({ [U.CIPHER]: 'must-rollback' })
								.where(eq(tables.user[U.ID], f.account[U.ID]));
							return Response.json({ success: 1, data: 'must-not-escape' });
						})
					);
					assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
					assert.deepEqual(await db.select().from(tables.vaultUploadCapability), []);
				} finally {
					await db.$client.unsafe(
						'DROP TRIGGER reject_fixture_capability ON vault_upload_capability'
					);
					await db.$client.unsafe('DROP FUNCTION reject_fixture_capability()');
				}
			});
			await t.test(
				'accounting without accessible cleanup targets cannot mark a vault ready',
				async () => {
					const f = await seed();
					await db.delete(tables.storage).where(eq(tables.storage[S.USER_ID], f.account[U.ID]));
					await db
						.delete(tables.credential)
						.where(eq(tables.credential[C.USER_ID], f.account[U.ID]));
					await db
						.insert(tables.vaultUploadCapability)
						.values({ userId: f.account[U.ID], generation: 'legacy', expiresAt: now + 900_000 });
					await f.controller.prepare(f.preparation);
					await assert.rejects(
						f.controller.confirm(f.confirmation),
						(error: any) => error.code === 'storage_access_required'
					);
					assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
					assert.equal((await f.controller.status(f.operationId)).phase, 'prepared');
				}
			);
			await t.test(
				'reset retains the issued expiry high-water mark and committed deadline',
				async () => {
					const f = await seed();
					const expiresAt = now + 48 * 3600_000;
					await db.insert(tables.vaultUploadCapability).values([
						{ userId: f.account[U.ID], generation: 'legacy', expiresAt },
						{
							userId: f.account[U.ID],
							generation: 'stale-generation',
							expiresAt: now + 7 * 86400_000
						},
						{ userId: f.other[U.ID], generation: 'legacy', expiresAt: now + 7 * 86400_000 }
					]);
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					assert.equal(committed.notBefore, expiresAt);
					now += 1_000;
					assert.equal((await f.controller.confirm(f.confirmation)).notBefore, committed.notBefore);
					assert.equal((await f.controller.status(f.operationId)).notBefore, committed.notBefore);
				}
			);
			await t.test('accounted FiFe and S3 vaults use a fifteen-minute reset window', async () => {
				for (const seconds of [null, -1, 900]) {
					const f = await seed(cloud, 0);
					if (seconds !== null)
						await db.insert(tables.vaultUploadCapability).values({
							userId: f.account[U.ID],
							generation: 'legacy',
							expiresAt: now + seconds * 1000
						});
					await f.controller.prepare(f.preparation);
					const result = await f.controller.confirm(f.confirmation);
					assert.equal(result.notBefore, now + 15 * 60_000);
					assert.equal(result.phase, 'cleanup_pending');
				}
			});
			await t.test('accounted S3-only vaults do not restart the old one-hour wait', async () => {
				const f = await seed(cloud, 0);
				await db.delete(tables.storage).where(eq(tables.storage[S.ID], f.allocations[0][S.ID]));
				await f.controller.prepare(f.preparation);
				assert.equal((await f.controller.confirm(f.confirmation)).notBefore, now + 15 * 60_000);
			});
			await t.test(
				'a recent accounting cutover drains once instead of restarting at reset',
				async () => {
					const cutover = now - 60 * 60_000;
					const f = await seed(cloud, cutover);
					await f.controller.prepare(f.preparation);
					assert.equal(
						(await f.controller.confirm(f.confirmation)).notBefore,
						cutover + 24 * 60 * 60_000 + 60_000
					);
				}
			);
			await t.test(
				'an accounted native grant still extends the fifteen-minute window',
				async () => {
					const f = await seed(cloud, 0);
					const expiresAt = now + 24 * 60 * 60_000;
					await db.insert(tables.vaultUploadCapability).values({
						userId: f.account[U.ID],
						generation: 'legacy',
						expiresAt
					});
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					assert.equal(committed.notBefore, expiresAt);
					await db.delete(tables.vaultUploadCapability);
					now += 1_000;
					assert.equal((await f.controller.confirm(f.confirmation)).notBefore, committed.notBefore);
				}
			);
			await t.test(
				'changing rollout policy cannot shorten an already committed reset',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					assert.equal(committed.notBefore, now + 86400_000 + 60_000);
					const updated = new core.RecoveryResetService(
						db,
						f.account[U.ID],
						f.session,
						cloud,
						() => now,
						0
					);
					assert.equal((await updated.confirm(f.confirmation)).notBefore, committed.notBefore);
					assert.equal((await updated.status(f.operationId)).notBefore, committed.notBefore);
				}
			);
			await t.test('fifteen minutes never bypasses failed cloud verification', async () => {
				let failing = true;
				const adapter: RecoveryStorage = {
					async probe() {},
					async step() {
						if (failing) throw new RecoveryFault('storage_cleanup_blocked');
						return { cursor: {}, done: true };
					}
				};
				const f = await seed(adapter, 0);
				await f.controller.prepare(f.preparation);
				const committed = await f.controller.confirm(f.confirmation);
				assert.equal(committed.notBefore, now + 15 * 60_000);
				now += 15 * 60_000 - 1;
				await cleanup.drainRecoveryCleanup(db, adapter, { now: () => now, limit: 4 });
				assert.equal((await f.controller.status(f.operationId)).phase, 'cleanup_pending');
				now += 1;
				await cleanup.drainRecoveryCleanup(db, adapter, { now: () => now, limit: 4 });
				assert.equal((await f.controller.status(f.operationId)).phase, 'cleanup_pending');
				assert.equal((await db.select().from(tables.vaultState))[0].ready, 0);
				failing = false;
				now += 2 * 60_000;
				await cleanup.drainRecoveryCleanup(db, adapter, { now: () => now, limit: 4 });
				assert.equal((await f.controller.status(f.operationId)).phase, 'ready');
			});
			await t.test(
				'missing or shorter accounting never shortens the conservative rollout floor',
				async () => {
					for (const seconds of [null, -1, 900]) {
						const f = await seed();
						if (seconds !== null)
							await db.insert(tables.vaultUploadCapability).values({
								userId: f.account[U.ID],
								generation: 'legacy',
								expiresAt: now + seconds * 1000
							});
						await f.controller.prepare(f.preparation);
						assert.equal(
							(await f.controller.confirm(f.confirmation)).notBefore,
							now + 86400_000 + 60_000
						);
					}
				}
			);
			await t.test('S3-only vaults retain the previous one-hour floor', async () => {
				const f = await seed();
				await db.delete(tables.storage).where(eq(tables.storage[S.ID], f.allocations[0][S.ID]));
				await db
					.insert(tables.vaultUploadCapability)
					.values({ userId: f.account[U.ID], generation: 'legacy', expiresAt: now + 900_000 });
				await f.controller.prepare(f.preparation);
				assert.equal(
					(await f.controller.confirm(f.confirmation)).notBefore,
					now + 3600_000 + 60_000
				);
			});
			await t.test('preparing and retrying never modifies the existing vault', async () => {
				const f = await seed();
				const prepared = await f.controller.prepare(f.preparation);
				assert.equal(prepared.phase, 'prepared');
				assert.deepEqual(await f.controller.prepare(f.preparation), prepared);
				assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
				assert.equal((await db.select().from(tables.userDevice)).length, 3);
				assert.equal((await db.select().from(tables.vaultState)).length, 0);
				assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 0);
			});
			await t.test(
				'reset retains provider connections and credentials through cleanup and retries',
				async () => {
					const f = await seed();
					await db.insert(tables.credential).values({
						[C.USER_ID]: f.account[U.ID],
						[C.PROVIDER_ID]: 6,
						[C.CREDENTIALS]: {
							...(f.owned[C.CREDENTIALS] as Record<string, unknown>),
							bucketName: 'saved-unlinked-bucket'
						}
					});
					const [pendingFile] = await db
						.select()
						.from(tables.file)
						.where(eq(tables.file[F.USER_ID], f.account[U.ID]));
					await db.insert(tables.tempStorage).values({
						[T.USER_ID]: f.account[U.ID],
						[T.FILE_ID]: pendingFile[F.ID],
						[T.STORAGE_ID]: f.allocations[0][S.ID],
						[T.PROVIDER_ID]: 1,
						[T.SIZE]: 64
					});
					await db
						.update(tables.storage)
						.set({
							[S.USED_BYTES]: 512,
							[S.PRIORITY]: 42,
							[S.LIMIT_BYTES]: 4096,
							[S.LIMIT_FREE_BYTES]: 2048,
							[S.JSON]: { title: 'Keep my bucket', configured: true }
						})
						.where(eq(tables.storage[S.USER_ID], f.account[U.ID]));
					await db
						.update(tables.storage)
						.set({ [S.USED_BYTES]: 99 })
						.where(eq(tables.storage[S.USER_ID], f.other[U.ID]));
					const credentials = await db
						.select()
						.from(tables.credential)
						.orderBy(tables.credential[C.ID]);
					const providers = await db.select().from(tables.provider).orderBy(tables.provider[P.ID]);
					const connections = await db.select().from(tables.storage).orderBy(tables.storage[S.ID]);
					const configuration = (rows: any[]) =>
						rows.map((row) =>
							Object.fromEntries(
								[
									S.ID,
									S.USER_ID,
									S.CREDENTIAL_ID,
									S.LIMIT_BYTES,
									S.LIMIT_FREE_BYTES,
									S.PRIORITY,
									S.JSON
								].map((key) => [key, row[key]])
							)
						);
					const preserved = async () => {
						assert.equal((await db.select().from(tables.tempStorage)).length, 0);
						assert.deepEqual(
							await db.select().from(tables.credential).orderBy(tables.credential[C.ID]),
							credentials
						);
						assert.deepEqual(
							await db.select().from(tables.provider).orderBy(tables.provider[P.ID]),
							providers
						);
						const current = await db.select().from(tables.storage).orderBy(tables.storage[S.ID]);
						assert.deepEqual(configuration(current), configuration(connections));
						for (const connection of current)
							assert.equal(
								connection[S.USED_BYTES],
								connection[S.USER_ID] === f.account[U.ID] ? 0 : 99
							);
					};
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					await preserved();
					await f.controller.confirm(f.confirmation);
					await preserved();
					now = committed.notBefore + 1;
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 });
					assert.equal((await f.controller.status(f.operationId)).phase, 'ready');
					assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 0);
					await preserved();
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 });
					await preserved();
				}
			);
			await t.test(
				'commit replaces exactly one vault and preserves billing, another user and shared credentials',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					const result = await f.controller.confirm(f.confirmation);
					assert.equal(result.phase, 'cleanup_pending');
					assert.ok(result.notBefore >= now + 24 * 60 * 60_000);
					assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], null);
					assert.equal((await currentUser(f.other[U.ID]))[U.CIPHER], oldCipher);
					assert.equal((await db.select().from(tables.userDevice)).length, 1);
					for (const table of [tables.file, tables.part, tables.item])
						assert.equal((await db.select().from(table)).length, 0);
					const [profile] = await db.select().from(tables.userData);
					assert.equal(profile[D.PRO_ID], 'paid-association');
					assert.equal(profile[D.PLAN_EXPIRES_AT], f.session.expiresAt);
					assert.equal(profile[D.USER_NAME], null);
					assert.equal(profile[D.PROFILE_IMAGE], null);
					const credentials = await db.select().from(tables.credential);
					assert.equal(credentials.length, 2);
					assert.deepEqual(
						new Set(credentials.map((row) => row[C.ID])),
						new Set([f.shared[C.ID], f.owned[C.ID]])
					);
					const manifests = await db.select().from(tables.recoveryCleanupTarget);
					assert.equal(manifests.length, 2);
					assert.ok(manifests.every((target) => target.prefix === 'fixture-user/'));
					assert.ok(manifests.every((target) => !('authorizationToken' in target.credentials)));
					assert.equal((await db.select().from(tables.vaultState))[0].ready, 0);
					assert.deepEqual(await f.controller.confirm(f.confirmation), result);
					assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 2);
					await assert.rejects(
						f.controller.confirm({
							...f.confirmation,
							cipher: Buffer.alloc(48, 9).toString('base64')
						}),
						/reset_conflict/
					);
				}
			);
			await t.test('provider preflight failure leaves all old vault data intact', async () => {
				const f = await seed({
					...cloud,
					async probe() {
						throw new RecoveryFault('storage_access_required');
					}
				});
				await f.controller.prepare(f.preparation);
				await assert.rejects(f.controller.confirm(f.confirmation), /storage_access_required/);
				assert.equal((await f.controller.status(f.operationId)).error, 'storage_access_required');
				assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
				assert.equal((await db.select().from(tables.file)).length, 1);
				assert.equal((await db.select().from(tables.userDevice)).length, 3);
				assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 0);
			});
			await t.test(
				'SQL failure rolls back keys, metadata deletion and cleanup snapshots together',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					await db.$client.unsafe(
						`CREATE FUNCTION reject_fixture_key_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture rollback'; END $$`
					);
					await db.$client.unsafe(
						`CREATE TRIGGER reject_fixture_update BEFORE UPDATE ON "user" FOR EACH ROW EXECUTE FUNCTION reject_fixture_key_update()`
					);
					try {
						await assert.rejects(f.controller.confirm(f.confirmation));
					} finally {
						await db.$client.unsafe('DROP TRIGGER reject_fixture_update ON "user"');
						await db.$client.unsafe('DROP FUNCTION reject_fixture_key_update()');
					}
					assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
					assert.equal((await db.select().from(tables.file)).length, 1);
					assert.equal((await db.select().from(tables.userDevice)).length, 3);
					assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 0);
					assert.equal((await f.controller.status(f.operationId)).phase, 'prepared');
				}
			);
			await t.test(
				'expired, forged, stale-session and cross-account confirmations cannot reset a vault',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					await assert.rejects(
						f.controller.confirm({ ...f.confirmation, challenge: 'b'.repeat(43) }),
						/reset_not_found/
					);
					const other = new core.RecoveryResetService(
						db,
						f.other[U.ID],
						{ ...f.session, userId: 'other-user', email: 'other@example.test' },
						cloud,
						() => now
					);
					await assert.rejects(other.confirm(f.confirmation), /reset_not_found/);
					await assert.rejects(other.status(f.operationId), /reset_not_found/);
					now += 5 * 60_000 + 1;
					await assert.rejects(f.controller.confirm(f.confirmation), /reset_expired/);
					now += 10 * 60_000;
					assert.equal((await f.controller.status(f.operationId)).requiresFreshSignin, true);
					await assert.rejects(
						f.controller.prepare({ ...f.preparation, operationId: crypto.randomUUID() }),
						/sign_in_again/
					);
					assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
				}
			);
			await t.test(
				'concurrent confirmations commit one envelope and one deletion manifest',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					const results = await Promise.all([
						f.controller.confirm(f.confirmation),
						f.controller.confirm(f.confirmation)
					]);
					assert.deepEqual(results[0], results[1]);
					assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 2);
				}
			);
			await t.test(
				'cleanup waits for old capabilities and repeats a final sweep for late uploads',
				async () => {
					const calls: number[] = [];
					const objects = new Set(['old-upload']);
					const f = await seed({
						...cloud,
						async step() {
							calls.push(now);
							objects.clear();
							return { cursor: {}, done: true };
						}
					});
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					await cleanup.drainRecoveryCleanup(
						db,
						{
							...cloud,
							async step() {
								calls.push(now);
								objects.clear();
								return { cursor: {}, done: true };
							}
						},
						{ now: () => now, limit: 4 }
					);
					assert.equal((await f.controller.status(f.operationId)).phase, 'cleanup_pending');
					assert.equal(
						(
							await db
								.select()
								.from(tables.storage)
								.where(eq(tables.storage[S.USER_ID], f.account[U.ID]))
						).length,
						2
					);
					objects.add('late-upload');
					now = committed.notBefore - 1;
					assert.equal(
						await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 }),
						0
					);
					now += 2;
					await cleanup.drainRecoveryCleanup(
						db,
						{
							...cloud,
							async step() {
								calls.push(now);
								objects.clear();
								return { cursor: {}, done: true };
							}
						},
						{ now: () => now, limit: 4 }
					);
					assert.equal(objects.size, 0);
					assert.equal((await f.controller.status(f.operationId)).phase, 'ready');
					assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 0);
					assert.equal(
						(
							await db
								.select()
								.from(tables.storage)
								.where(eq(tables.storage[S.USER_ID], f.account[U.ID]))
						).length,
						2
					);
					assert.equal(calls.filter((time) => time > committed.notBefore).length, 2);
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now });
					assert.equal(
						(
							await db
								.select()
								.from(tables.storage)
								.where(eq(tables.storage[S.USER_ID], f.account[U.ID]))
						).length,
						2
					);
				}
			);
			await t.test(
				'provider outage persists an error and retries without false completion',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					now = committed.notBefore + 1;
					await cleanup.drainRecoveryCleanup(
						db,
						{
							...cloud,
							async step() {
								throw new Error('provider credentials must not be logged');
							}
						},
						{ now: () => now, limit: 2 }
					);
					assert.equal((await f.controller.status(f.operationId)).error, 'storage_cleanup_blocked');
					assert.equal((await db.select().from(tables.vaultState))[0].ready, 0);
					now += 61_000;
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 });
					assert.equal((await f.controller.status(f.operationId)).phase, 'ready');
				}
			);
			await t.test(
				'restart after the last deletion checkpoint finishes default allocation once',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					await db.update(tables.recoveryCleanupTarget).set({ phase: 'done' });
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 0 });
					assert.equal((await f.controller.status(f.operationId)).phase, 'cleanup_pending');
					now = committed.notBefore + 1;
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 0 });
					assert.equal((await f.controller.status(f.operationId)).phase, 'ready');
					assert.equal((await db.select().from(tables.recoveryCleanupTarget)).length, 0);
				}
			);
			await t.test(
				'a delayed old sync cannot recreate metadata or reactivate its device after commit',
				async () => {
					const f = await seed();
					const platform = {
						env: {
							HYPERDRIVE: { connectionString: database.url },
							FIFE_AUTH_CACHE: {
								get: async () => ({
									authorized: true,
									userId: f.account[U.ID],
									remoteAuthId: f.session.userId,
									email: f.session.email
								}),
								put: async () => {}
							}
						}
					};
					const route = await vite.ssrLoadModule('/src/routes/api/sync/+server.ts');
					const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
					closeRouteDatabase = () => dbModule.getDb(platform, true).$client.end();
					let release!: () => void;
					let entered!: () => void;
					const waiting = new Promise<void>((resolve) => {
						release = resolve;
					});
					const bodyRead = new Promise<void>((resolve) => {
						entered = resolve;
					});
					const request = new Request('https://api.example.test/api/sync', {
						method: 'POST',
						headers: {
							authorization: 'Bearer fixture-token',
							service: 'neon',
							device_uuid: 'old-device'
						}
					});
					request.json = async () => {
						entered();
						await waiting;
						return { table_maps: [] };
					};
					const pending = route.POST({ request, platform });
					await bodyRead;
					await f.controller.prepare(f.preparation);
					await f.controller.confirm(f.confirmation);
					release();
					const result = await (await pending).json();
					assert.equal(result.success, 0);
					assert.equal(result.reason, 'device_revoked');
					assert.equal(
						(
							await db
								.select()
								.from(tables.userDevice)
								.where(eq(tables.userDevice[V.USER_ID], f.account[U.ID]))
						).length,
						0
					);
				}
			);
			await t.test(
				'reset vault bootstrap rejects old sessions and permits only current generation data',
				async () => {
					const f = await seed();
					await f.controller.prepare(f.preparation);
					const committed = await f.controller.confirm(f.confirmation);
					now = committed.notBefore + 1;
					await cleanup.drainRecoveryCleanup(db, cloud, { now: () => now, limit: 4 });
					await db.insert(tables.userDevice).values({
						[V.USER_ID]: f.account[U.ID],
						[V.DEVICE_UUID]: 'new-device',
						[V.TITLE]: 'Fresh device'
					});
					const platform = {
						env: {
							HYPERDRIVE: { connectionString: database.url },
							FIFE_AUTH_CACHE: {
								get: async () => ({
									authorized: true,
									userId: f.account[U.ID],
									remoteAuthId: f.session.userId,
									email: f.session.email
								}),
								put: async () => {}
							}
						}
					};
					const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
					closeRouteDatabase = () => dbModule.getDb(platform, true).$client.end();
					async function call(path: string, extra: Record<string, string>, body?: object) {
						const url = new URL(`https://api.example.test/api/${path}`);
						const request = new Request(url, {
							method: body ? 'POST' : 'GET',
							headers: {
								authorization: 'Bearer fixture-token',
								service: 'neon',
								...extra
							},
							...(body ? { body: JSON.stringify(body) } : {})
						});
						const route = await vite.ssrLoadModule(`/src/routes/api/${path}/+server.ts`);
						return (await route[body ? 'POST' : 'GET']({ request, url, platform })).json();
					}
					assert.equal(
						(await call('sync', { device_uuid: 'new-device' })).reason,
						'vault_replaced'
					);
					assert.equal(
						(
							await call('sync', {
								device_uuid: 'new-device',
								'x-fife-vault-protocol': '1',
								'x-fife-vault-generation': 'forged'
							})
						).reason,
						'vault_replaced'
					);
					const headers = {
						device_uuid: 'new-device',
						'x-fife-vault-protocol': '1',
						'x-fife-vault-generation': committed.generation
					};
					assert.equal((await call('sync', headers)).success, 1);
					const connected = await call('storages', headers);
					assert.equal(connected.success, 1);
					const entries = connected.data as Array<{ id: number; added: number; used: number }>;
					// The new device can reuse both connections without adding them again.
					assert.deepEqual(
						entries
							.filter((row) => row.added === 1)
							.map((row) => row.id)
							.sort(),
						[1, 6]
					);
					assert.ok(entries.every((row) => row.used === 0));
					const originalFetch = globalThis.fetch;
					globalThis.fetch = async (input, init) => {
						assert.equal(new URL(String(input)).hostname, 'auth.example.test');
						const old = new Headers(init?.headers).get('Cookie')?.includes('old-session');
						return Response.json({
							session: {
								userId: f.session.userId,
								createdAt: new Date(
									old ? committed.notBefore - 48 * 3600_000 : Date.now() - 60_000
								).toISOString(),
								expiresAt: new Date(Date.now() + 86400_000).toISOString()
							},
							user: {
								id: f.session.userId,
								email: f.session.email,
								emailVerified: true
							}
						});
					};
					try {
						assert.equal(
							(
								await call('keys', {
									'x-fife-vault-protocol': '1',
									'x-fife-session': 'old-session'
								})
							).reason,
							'vault_replaced'
						);
						const keys = await call('keys', {
							'x-fife-vault-protocol': '1',
							'x-fife-recovery-protocol': '2',
							'x-fife-session': 'fixture-session'
						});
						assert.equal(keys.data.cipher, null);
						assert.equal(keys.data.key_state, 'missing');
						assert.equal(keys.data.vault_generation, committed.generation);
					} finally {
						globalThis.fetch = originalFetch;
					}
				}
			);
			await t.test('rollout eligibility and healthy cleanup worker are both required', async () => {
				await seed();
				const { recoveryAvailable } = await vite.ssrLoadModule(
					'/src/lib/server/recoveryAvailability.ts'
				);
				const flags = {
					RECOVERY_RESET_ENABLED: 'true',
					RECOVERY_WORKER_READY: 'true',
					RECOVERY_RESET_EMAILS: ' Fixture@example.test '
				};
				const clock = Date.now();
				await db.delete(tables.recoveryWorkerState);
				assert.equal(await recoveryAvailable(db, flags, 'fixture@example.test', clock), false);
				await db.insert(tables.recoveryWorkerState).values({ id: 'cleanup', lastRunAt: clock });
				assert.equal(await recoveryAvailable(db, flags, 'fixture@example.test', clock), true);
				assert.equal(await recoveryAvailable(db, flags, 'other@example.test', clock), false);
				assert.equal(await recoveryAvailable(db, flags, undefined, clock), false);
				assert.equal(
					await recoveryAvailable(
						db,
						{ ...flags, RECOVERY_RESET_EMAILS: '' },
						'fixture@example.test',
						clock
					),
					false
				);
				assert.equal(
					await recoveryAvailable(
						db,
						{ ...flags, RECOVERY_RESET_ENABLED: 'false' },
						'fixture@example.test',
						clock
					),
					false
				);
				assert.equal(
					await recoveryAvailable(
						db,
						{ ...flags, RECOVERY_WORKER_READY: 'false' },
						'fixture@example.test',
						clock
					),
					false
				);
				assert.equal(
					await recoveryAvailable(db, flags, 'fixture@example.test', clock + 15 * 60_000),
					false
				);
				assert.equal(await recoveryAvailable(db, flags, 'fixture@example.test', clock - 1), false);
				assert.equal(
					await recoveryAvailable(
						db,
						{ ...flags, RECOVERY_RESET_EMAILS: '*' },
						'other@example.test',
						clock
					),
					true
				);
				await db.delete(tables.recoveryWorkerState);
			});

			await t.test(
				'HTTP reset requires protocol, live Neon proof and a healthy worker before preparation',
				async () => {
					const f = await seed();
					const platform = {
						env: {
							HYPERDRIVE: { connectionString: database.url },
							FIFE_AUTH_CACHE: {
								get: async () => ({
									authorized: true,
									userId: f.account[U.ID],
									remoteAuthId: f.session.userId,
									email: f.session.email
								}),
								put: async () => {}
							}
						}
					};
					const dbModule = await vite.ssrLoadModule('/src/lib/server/db/index.ts');
					closeRouteDatabase = () => dbModule.getDb(platform, true).$client.end();
					const route = await vite.ssrLoadModule(
						'/src/routes/api/recovery-reset/prepare/+server.ts'
					);
					const statusRoute = await vite.ssrLoadModule(
						'/src/routes/api/recovery-reset/status/+server.ts'
					);
					const originalFetch = globalThis.fetch;
					let calls = 0;
					globalThis.fetch = async (input) => {
						calls++;
						assert.equal(new URL(String(input)).hostname, 'auth.example.test');
						return Response.json({
							session: {
								userId: f.session.userId,
								createdAt: new Date(Date.now() - 60_000).toISOString(),
								expiresAt: new Date(Date.now() + 86400_000).toISOString()
							},
							user: {
								id: f.session.userId,
								email: f.session.email,
								emailVerified: true
							}
						});
					};
					async function prepare(headers: Record<string, string>, body: unknown = f.preparation) {
						const request = new Request('https://api.example.test/api/recovery-reset/prepare', {
							method: 'POST',
							headers: { authorization: 'Bearer fixture-token', service: 'neon', ...headers },
							body: JSON.stringify(body)
						});
						return (await route.POST({ request, platform })).json();
					}
					try {
						assert.equal((await prepare({})).message, 'client_update_required');
						assert.equal(calls, 0);
						assert.equal(
							(await prepare({ 'x-fife-vault-protocol': '1' })).message,
							'sign_in_again'
						);
						assert.equal(calls, 0);
						const proof = {
							'x-fife-vault-protocol': '1',
							'x-fife-recovery-protocol': '2',
							'x-fife-session': 'fixture-session'
						};
						const statusRequest = new Request(
							`https://api.example.test/api/recovery-reset/status?operation_id=${f.operationId}`,
							{ headers: { authorization: 'Bearer fixture-token', service: 'neon', ...proof } }
						);
						const missing = await statusRoute.GET({ request: statusRequest, platform });
						assert.equal(missing.status, 200);
						assert.equal(missing.headers.get('cache-control'), 'no-store');
						assert.deepEqual(await missing.json(), { success: 0, message: 'reset_not_found' });
						assert.equal((await db.select().from(tables.recoveryReset)).length, 0);
						assert.equal((await prepare(proof)).message, 'recovery_unavailable');
						assert.equal((await db.select().from(tables.recoveryReset)).length, 0);
						await db
							.insert(tables.recoveryWorkerState)
							.values({ id: 'cleanup', lastRunAt: Date.now() })
							.onConflictDoUpdate({
								target: tables.recoveryWorkerState.id,
								set: { lastRunAt: Date.now() }
							});
						assert.equal((await prepare(proof, [])).message, 'invalid_reset_request');
						assert.equal((await prepare(proof)).data.phase, 'prepared');
						assert.equal((await currentUser(f.account[U.ID]))[U.CIPHER], oldCipher);
					} finally {
						globalThis.fetch = originalFetch;
					}
				}
			);
		} finally {
			await closeRouteDatabase?.();
			await vite.close();
			await database.close();
		}
	}
);
