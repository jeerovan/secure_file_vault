import 'dotenv/config';
import { sql } from 'drizzle-orm';
import * as schema from '../src/lib/server/db/schema';
import { ProviderKeys, StorageProvider } from '../src/lib/server/db/keys';
import { resolveDatabaseDriver, withScriptDatabase } from './database';

const driver = resolveDatabaseDriver(process.argv[2]);
await withScriptDatabase(driver, async (db) => {
	await db
		.insert(schema.provider)
		.values({
			[ProviderKeys.ID]: StorageProvider.S3,
			[ProviderKeys.TITLE]: 'S3 Compatible',
			[ProviderKeys.FREE_BYTES]: 10737418240,
			[ProviderKeys.PRIORITY]: 5
		})
		.onConflictDoUpdate({
			target: schema.provider[ProviderKeys.ID],
			set: {
				[ProviderKeys.TITLE]: 'S3 Compatible',
				[ProviderKeys.FREE_BYTES]: 10737418240,
				[ProviderKeys.PRIORITY]: 5
			}
		});
	await db.execute(
		sql`SELECT setval(pg_get_serial_sequence('provider', '1'), (SELECT MAX("1") FROM provider), true)`
	);
});
console.info(`S3 Compatible provider registered with the ${driver} driver`);
