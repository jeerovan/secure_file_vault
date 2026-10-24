import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import postgres from 'postgres';
import { createRecoveryDatabase, recoveryTestUrl } from './support/recoveryDatabase';
import { applyRecoveryMigration } from '../scripts/recoveryMigration';
import {
	user,
	recoveryReset,
	vaultState,
	vaultUploadCapability,
	vaultUpload
} from '../src/lib/server/db/schema';
import { UserKeys } from '../src/lib/server/db/keys';

function migrationText(id: string) {
	return readFile(new URL(`../migrations/${id}.sql`, import.meta.url), 'utf8');
}

test(
	'a failed migration rolls back its file and retries without losing earlier migrations',
	{ skip: !recoveryTestUrl },
	async () => {
		const database = await createRecoveryDatabase({ legacy: true });
		try {
			const first = await migrationText('0001_recovery_reset');
			const second = await migrationText('0002_upload_capability');
			await applyRecoveryMigration(database.db.$client, first);
			await assert.rejects(
				applyRecoveryMigration(
					database.db.$client,
					`${second}\nSELECT 1 / 0;`,
					'0002_upload_capability'
				),
				{ code: '22012' }
			);
			assert.deepEqual(
				(await database.db.$client`SELECT id FROM fife_schema_migration ORDER BY id`).map(
					(row) => row.id
				),
				['0001_recovery_reset']
			);
			const [rolledBack] = await database.db
				.$client`SELECT to_regclass('public.vault_upload_capability')::text AS name`;
			assert.equal(rolledBack.name, null, 'DDL from the failed file must roll back');
			await applyRecoveryMigration(database.db.$client, first);
			await applyRecoveryMigration(database.db.$client, second, '0002_upload_capability');
			assert.deepEqual(await database.db.select().from(vaultUploadCapability), []);
			assert.deepEqual(
				(await database.db.$client`SELECT id FROM fife_schema_migration ORDER BY id`).map(
					(row) => row.id
				),
				['0001_recovery_reset', '0002_upload_capability']
			);
		} finally {
			await database.close();
		}
	}
);

test(
	'concurrent migration runners serialize and record each file exactly once',
	{ skip: !recoveryTestUrl },
	async () => {
		const database = await createRecoveryDatabase({ legacy: true });
		const clients = Array.from({ length: 4 }, () => postgres(database.url, { max: 1 }));
		try {
			const migrations = await Promise.all(
				['0001_recovery_reset', '0002_upload_capability'].map(async (id) => ({
					id,
					text: await migrationText(id)
				}))
			);
			await Promise.all(
				clients.map(async (client) => {
					for (const migration of migrations)
						await applyRecoveryMigration(client, migration.text, migration.id);
				})
			);
			assert.deepEqual(
				(await database.db.$client`SELECT id FROM fife_schema_migration ORDER BY id`).map(
					(row) => row.id
				),
				migrations.map((migration) => migration.id)
			);
			assert.deepEqual(await database.db.select().from(vaultState), []);
			assert.deepEqual(await database.db.select().from(vaultUploadCapability), []);
			await assert.rejects(
				applyRecoveryMigration(clients[0], `${migrations[0].text}\n-- conflicting runner`),
				/checksum differs/
			);
		} finally {
			await Promise.all(clients.map((client) => client.end()));
			await database.close();
		}
	}
);

test(
	'an index blocked by live table activity times out safely and succeeds on retry',
	{ skip: !recoveryTestUrl, timeout: 20_000 },
	async () => {
		const database = await createRecoveryDatabase({ legacy: true });
		const blocker = postgres(database.url, { max: 1 });
		let release!: () => void;
		let locked!: () => void;
		const released = new Promise<void>((resolve) => (release = resolve));
		const acquired = new Promise<void>((resolve) => (locked = resolve));
		let blocking: Promise<unknown> | undefined;
		try {
			for (const id of [
				'0001_recovery_reset',
				'0002_upload_capability',
				'0003_managed_upload',
				'0004_upload_cleanup_cursor'
			])
				await applyRecoveryMigration(database.db.$client, await migrationText(id), id);
			// The shared fixture generates current non-recovery models, including
			// this index. Recreate the pre-0005 state before testing its DDL lock.
			await database.db.$client.unsafe('DROP INDEX part_managed_object');
			blocking = blocker.begin(async (tx) => {
				await tx.unsafe('LOCK TABLE "part" IN ACCESS EXCLUSIVE MODE');
				locked();
				await released;
			});
			await Promise.race([
				acquired,
				blocking.then(() => {
					throw new Error('Table lock was not held');
				})
			]);
			const index = await migrationText('0005_managed_object_index');
			await assert.rejects(
				applyRecoveryMigration(database.db.$client, index, '0005_managed_object_index'),
				{ code: '55P03' }
			);
			const [absent] = await database.db
				.$client`SELECT to_regclass('public.part_managed_object')::text AS name`;
			assert.equal(absent.name, null);
			assert.equal(
				(
					await database.db
						.$client`SELECT id FROM fife_schema_migration WHERE id = '0005_managed_object_index'`
				).length,
				0
			);
			release();
			await blocking;
			await applyRecoveryMigration(database.db.$client, index, '0005_managed_object_index');
			const [created] = await database.db
				.$client`SELECT indisvalid, indisready FROM pg_index WHERE indexrelid = 'public.part_managed_object'::regclass`;
			assert.equal(created.indisvalid, true);
			assert.equal(created.indisready, true);
		} finally {
			release();
			await blocking;
			await blocker.end();
			await database.close();
		}
	}
);

