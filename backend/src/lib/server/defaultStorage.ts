import { and, eq } from 'drizzle-orm';
import type { Db, Tx } from './db';
import { user, credential, provider, storage } from './db/schema';
import { UserKeys, CredentialKeys, ProviderKeys, StorageKeys, StorageProvider } from './db/keys';

/** Caller holds the account write lock (or is creating this account). */
export async function ensureDefaultFiFeStorage(db: Db | Tx, userId: number) {
	const [service] = await db
		.select({ id: user[UserKeys.ID] })
		.from(user)
		.where(eq(user[UserKeys.REMOTE_AUTH_ID], 'fife'))
		.limit(1);
	if (!service) return;
	const [credentials] = await db
		.select({ id: credential[CredentialKeys.ID] })
		.from(credential)
		.where(
			and(
				eq(credential[CredentialKeys.USER_ID], service.id),
				eq(credential[CredentialKeys.PROVIDER_ID], StorageProvider.FIFE)
			)
		)
		.limit(1);
	if (!credentials) return;
	const [existing] = await db
		.select({ id: storage[StorageKeys.ID] })
		.from(storage)
		.where(
			and(
				eq(storage[StorageKeys.USER_ID], userId),
				eq(storage[StorageKeys.CREDENTIAL_ID], credentials.id)
			)
		)
		.limit(1);
	if (existing) return;
	const [entry] = await db
		.select()
		.from(provider)
		.where(eq(provider[ProviderKeys.ID], StorageProvider.FIFE))
		.limit(1);
	if (!entry) return;
	await db.insert(storage).values({
		[StorageKeys.USER_ID]: userId,
		[StorageKeys.CREDENTIAL_ID]: credentials.id,
		[StorageKeys.LIMIT_BYTES]: entry[ProviderKeys.FREE_BYTES],
		[StorageKeys.LIMIT_FREE_BYTES]: entry[ProviderKeys.FREE_BYTES],
		[StorageKeys.PRIORITY]: entry[ProviderKeys.PRIORITY],
		[StorageKeys.JSON]: {}
	});
}
