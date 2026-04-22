import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { syncPlanExpiry } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
export const GET: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	syncPlanExpiry(db, authUser.userId!, authUser.supabaseId!); // no wait
	return json({ success: 1 });
};
