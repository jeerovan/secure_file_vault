import 'dotenv/config';
import { sql } from 'drizzle-orm';
import * as schema from '../src/lib/server/db/schema';
import { ProviderKeys, StorageProvider, UserKeys } from '../src/lib/server/db/keys';
import { resolveDatabaseDriver, withScriptDatabase } from './database';

const main = async () => {
	const driver = resolveDatabaseDriver(process.argv[2]);

	console.log(`🌱 Seeding database with the ${driver} driver...`);

	try {
		await withScriptDatabase(driver, async (db) => {
			await db.insert(schema.user).values({
				[UserKeys.REMOTE_AUTH_ID]: 'fife',
				[UserKeys.EMAIL]: 'fife@jeero.one',
				[UserKeys.CIPHER]: 'None',
				[UserKeys.NONCE]: 'None'
			});
			await db.insert(schema.provider).values({
				[ProviderKeys.ID]: StorageProvider.FIFE,
				[ProviderKeys.TITLE]: 'FiFe',
				[ProviderKeys.FREE_BYTES]: 1073741824,
				[ProviderKeys.PRIORITY]: 1
			});
			await db.insert(schema.provider).values({
				[ProviderKeys.ID]: StorageProvider.BACKBLAZE,
				[ProviderKeys.TITLE]: 'BackBlaze B2',
				[ProviderKeys.FREE_BYTES]: 10737418240,
				[ProviderKeys.PRIORITY]: 10
			});
			await db.insert(schema.provider).values({
				[ProviderKeys.ID]: StorageProvider.CLOUDFLARE,
				[ProviderKeys.TITLE]: 'Cloudflare R2',
				[ProviderKeys.FREE_BYTES]: 10737418240,
				[ProviderKeys.PRIORITY]: 4
			});
			await db.insert(schema.provider).values({
				[ProviderKeys.ID]: StorageProvider.OCI,
				[ProviderKeys.TITLE]: 'Oracle Object Storage',
				[ProviderKeys.FREE_BYTES]: 21474836480,
				[ProviderKeys.PRIORITY]: 8
			});
			await db.insert(schema.provider).values({
				[ProviderKeys.ID]: StorageProvider.IDRIVE,
				[ProviderKeys.TITLE]: 'IDrive E2',
				[ProviderKeys.FREE_BYTES]: 10737418240,
				[ProviderKeys.PRIORITY]: 6
			});
			await db.insert(schema.provider).values({
				[ProviderKeys.ID]: StorageProvider.S3,
				[ProviderKeys.TITLE]: 'S3 Compatible',
				[ProviderKeys.FREE_BYTES]: 10737418240,
				[ProviderKeys.PRIORITY]: 5
			});
			await db.execute(
				sql`SELECT setval(pg_get_serial_sequence('provider', '1'), (SELECT MAX("1") FROM provider), true)`
			);
		});

		console.log('✅ Database seeded successfully!');
	} catch (error) {
		console.error('❌ Error seeding database:', error);
		process.exitCode = 1;
	}
};

await main();
