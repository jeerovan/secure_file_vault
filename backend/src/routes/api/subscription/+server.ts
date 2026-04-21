import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { syncPlanExpiry } from '$lib/server/db/api';

export const GET: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	syncPlanExpiry(authUser.userId!, authUser.supabaseId!); // no wait
	return json({ success: 1 });
};
