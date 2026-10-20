import { createHash } from 'node:crypto';
import type postgres from 'postgres';

/** Run once under an advisory lock; retries verify the exact migration text. */
export async function applyRecoveryMigration(
	client: postgres.Sql,
	migration: string,
	migrationId = '0001_recovery_reset'
) {
	if (!/^\d{4}_[a-z_]+$/.test(migrationId)) throw new Error('Invalid migration identifier');
	const checksum = createHash('sha256').update(migration).digest('hex');
	await client.begin(async (tx) => {
		await tx.unsafe("SET LOCAL lock_timeout = '5s'");
		await tx.unsafe("SET LOCAL statement_timeout = '30s'");
		await tx`SELECT pg_advisory_xact_lock(1179207237, 1380270931)`;
		await tx.unsafe(
			'CREATE TABLE IF NOT EXISTS fife_schema_migration (id text PRIMARY KEY, checksum text NOT NULL)'
		);
		const rows = await tx`SELECT checksum FROM fife_schema_migration WHERE id = ${migrationId}`;
		if (rows.length) {
			if (rows[0].checksum !== checksum)
				throw new Error('Applied recovery migration checksum differs');
			return;
		}
		await tx.unsafe(migration);
		await tx`INSERT INTO fife_schema_migration (id, checksum) VALUES (${migrationId}, ${checksum})`;
	});
}
