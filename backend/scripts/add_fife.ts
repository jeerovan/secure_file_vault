import 'dotenv/config';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from '../src/lib/server/db/schema';
import { CredentialKeys, StorageProvider, UserKeys } from '../src/lib/server/db/keys';
import { authorize } from '../src/lib/server/backblaze';
import { getUserBySupabaseId } from '../src/lib/server/db/api';

const main = async (appId: string, appKey: string) => {
	const dbUrl = process.env.DATABASE_URL;

	if (!dbUrl) {
		throw new Error('DATABASE_URL is not defined in the .env file');
	}

	const client = postgres(dbUrl);
	const db = drizzle(client, { schema });

	try {
		const { message, data } = await authorize(appId, appKey);
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
		const providerId = StorageProvider.FIFE;
		const fifeUser = await getUserBySupabaseId('fife');
		await db.insert(schema.credential).values({
			[CredentialKeys.USER_ID]: fifeUser[UserKeys.ID],
			[CredentialKeys.PROVIDER_ID]: providerId,
			[CredentialKeys.CREDENTIALS]: credentials
		});
		console.log('✅ FiFe added successfully!');
		process.exit(0);
	} catch (error) {
		console.error('❌ Error seeding database:', error);
		process.exit(1);
	}
};

const args = process.argv.slice(2);
const appId = args[0];
const appKey = args[1];

if (!appId || !appKey) {
	console.error('❌ Error: Missing appId or appKey arguments.');
	console.error('Usage: npm run db:add-fife -- <appId> <appKey>');
	process.exit(1);
}
main(appId, appKey);
