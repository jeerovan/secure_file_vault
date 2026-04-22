import 'dotenv/config';
import { drizzle } from 'drizzle-orm/neon-http';
import { neon } from '@neondatabase/serverless';
import * as schema from '../src/lib/server/db/schema';
import { CredentialKeys, StorageProvider, UserKeys } from '../src/lib/server/db/keys';
import { eq } from 'drizzle-orm';

const main = async (appId: string, appKey: string) => {
	const dbUrl = process.env.DATABASE_URL;

	if (!dbUrl) {
		throw new Error('DATABASE_URL is not defined in the .env file');
	}

	const client = neon(dbUrl);
	const db = drizzle(client, { schema });

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
		const providerId = StorageProvider.FIFE;
		const [fifeUser] = await db
			.select()
			.from(schema.user)
			.where(eq(schema.user[UserKeys.SUPABASE_ID], 'fife'))
			.limit(1);
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
