import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode } from '$lib/server/db/keys';
import { getProviders, getUserStorage } from '$lib/server/db/api';

export const GET: RequestHandler = async ({ request }) => {
	if (request.headers.has('Authorization')) {
		const authUser = await requireAuth(request);
		if (!authUser.authorized) {
			return json({ success: 0, message: authUser.message });
		}
		const result = await getUserStorage(authUser.userId!);

		if (!result) {
			return json({ success: 0, message: ErrorCode.NO_USER });
		}

		return json({ success: 1, data: result });
	} else {
		const result = await getProviders();
		return json({ success: 1, data: result });
	}
};
