// scripts/seed.ts
import 'dotenv/config';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import Database from 'better-sqlite3';
import * as schema from '../src/lib/server/db/schema'; // Path relative to the scripts folder
import { ProviderKeys, UserKeys } from '../src/lib/server/db/keys';

const main = async () => {
	const dbUrl = process.env.DATABASE_URL;

	if (!dbUrl) {
		throw new Error('DATABASE_URL is not defined in the .env file');
	}

	// Initialize the SQLite connection and Drizzle ORM
	const sqlite = new Database(dbUrl);
	const db = drizzle(sqlite, { schema });

	console.log('🌱 Seeding database...');

	try {
		await db.insert(schema.user).values({
			[UserKeys.SUPABASE_ID]: 'fife',
			[UserKeys.EMAIL]: 'fife@jeero.one',
			[UserKeys.CIPHER]: 'None',
			[UserKeys.NONCE]: 'None'
		});
		await db.insert(schema.provider).values({
			[ProviderKeys.TITLE]: 'FiFe',
			[ProviderKeys.FREE_BYTES]: 1073741824,
			[ProviderKeys.PRIORITY]: 1
		});
		await db.insert(schema.provider).values({
			[ProviderKeys.TITLE]: 'BackBlaze B2',
			[ProviderKeys.FREE_BYTES]: 10737418240,
			[ProviderKeys.PRIORITY]: 10
		});
		await db.insert(schema.provider).values({
			[ProviderKeys.TITLE]: 'Cloudflare R2',
			[ProviderKeys.FREE_BYTES]: 10737418240,
			[ProviderKeys.PRIORITY]: 4
		});
		await db.insert(schema.provider).values({
			[ProviderKeys.TITLE]: 'Oracle Object Storage',
			[ProviderKeys.FREE_BYTES]: 21474836480,
			[ProviderKeys.PRIORITY]: 8
		});
		await db.insert(schema.provider).values({
			[ProviderKeys.TITLE]: 'IDrive E2',
			[ProviderKeys.FREE_BYTES]: 10737418240,
			[ProviderKeys.PRIORITY]: 6
		});

		console.log('✅ Database seeded successfully!');
		process.exit(0);
	} catch (error) {
		console.error('❌ Error seeding database:', error);
		process.exit(1);
	}
};

main();