test(
	'additive recovery migration preserves existing rows and is safely repeatable',
	{ skip: !recoveryTestUrl },
	async () => {
		const database = await createRecoveryDatabase({ legacy: true });
		try {
			const [original] = await database.db
				.insert(user)
				.values({
					[UserKeys.REMOTE_AUTH_ID]: 'fixture-user',
					[UserKeys.EMAIL]: 'fixture@example.test',
					[UserKeys.CIPHER]: 'original-cipher',
					[UserKeys.NONCE]: 'original-nonce'
				})
				.returning();
			const migration = await readFile(
				new URL('../migrations/0001_recovery_reset.sql', import.meta.url),
				'utf8'
			);
			await applyRecoveryMigration(database.db.$client, migration);
			await applyRecoveryMigration(database.db.$client, migration);
			assert.deepEqual((await database.db.select().from(user))[0], original);
			assert.deepEqual(await database.db.select().from(vaultState), []);
			assert.deepEqual(await database.db.select().from(recoveryReset), []);
			await assert.rejects(
				applyRecoveryMigration(database.db.$client, `${migration}\n-- changed`),
				/checksum differs/
			);
			const rls = await database.db
				.$client`SELECT relname, relrowsecurity FROM pg_class WHERE relname IN ('vault_state', 'recovery_reset', 'recovery_cleanup_target', 'recovery_worker_state')`;
			assert.equal(rls.length, 4);
			assert.ok(rls.every((row) => row.relrowsecurity));
			const capabilities = await readFile(
				new URL('../migrations/0002_upload_capability.sql', import.meta.url),
				'utf8'
			);
			await applyRecoveryMigration(database.db.$client, capabilities, '0002_upload_capability');
			await applyRecoveryMigration(database.db.$client, capabilities, '0002_upload_capability');
			assert.deepEqual(await database.db.select().from(vaultUploadCapability), []);
			assert.deepEqual((await database.db.select().from(user))[0], original);
			assert.deepEqual(await database.db.select().from(vaultState), []);
			await assert.rejects(
				applyRecoveryMigration(
					database.db.$client,
					`${capabilities}\n-- changed`,
					'0002_upload_capability'
				),
				/checksum differs/
			);
			const [capabilityRls] = await database.db
				.$client`SELECT relrowsecurity FROM pg_class WHERE relname = 'vault_upload_capability'`;
			assert.equal(capabilityRls.relrowsecurity, true);
			const managed = await readFile(
				new URL('../migrations/0003_managed_upload.sql', import.meta.url),
				'utf8'
			);
			await applyRecoveryMigration(database.db.$client, managed, '0003_managed_upload');
			await applyRecoveryMigration(database.db.$client, managed, '0003_managed_upload');
			const cursor = await readFile(
				new URL('../migrations/0004_upload_cleanup_cursor.sql', import.meta.url),
				'utf8'
			);
			await applyRecoveryMigration(database.db.$client, cursor, '0004_upload_cleanup_cursor');
			await applyRecoveryMigration(database.db.$client, cursor, '0004_upload_cleanup_cursor');
			const index = await readFile(
				new URL('../migrations/0005_managed_object_index.sql', import.meta.url),
				'utf8'
			);
			await database.db.$client.unsafe('DROP INDEX part_managed_object');
			await applyRecoveryMigration(database.db.$client, index, '0005_managed_object_index');
			await applyRecoveryMigration(database.db.$client, index, '0005_managed_object_index');
			const indexes = await database.db
				.$client`SELECT indexdef FROM pg_indexes WHERE indexname = 'part_managed_object'`;
			assert.equal(indexes.length, 1);
			assert.match(indexes[0].indexdef, /managedObjectKey/);
			assert.deepEqual(await database.db.select().from(vaultUpload), []);
			assert.deepEqual((await database.db.select().from(user))[0], original);
			const [managedRls] = await database.db
				.$client`SELECT relrowsecurity FROM pg_class WHERE relname = 'vault_upload'`;
			assert.equal(managedRls.relrowsecurity, true);
			// Emulate the released envelope columns before applying the widening migration.
			await database.db.$client.unsafe(
				'ALTER TABLE "user" ALTER COLUMN "6" SET NOT NULL, ALTER COLUMN "7" SET NOT NULL'
			);
			await database.db.$client.unsafe('ALTER TABLE "user" DROP CONSTRAINT user_key_envelope_pair');
			const deferred = await readFile(
				new URL('../migrations/0006_deferred_vault_keys.sql', import.meta.url),
				'utf8'
			);
			await applyRecoveryMigration(database.db.$client, deferred, '0006_deferred_vault_keys');
			await applyRecoveryMigration(database.db.$client, deferred, '0006_deferred_vault_keys');
			assert.deepEqual((await database.db.select().from(user))[0], original);
			const columns = await database.db
				.$client`SELECT is_nullable FROM information_schema.columns WHERE table_name='user' AND column_name IN ('6','7')`;
			assert.equal(columns.length, 2);
			assert.ok(columns.every((column) => column.is_nullable === 'YES'));
			await assert.rejects(
				database.db.$client.unsafe('UPDATE "user" SET "6"=NULL WHERE "4"=\'fixture-user\''),
				/user_key_envelope_pair/
			);
			await database.db.$client.unsafe(
				'UPDATE "user" SET "6"=NULL, "7"=NULL WHERE "4"=\'fixture-user\''
			);
			assert.equal((await database.db.select().from(user))[0][UserKeys.CIPHER], null);
			await assert.rejects(
				applyRecoveryMigration(
					database.db.$client,
					`${managed}\n-- changed`,
					'0003_managed_upload'
				),
				/checksum differs/
			);
		} finally {
			await database.close();
		}
	}
);
