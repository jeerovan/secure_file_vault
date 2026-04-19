import type { PageServerLoad } from './$types';
import { getProviders, getUserBySupabaseId, getUserStorage } from '$lib/server/db/api';
import { UserKeys } from '$lib/server/db/keys';

export const load: PageServerLoad = async ({ locals: { safeGetSession } }) => {
	let storageProviders = [];
	const { user } = await safeGetSession();
	if (user != null) {
		const dbUser = await getUserBySupabaseId(user.id);
		storageProviders = await getUserStorage(dbUser[UserKeys.ID]);
	} else {
		storageProviders = await getProviders();
	}
	return {
		storageProviders
	};
};
