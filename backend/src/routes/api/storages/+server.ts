import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode } from '$lib/server/db/keys';
import { getProviders, getUserStorage } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { authorizeRegisteredDevice } from '$lib/server/deviceAccess';

export const GET: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (authUser.authorized) {
		const access = await authorizeRegisteredDevice(db, {
			...authUser,
			vaultProtocol: request.headers.get('x-fife-vault-protocol') === '1' ? 1 : 0,
			requestedVaultGeneration: request.headers.get('x-fife-vault-generation') ?? undefined
		});
		if (!access.authorized) {
			return json({ success: 0, message: access.message, reason: access.reason });
		}
		const result = await getUserStorage(db, authUser.userId!);
		if (!result) {
			return json({ success: 0, message: ErrorCode.NO_USER });
		}
		return json({ success: 1, data: result });
	} else {
		const result = await getProviders(db);
		return json({ success: 1, data: result });
	}
};
