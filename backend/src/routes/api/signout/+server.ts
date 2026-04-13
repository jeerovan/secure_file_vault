import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import { removeDevice } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { device_uuid } = body;

	if (!device_uuid) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	return await removeDevice(authUser.userId!, device_uuid);
};
