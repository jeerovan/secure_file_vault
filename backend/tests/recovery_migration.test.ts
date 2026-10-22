import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
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
