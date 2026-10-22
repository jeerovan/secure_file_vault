import { readFile } from 'node:fs/promises';
import postgres from 'postgres';
import { applyRecoveryMigration } from './recoveryMigration';

if (!process.env.DATABASE_URL)
	throw new Error('DATABASE_URL is required; no default database is used');
const databaseUrl = new URL(process.env.DATABASE_URL);
if (!['localhost', '127.0.0.1', '[::1]'].includes(databaseUrl.hostname)) {
	// Direct Neon connections require TLS; never weaken certificate validation.
	databaseUrl.searchParams.set('sslmode', 'verify-full');
}
const client = postgres(databaseUrl.toString(), { max: 1, connect_timeout: 10 });
try {
	for (const migrationId of [
		'0001_recovery_reset',
		'0002_upload_capability',
		'0003_managed_upload',
		'0004_upload_cleanup_cursor',
		'0005_managed_object_index',
		'0006_deferred_vault_keys'
	])
		await applyRecoveryMigration(
			client,
			await readFile(new URL(`../migrations/${migrationId}.sql`, import.meta.url), 'utf8'),
			migrationId
		);
	console.info('Recovery schema migration applied or already verified');
} finally {
	await client.end();
}
