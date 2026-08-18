import 'dotenv/config';
import * as schema from '../src/lib/server/db/schema';
import { CredentialKeys, StorageProvider, UserKeys } from '../src/lib/server/db/keys';
import { eq } from 'drizzle-orm';
import {
	isDatabaseDriver,
	resolveDatabaseDriver,
	withScriptDatabase,
	type DatabaseDriver
} from './database';

const main = async (driver: DatabaseDriver, appId: string, appKey: string) => {
	try {
		const B2_API_URL = 'https://api.backblazeb2.com/b2api/v4';
		const authResponse = await fetch(`${B2_API_URL}/b2_authorize_account`, {
			headers: { Authorization: `Basic ${btoa(`${appId}:${appKey}`)}` }
		});

		const data = await authResponse.json();
		const {
			accountId,
			authorizationToken,
			apiInfo: {
				storageApi: {
					apiUrl,
					downloadUrl,
					allowed: {
						buckets: [{ id: bucketId, name: bucketName }]
					},
					s3ApiUrl
				}
			}
		} = data;
		const credentials = {
			accountId,
			appId,
			appKey,
			authorizationToken,
			bucketId,
			bucketName,
			apiUrl,
			downloadUrl,
			s3ApiUrl
		};
		await withScriptDatabase(driver, async (db) => {
			const [fifeUser] = await db
				.select()
				.from(schema.user)
				.where(eq(schema.user[UserKeys.REMOTE_AUTH_ID], 'fife'))
				.limit(1);
			if (!fifeUser) throw new Error('FiFe system user not found; run db:seed first');
			await db.insert(schema.credential).values({
				[CredentialKeys.USER_ID]: fifeUser[UserKeys.ID],
				[CredentialKeys.PROVIDER_ID]: StorageProvider.FIFE,
				[CredentialKeys.CREDENTIALS]: credentials
			});
		});
		console.log(`✅ FiFe added successfully with the ${driver} driver!`);
	} catch (error) {
		console.error('❌ Error seeding database:', error);
		process.exitCode = 1;
	}
};

const args = process.argv.slice(2);
const requestedDriver = isDatabaseDriver(args[0]) ? args.shift() : undefined;
const driver = resolveDatabaseDriver(requestedDriver);
const [appId, appKey] = args;

if (!appId || !appKey) {
	console.error('❌ Error: Missing appId or appKey arguments.');
	console.error('Usage: npm run db:add-fife -- [postgres|neon] <appId> <appKey>');
	process.exit(1);
}
await main(driver, appId, appKey);
