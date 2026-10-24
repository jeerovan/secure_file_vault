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
	TempStorageKeys as T,
	PartKeys as A,
	FileKeys as F
} from '../src/lib/server/db/keys';
import type { ManagedUploadStorage, UploadRecord } from '../src/lib/server/managedUploadStorage';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';

const deferred = () => {
	let resolve!: () => void;
	const promise = new Promise<void>((r) => {
		resolve = r;
	});
	return { promise, resolve };
};
test(
	'managed uploads retain ownership and cleanup across interruption',
	{ skip: !recoveryTestUrl },
	async (t) => {
		const database = await createRecoveryDatabase();
		Object.assign(process.env, {
			DATABASE_URL: database.url,
			SUPABASE_URL: 'https://auth.example.test',
			SUPABASE_KEY: 'fixture',
			NEON_JWKS: 'https://auth.example.test/jwks',
			REVENUECAT_SECRET_KEY: 'fixture',
			REVENUECAT_WEBHOOK_SECRET: 'fixture',
			FCM_KEY: 'fixture'
		});
		const vite = await createServer({
			root: process.cwd(),
			logLevel: 'silent',
			server: { middlewareMode: true, watch: { ignored: ['**/*'] } }
		});
		const core = await vite.ssrLoadModule('/src/lib/server/managedUpload.ts');
		const { UploadFault } = await vite.ssrLoadModule('/src/lib/server/managedUploadStorage.ts');
		const { db } = database;
		let now = 1_000_000,
			starts = 0,
			completes = 0,
			deletes = 0,
			ready = true,
			published = false,
			deleted = true;
		let beforeInitiate: ((row: UploadRecord) => Promise<void>) | undefined;
		let beforeComplete: (() => Promise<void>) | undefined;
		let beforeVerify: (() => Promise<void>) | undefined;
		let failDelete = false,
			loseComplete = false;
		const cloud: ManagedUploadStorage = {
			async initiate(row) {
				starts++;
				assert.equal(
					(await db.select().from(tables.vaultUpload).where(eq(tables.vaultUpload.id, row.id)))
						.length,
					1,
					'cloud initiation must follow a committed durable record'
				);
				await beforeInitiate?.(row);
				return 'provider-upload';
			},
			async sign() {
				return {
					uploadUrl: 'https://objects.example.test/part?uploadId=provider-upload',
					headers: { 'Content-MD5': 'AAAAAAAAAAAAAAAAAAAAAA==' }
				};
			},
			async finalize(_row, commit) {
				await beforeVerify?.();
				if (!ready) throw new UploadFault('upload_not_ready', true);
				if (commit && !(await commit())) throw new UploadFault('upload_retired', true);
				completes++;
				await beforeComplete?.();
				published = true;
				if (loseComplete) {
					loseComplete = false;
					throw new UploadFault('upload_outcome_unknown');
				}
				return { versionId: 'exact-version' };
			},
			async cleanup() {
				deletes++;
				if (failDelete) throw new UploadFault('upload_cleanup_blocked');
				if (deleted) published = false;
				return { done: deleted, cursor: {} };
			}
		};
		async function seed() {
			await db.delete(tables.user);
			await db.delete(tables.provider);
			now = 1_000_000;
			starts = completes = deletes = 0;
			ready = deleted = true;
			published = false;
			beforeInitiate = beforeComplete = beforeVerify = undefined;
			failDelete = loseComplete = false;
			await db
				.insert(tables.provider)
				.values({ [P.ID]: 6, [P.TITLE]: 'S3', [P.FREE_BYTES]: 1000, [P.PRIORITY]: 1 });
			const [account] = await db
				.insert(tables.user)
				.values({
					[U.REMOTE_AUTH_ID]: 'managed-fixture',
					[U.EMAIL]: 'fixture@example.test',
					[U.CIPHER]: 'cipher',
					[U.NONCE]: 'nonce'
				})
				.returning();
			await db.insert(tables.userDevice).values({
				[V.USER_ID]: account[U.ID],
				[V.DEVICE_UUID]: 'device',
				[V.TITLE]: 'Fixture',
				[V.ACTIVE]: 1
			});
			const [credential] = await db
				.insert(tables.credential)
				.values({
					[C.USER_ID]: account[U.ID],
					[C.PROVIDER_ID]: 6,
					[C.CREDENTIALS]: {
						appId: 'fixture',
						appKey: 'private-fixture',
						bucketName: 'fixture',
						endpoint: 'https://objects.example.test',
						region: 'us-east-1',
						forcePathStyle: true
					}
				})
				.returning();
			const [storage] = await db
				.insert(tables.storage)
				.values({
					[S.USER_ID]: account[U.ID],
					[S.CREDENTIAL_ID]: credential[C.ID],
					[S.LIMIT_BYTES]: 1000,
					[S.LIMIT_FREE_BYTES]: 1000,
					[S.JSON]: {}
				})
				.returning();
			await db.insert(tables.file).values({
				[F.USER_ID]: account[U.ID],
				[F.DEVICE_UUID]: 'device',
				[F.FILE_HASH]: 'a'.repeat(43),
				[F.STORAGE_ID]: storage[S.ID],
				[F.PROVIDER_ID]: 6
			});
			const auth = { authorized: true, userId: account[U.ID], deviceUuid: 'device' };
			const input = {
				id: crypto.randomUUID(),
				receipt: 'r'.repeat(43),
				storage_id: storage[S.ID],
				file_id: `${'a'.repeat(43)}_1`,
				content_length: 100,
				content_sha1: 'a'.repeat(40),
				content_md5: 'AAAAAAAAAAAAAAAAAAAAAA==',
				part_metadata: { cipher: 'durable-key', nonce: 'durable-nonce' }
			};
			const service = () => new core.ManagedUploadService(db, cloud, () => now);
			const row = async () => (await db.select().from(tables.vaultUpload))[0];
			return { auth, input, service, row, account };
		}
		try {
			await t.test(
				'HTTP activation controls new preparation while preserving completion and reporting',
				async () => {
					const f = await seed();
					const bindings = (await vite.ssrLoadModule('$env/dynamic/private')).env;
					const originalFlag = bindings.MANAGED_UPLOADS_ENABLED;
					const storageModule = await vite.ssrLoadModule('/src/lib/server/managedUploadStorage.ts');
					const prototype = storageModule.ProviderManagedUploadStorage.prototype;
					const originalMethods = Object.fromEntries(
						Object.keys(cloud).map((key) => [key, prototype[key]])
					);
					Object.assign(prototype, cloud);
					try {
						const handler = await vite.ssrLoadModule('/src/lib/server/managedUploadHttp.ts');
						const protocol = await vite.ssrLoadModule(
							'/src/routes/api/uploads/protocol/+server.ts'
						);
						const platform = {
							env: {
								HYPERDRIVE: { connectionString: database.url },
								FIFE_AUTH_CACHE: {
									get: async () => ({
										authorized: true,
										userId: f.account[U.ID],
										remoteAuthId: f.account[U.REMOTE_AUTH_ID],
										email: f.account[U.EMAIL]
									}),
									put: async () => {}
								}
							}
						};
						const call = async (action: string, body: unknown) => {
							const response = await handler.managedUploadRequest(
								new Request(`https://fixture.test/api/uploads/${action}`, {
									method: 'POST',
									headers: {
										service: 'neon',
										authorization: 'Bearer fixture',
										device_uuid: 'device',
										'content-type': 'application/json'
									},
									body: JSON.stringify(body)
								}),
								platform,
								action
							);
							return { status: response.status, body: await response.json() };
						};
						bindings.MANAGED_UPLOADS_ENABLED = 'false';
						assert.equal(protocol.POST().status, 404);
						assert.deepEqual(await call('prepare', f.input), {
							status: 503,
							body: { success: 0, message: 'managed_uploads_disabled' }
						});
						assert.equal(starts, 0);
						assert.deepEqual(await db.select().from(tables.vaultUpload), []);
						bindings.MANAGED_UPLOADS_ENABLED = 'true';
						assert.equal(protocol.POST().status, 200);
						assert.equal((await call('prepare', f.input)).body.data.state, 'upload');
						bindings.MANAGED_UPLOADS_ENABLED = 'false';
						assert.equal(protocol.POST().status, 404);
						assert.equal((await call('prepare', f.input)).body.data.state, 'upload');
						assert.equal(
							(await call('prepare', { ...f.input, id: crypto.randomUUID() })).status,
							503
						);
						const complete = await call('complete', { id: f.input.id, receipt: f.input.receipt });
						assert.equal(complete.status, 200);
						assert.equal(complete.body.data.state, 'complete');
						const report = await call('report', { id: f.input.id, receipt: f.input.receipt });
						assert.equal(report.status, 200);
						assert.equal(report.body.data.state, 'committed');
						assert.equal(starts, 1);
						assert.equal(completes, 1);
					} finally {
						bindings.MANAGED_UPLOADS_ENABLED = originalFlag;
						Object.assign(prototype, originalMethods);
					}
				}
			);
			await t.test(
				'activation pause prevents new records without abandoning accepted uploads',
				async () => {
					const f = await seed();
					await assert.rejects(
						f.service().prepare(f.auth, f.input, { allowNew: false }),
						/managed_uploads_disabled/
					);
					assert.equal(starts, 0);
					assert.deepEqual(await db.select().from(tables.vaultUpload), []);
					assert.deepEqual(await db.select().from(tables.part), []);
					assert.equal((await f.service().prepare(f.auth, f.input)).state, 'upload');
					assert.equal(
						(await f.service().prepare(f.auth, f.input, { allowNew: false })).state,
						'upload'
					);
					assert.equal(
						starts,
						1,
						'resuming an accepted operation must not initiate another upload'
					);
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'complete'
					);
					assert.equal(completes, 1);
					assert.equal(
						(await f.service().prepare(f.auth, f.input, { allowNew: false })).state,
						'complete'
					);
				}
			);
			await t.test(
				'activation pause leaves receipt cleanup and its durable queue operational',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					assert.equal(
						(await f.service().report(f.input.id, f.input.receipt)).state,
						'cleanup_pending'
					);
					assert.equal(
						(await f.service().prepare(f.auth, f.input, { allowNew: false })).state,
						'cleanup_pending'
					);
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal(deletes, 1);
					assert.equal((await f.service().report(f.input.id, f.input.receipt)).state, 'deleted');
				}
			);
			await t.test('missing encryption metadata never allocates a provider upload', async () => {
				const f = await seed();
				for (const part_metadata of [
					undefined,
					{},
					{ cipher: '', nonce: 'nonce' },
					{ cipher: 'key', nonce: '' }
				]) {
					await assert.rejects(
						f.service().prepare(f.auth, { ...f.input, part_metadata }),
						/invalid_upload_request/
					);
				}
				assert.equal(starts, 0);
				assert.equal((await db.select().from(tables.vaultUpload)).length, 0);
			});
			await t.test(
				'removing staged part metadata prevents publication and retains cleanup',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await db.delete(tables.part);
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'cleanup_pending'
					);
					assert.equal(completes, 0);
					assert.equal((await f.row()).retired, 1);
				}
			);
			await t.test(
				'completion preserves recovery metadata without a later client sync',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const [staged] = await db.select().from(tables.part);
					assert.equal(staged[A.UPLOADED], 0);
					assert.equal(staged[A.CIPHER], 'durable-key');
					const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
					await api.savePartChanges(
						db,
						f.account[U.ID],
						'device',
						[
							{
								id: f.input.file_id,
								updated_at: now + 100,
								uploaded: 0,
								deleted: 0,
								size: 100,
								cipher: 'conflicting-key',
								nonce: 'other',
								data: JSON.stringify({ sha1: 'other' })
							}
						],
						true
					);
					await f.service().complete(f.auth, f.input.id, f.input.receipt);
					const [accepted] = await db.select().from(tables.part);
					assert.equal(accepted?.[A.UPLOADED], 1);
					assert.equal(accepted[A.CIPHER], 'durable-key');
					assert.equal(accepted[A.NONCE], 'durable-nonce');
					assert.equal((accepted[A.JSON] as { fileId: string }).fileId, 'exact-version');
					await api.savePartChanges(
						db,
						f.account[U.ID],
						'device',
						[
							{
								id: f.input.file_id,
								updated_at: now + 100,
								uploaded: 0,
								deleted: 0,
								size: 100,
								cipher: 'conflicting-key',
								nonce: 'other',
								data: JSON.stringify({ sha1: 'other' })
							}
						],
						true
					);
					const recovered = await f
						.service()
						.prepare(f.auth, { ...f.input, id: crypto.randomUUID(), receipt: 's'.repeat(43) });
					assert.equal(recovered.state, 'existing');
					assert.equal(recovered.part[A.CIPHER], 'durable-key');
					assert.equal(starts, 1);
					assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 100);
				}
			);
			await t.test(
				'cleanup receipts protect committed files even after device removal',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await f.service().complete(f.auth, f.input.id, f.input.receipt);
					await db.delete(tables.userDevice);
					const receipt = await f.service().report(f.input.id, f.input.receipt);
					assert.deepEqual(receipt, { protocol: 'managed-v1', id: f.input.id, state: 'committed' });
					now += 48 * 60 * 60_000;
					assert.equal(await core.drainManagedUploads(db, cloud, { now: () => now }), 0);
					const [accepted] = await db.select().from(tables.part);
					assert.equal(accepted[A.UPLOADED], 1);
					assert.equal(accepted[A.CIPHER], 'durable-key');
					assert.equal(published, true);
					assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 100);
				}
			);
			await t.test(
				'retirement during verification prevents a provider completion intent',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const entered = deferred(),
						release = deferred();
					beforeVerify = async () => {
						entered.resolve();
						await release.promise;
					};
					const completing = f.service().complete(f.auth, f.input.id, f.input.receipt);
					await entered.promise;
					assert.equal((await f.row()).phase, 'verifying');
					assert.equal((await f.row()).uncertain, null);
					await f.service().report(f.input.id, f.input.receipt);
					release.resolve();
					assert.equal((await completing).state, 'cleanup_pending');
					assert.equal(completes, 0);
					assert.equal(published, false);
					assert.equal((await f.row()).uncertain, null);
				}
			);
			await t.test(
				'reset retains a removed provider snapshot while its upload is unresolved',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await db.delete(tables.storage);
					await db.delete(tables.credential);
					const resetModule = await vite.ssrLoadModule('/src/lib/server/recoveryReset.ts');
					const targets = await resetModule.recoveryTargets(
						db,
						f.account[U.ID],
						'managed-fixture/'
					);
					assert.equal(targets.length, 1);
					assert.equal(targets[0].providerId, 6);
					assert.equal(targets[0].credentials.appKey, 'private-fixture');
					assert.deepEqual(
						await resetModule.recoveryTargets(db, f.account[U.ID], 'managed-fixture/vaults/other/'),
						[]
					);
				}
			);
			await t.test(
				'a managed metadata retry cannot replace an already uploaded part key',
				async () => {
					const f = await seed();
					const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
					const accepted = {
						id: f.input.file_id,
						updated_at: now,
						data: JSON.stringify({ sha1: f.input.content_sha1 }),
						uploaded: 1,
						deleted: 0,
						size: 100,
						cipher: 'accepted-key',
						nonce: 'accepted-nonce'
					};
					await api.savePartChanges(db, f.account[U.ID], 'device', [accepted], true);
					await api.savePartChanges(
						db,
						f.account[U.ID],
						'device',
						[{ ...accepted, uploaded: 0, cipher: 'conflicting-local-key', updated_at: now + 1 }],
						true
					);
					const [part] = await db.select().from(tables.part);
					assert.equal(part[A.CIPHER], 'accepted-key');
					assert.equal(part[A.UPLOADED], 1);
					const result = await f.service().prepare(f.auth, f.input);
					assert.equal(result.state, 'existing');
					assert.equal(result.part[A.CIPHER], 'accepted-key');
					assert.equal(starts, 0);
					assert.deepEqual(await db.select().from(tables.vaultUpload), []);
				}
			);
			await t.test(
				'completion adopts another accepted part and retires its unused upload',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
					await api.savePartChanges(db, f.account[U.ID], 'other-device', [
						{
							id: f.input.file_id,
							updated_at: now + 10,
							uploaded: 1,
							deleted: 0,
							size: 100,
							cipher: 'accepted-key',
							nonce: 'accepted-nonce',
							data: JSON.stringify({ sha1: 'other-ciphertext' })
						}
					]);
					const result = await f.service().complete(f.auth, f.input.id, f.input.receipt);
					assert.equal(result.state, 'existing');
					assert.equal(result.cleanupRequired, true);
					assert.equal(completes, 0);
					assert.equal(result.part[A.CIPHER], 'accepted-key');
					assert.equal((await f.row()).retired, 1);
				}
			);
			for (const retry of ['prepare', 'complete']) {
				await t.test(`a late legacy completion is adopted on ${retry} retry`, async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await f.service().complete(f.auth, f.input.id, f.input.receipt);
					const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
					await api.savePartChanges(db, f.account[U.ID], 'other-device', [
						{
							id: f.input.file_id,
							updated_at: now + 100,
							uploaded: 1,
							deleted: 0,
							size: 100,
							cipher: 'legacy-key',
							nonce: 'legacy-nonce',
							data: JSON.stringify({ sha1: 'legacy-ciphertext' })
						}
					]);
					const result =
						retry === 'prepare'
							? await f.service().prepare(f.auth, f.input)
							: await f.service().complete(f.auth, f.input.id, f.input.receipt);
					assert.equal(result.state, 'existing');
					assert.equal(result.cleanupRequired, true);
					assert.equal(result.part[A.CIPHER], 'legacy-key');
					await f.service().report(f.input.id, f.input.receipt);
					const [part] = await db.select().from(tables.part);
					assert.equal(part[A.CIPHER], 'legacy-key');
					assert.equal(part[A.UPLOADED], 1);
					assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 100);
				});
			}
			for (const interval of ['verification', 'provider I/O']) {
				await t.test(
					`legacy completion during managed ${interval} preserves its accepted keys`,
					async () => {
						const f = await seed();
						await f.service().prepare(f.auth, f.input);
						const physicalKey = (await f.row()).objectKey;
						assert.equal(physicalKey, `managed-fixture/${f.input.file_id}~${f.input.id}`);
						const entered = deferred(),
							release = deferred();
						const pause = async () => {
							entered.resolve();
							await release.promise;
						};
						if (interval === 'verification') beforeVerify = pause;
						else beforeComplete = pause;
						const completing = f.service().complete(f.auth, f.input.id, f.input.receipt);
						await entered.promise;
						const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
						await api.savePartChanges(db, f.account[U.ID], 'old-device', [
							{
								id: f.input.file_id,
								updated_at: now + 100,
								uploaded: 1,
								deleted: 0,
								size: 100,
								cipher: 'legacy-key',
								nonce: 'legacy-nonce',
								data: { sha1: 'legacy-sha1' }
							}
						]);
						release.resolve();
						assert.equal((await completing).state, 'cleanup_pending');
						const accepted = await f.service().complete(f.auth, f.input.id, f.input.receipt);
						assert.equal(accepted.state, 'existing');
						assert.equal(accepted.part[A.CIPHER], 'legacy-key');
						await f.service().report(f.input.id, f.input.receipt);
						now++;
						await core.drainManagedUploads(db, cloud, { now: () => now });
						assert.equal((await f.row()).phase, 'deleted');
						const [part] = await db.select().from(tables.part);
						assert.equal(part[A.CIPHER], 'legacy-key');
						assert.equal(part[A.UPLOADED], 1);
						assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 100);
					}
				);
			}
			await t.test(
				'a legacy replacement releases only the superseded object and accounts for its actual size',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await f.service().complete(f.auth, f.input.id, f.input.receipt);
					const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
					await api.savePartChanges(
						db,
						f.account[U.ID],
						'old-device',
						[
							{
								id: f.input.file_id,
								updated_at: now + 100,
								uploaded: 1,
								deleted: 0,
								size: 145,
								cipher: 'legacy-key',
								nonce: 'legacy-nonce',
								data: { sha1: 'legacy-sha1', legacyUpload: true }
							}
						],
						true
					);
					now = Date.now() + 1;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'deleted');
					assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 145);
					assert.equal((await db.select().from(tables.part))[0][A.CIPHER], 'legacy-key');
				}
			);
			await t.test(
				'file deletion retires uploads before storage or part-count metadata is synchronized',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const [entry] = await db
						.update(tables.file)
						.set({ [F.STORAGE_ID]: null, [F.PARTS]: 0 })
						.returning();
					const worker = await vite.ssrLoadModule('/src/lib/server/deleteWorker.ts');
					await worker.deleteFileFromStorage(db, entry);
					assert.equal((await f.row()).retired, 1);
					now = Date.now() + 1;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'deleted');
					assert.equal(completes, 0);
				}
			);
			await t.test('stale managed metadata cannot resurrect a deleted cloud object', async () => {
				const f = await seed();
				await f.service().prepare(f.auth, f.input);
				await f.service().complete(f.auth, f.input.id, f.input.receipt);
				const [accepted] = await db.select().from(tables.part);
				await db.update(tables.file).set({ [F.DELETED]: 1 });
				now += 24 * 60 * 60_000 + 1;
				await core.drainManagedUploads(db, cloud, { now: () => now });
				await db.update(tables.file).set({ [F.DELETED]: 0 });
				const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
				for (const managed of [false, true])
					await api.savePartChanges(
						db,
						f.account[U.ID],
						'device',
						[
							{
								id: f.input.file_id,
								updated_at: now + 100,
								uploaded: 1,
								deleted: 0,
								size: 100,
								cipher: accepted[A.CIPHER],
								nonce: accepted[A.NONCE],
								data: accepted[A.JSON]
							}
						],
						managed
					);
				const [part] = await db.select().from(tables.part);
				assert.equal(part[A.UPLOADED], 0);
				assert.equal(part[A.CIPHER], null);
				assert.equal(published, false);
				assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 0);
			});
			await t.test(
				'a server allocation reservation permits upload before the next metadata sync',
				async () => {
					const f = await seed();
					const [entry] = await db
						.update(tables.file)
						.set({ [F.STORAGE_ID]: null, [F.PROVIDER_ID]: null })
						.returning();
					await db.insert(tables.tempStorage).values({
						[T.USER_ID]: f.account[U.ID],
						[T.FILE_ID]: entry[F.ID],
						[T.STORAGE_ID]: f.input.storage_id,
						[T.PROVIDER_ID]: 6,
						[T.SIZE]: 100
					});
					assert.equal((await f.service().prepare(f.auth, f.input)).state, 'upload');
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'complete'
					);
				}
			);
			await t.test(
				'initiation is durable, retry reuses its ID, and provider secrets never enter responses',
				async () => {
					const f = await seed();
					const first = await f.service().prepare(f.auth, f.input);
					assert.equal(first.state, 'upload');
					assert.equal(first.protocol, 'managed-v1');
					assert.equal((await f.service().prepare(f.auth, f.input)).uploadUrl, first.uploadUrl);
					assert.equal(starts, 1);
					assert.equal((await f.row()).uploadId, 'provider-upload');
					assert.ok(!JSON.stringify(first).includes('private-fixture'));
					assert.deepEqual(await db.select().from(tables.vaultState), []);
				}
			);
			await t.test(
				'completion is acknowledged only after server finalization and is idempotent',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const result = await f.service().complete(f.auth, f.input.id, f.input.receipt);
					assert.equal(result.state, 'complete');
					assert.equal(result.fileId, 'exact-version');
					assert.equal(published, true);
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'complete'
					);
					assert.equal(completes, 1);
				}
			);
			await t.test('incomplete body can retry without changing upload identity', async () => {
				const f = await seed();
				await f.service().prepare(f.auth, f.input);
				ready = false;
				await assert.rejects(
					f.service().complete(f.auth, f.input.id, f.input.receipt),
					/upload_not_ready/
				);
				assert.equal((await f.row()).phase, 'uploading');
				assert.equal(published, false);
				ready = true;
				assert.equal(
					(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
					'complete'
				);
				assert.equal(starts, 1);
			});
			await t.test(
				'lost completion remains recoverable after server restart without another upload',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					loseComplete = true;
					await assert.rejects(
						f.service().complete(f.auth, f.input.id, f.input.receipt),
						/upload_outcome_unknown/
					);
					assert.equal(published, true);
					assert.equal((await f.row()).uncertain, 'complete');
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'complete'
					);
					assert.equal(starts, 1);
				}
			);
			await t.test(
				'forged receipts, metadata changes and another device cannot finalize or replace a record',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await assert.rejects(
						f.service().complete(f.auth, f.input.id, 'x'.repeat(43)),
						/upload_not_found/
					);
					await assert.rejects(
						f.service().prepare(f.auth, { ...f.input, content_length: 99 }),
						/upload_conflict/
					);
					await db.insert(tables.userDevice).values({
						[V.USER_ID]: f.account[U.ID],
						[V.DEVICE_UUID]: 'other',
						[V.TITLE]: 'Other',
						[V.ACTIVE]: 1
					});
					await assert.rejects(
						f.service().complete({ ...f.auth, deviceUuid: 'other' }, f.input.id, f.input.receipt),
						/upload_not_found/
					);
					await assert.rejects(f.service().report(f.input.id, 'x'.repeat(43)), /upload_not_found/);
					assert.equal((await f.row()).retired, 0);
					assert.equal(completes, 0);
				}
			);
			await t.test(
				'missing file metadata schedules durable deletion instead of publishing',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await db.delete(tables.file);
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'cleanup_pending'
					);
					assert.equal(completes, 0);
					assert.equal((await f.row()).retired, 1);
					now++;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'deleted');
				}
			);
			await t.test(
				'cleanup receipt survives device deletion and retries until verified, even with no client',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await db.delete(tables.userDevice);
					assert.equal(
						(await f.service().report(f.input.id, f.input.receipt)).state,
						'cleanup_pending'
					);
					failDelete = true;
					now++;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'cleanup');
					assert.ok((await f.row()).credentials.appKey);
					failDelete = false;
					deleted = false;
					now += 60_001;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'cleanup');
					deleted = true;
					now += 60_001;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.service().report(f.input.id, f.input.receipt)).state, 'deleted');
					assert.deepEqual((await f.row()).credentials, {});
					assert.equal((await f.row()).objectKey, '');
					assert.equal((await f.row()).contentLength, 0);
				}
			);
			await t.test(
				'concurrent completion executes once and retirement wins during provider I/O',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const entered = deferred(),
						release = deferred();
					beforeComplete = async () => {
						entered.resolve();
						await release.promise;
					};
					const completing = f.service().complete(f.auth, f.input.id, f.input.receipt);
					await entered.promise;
					assert.equal(
						(await f.service().complete(f.auth, f.input.id, f.input.receipt)).state,
						'pending'
					);
					await f.service().report(f.input.id, f.input.receipt);
					assert.equal(
						await core.drainManagedUploads(db, cloud, { now: () => now }),
						0,
						'active finalization must retain its lease'
					);
					release.resolve();
					assert.equal((await completing).state, 'cleanup_pending');
					assert.equal(completes, 1);
					now++;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal(published, false);
				}
			);
			await t.test(
				'initiation completing after retirement remains tracked and cannot expose an upload URL',
				async () => {
					const f = await seed();
					const entered = deferred(),
						release = deferred();
					beforeInitiate = async () => {
						entered.resolve();
						await release.promise;
					};
					const preparing = f.service().prepare(f.auth, f.input);
					await entered.promise;
					await f.service().report(f.input.id, f.input.receipt);
					release.resolve();
					const result = await preparing;
					assert.equal(result.state, 'cleanup_pending');
					assert.equal(result.uploadUrl, undefined);
					assert.equal((await f.row()).uploadId, 'provider-upload');
				}
			);
			await t.test(
				'idle abandoned uploads are collected independently of reset and device lifetime',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await db.delete(tables.userDevice);
					now += 24 * 60 * 60_000 + 1;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'deleted');
					assert.equal(deletes, 1);
				}
			);
			await t.test(
				'malformed input and a conflicting object never initiate a cloud upload',
				async () => {
					const f = await seed();
					for (const patch of [
						{ file_id: '../key_1' },
						{ content_length: -1 },
						{ content_length: 101 * 1024 * 1024 + 1 },
						{ receipt: '' },
						{ storage_id: 0 },
						{ id: 'bad' }
					])
						await assert.rejects(
							f.service().prepare(f.auth, { ...f.input, ...patch }),
							/invalid_upload_request/
						);
					assert.equal(starts, 0);
					assert.deepEqual(await db.select().from(tables.vaultUpload), []);
					await f.service().prepare(f.auth, f.input);
					await assert.rejects(
						f.service().prepare(f.auth, { ...f.input, id: crypto.randomUUID() }),
						/upload_object_busy/
					);
					assert.equal(starts, 1);
				}
			);
			await t.test(
				'accepted metadata retains its manifest until its file is deleted and usage releases once',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					await f.service().complete(f.auth, f.input.id, f.input.receipt);
					const [accepted] = await db.select().from(tables.part);
					const api = await vite.ssrLoadModule('/src/lib/server/db/api.ts');
					await api.savePartChanges(db, f.account[U.ID], 'device', [
						{
							id: f.input.file_id,
							updated_at: now,
							data: JSON.stringify(accepted[A.JSON]),
							uploaded: 1,
							deleted: 0,
							size: f.input.content_length,
							cipher: f.input.part_metadata.cipher,
							nonce: f.input.part_metadata.nonce
						}
					]);
					assert.equal((await f.row()).phase, 'stored');
					assert.equal((await db.select().from(tables.part)).length, 1);
					assert.equal(published, true, 'metadata acknowledgement must not delete the object');
					await db.update(tables.file).set({ [F.DELETED]: 1 });
					now += 24 * 60 * 60_000 + 1;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal((await f.row()).phase, 'deleted');
					assert.equal(published, false);
					assert.equal((await db.select().from(tables.storage))[0][S.USED_BYTES], 0);
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal(deletes, 1);
					assert.equal((await f.service().report(f.input.id, f.input.receipt)).state, 'deleted');
				}
			);
			await t.test(
				'device removal while finalizing retains a cleanup job instead of an active completion',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const entered = deferred(),
						release = deferred();
					beforeComplete = async () => {
						entered.resolve();
						await release.promise;
					};
					const completing = f.service().complete(f.auth, f.input.id, f.input.receipt);
					await entered.promise;
					await db.delete(tables.userDevice);
					release.resolve();
					assert.equal((await completing).state, 'cleanup_pending');
					assert.equal((await f.row()).retired, 1);
					now++;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal(published, false);
					assert.equal((await f.row()).phase, 'deleted');
				}
			);
			await t.test(
				'a real reset races provider finalization without losing its upload record',
				async () => {
					const f = await seed();
					await f.service().prepare(f.auth, f.input);
					const resetModule = await vite.ssrLoadModule('/src/lib/server/recoveryReset.ts');
					const recoverySession = await vite.ssrLoadModule('/src/lib/server/recoverySession.ts');
					const prefixCleanup = await vite.ssrLoadModule('/src/lib/server/recoveryCleanup.ts');
					const session = {
						userId: 'managed-fixture',
						email: 'fixture@example.test',
						createdAt: now - 1,
						expiresAt: now + 86_400_000,
						hash: 'fixture-session'
					};
					let sweeps = 0;
					const reset = new resetModule.RecoveryResetService(
						db,
						f.account[U.ID],
						session,
						{
							probe: async () => {},
							step: async () => {
								sweeps++;
								return { cursor: {}, done: true };
							}
						},
						() => now
					);
					const operationId = crypto.randomUUID(),
						challenge = Buffer.alloc(32, 4).toString('base64url');
					await reset.prepare({
						operationId,
						expectedGeneration: 'legacy',
						challengeHash: await recoverySession.recoveryHash(challenge)
					});
					const entered = deferred(),
						release = deferred();
					beforeComplete = async () => {
						entered.resolve();
						await release.promise;
					};
					const completing = f.service().complete(f.auth, f.input.id, f.input.receipt);
					await entered.promise;
					const committed = await reset.confirm({
						operationId,
						challenge,
						cipher: Buffer.alloc(48, 1).toString('base64'),
						nonce: Buffer.alloc(24, 2).toString('base64')
					});
					assert.equal((await f.row()).operationId, operationId);
					assert.equal((await f.row()).retired, 1);
					assert.deepEqual(await db.select().from(tables.file), []);
					assert.deepEqual(await db.select().from(tables.userDevice), []);
					await prefixCleanup.drainRecoveryCleanup(
						db,
						{
							step: async () => {
								sweeps++;
								return { cursor: {}, done: true };
							}
						},
						{ now: () => now }
					);
					assert.equal(sweeps, 0);
					release.resolve();
					assert.equal((await completing).state, 'cleanup_pending');
					assert.equal(published, true);
					now++;
					await core.drainManagedUploads(db, cloud, { now: () => now });
					assert.equal(published, false);
					now = committed.notBefore + 1;
					await prefixCleanup.drainRecoveryCleanup(
						db,
						{
							step: async () => {
								sweeps++;
								return { cursor: {}, done: true };
							}
						},
						{ now: () => now, limit: 4 }
					);
					assert.equal((await reset.status(operationId)).phase, 'ready');
					assert.equal(sweeps, 1);
				}
			);
		} finally {
			await vite.close();
			await database.close();
		}
	}
);
