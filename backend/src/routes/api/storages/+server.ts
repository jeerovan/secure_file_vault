import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode } from '$lib/server/db/keys';
import { getProviders, getUserStorage } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';

export const GET: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (authUser.authorized) {
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
