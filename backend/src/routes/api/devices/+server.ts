import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import { addUpdateDevice, getUserDevices } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const GET: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	const result = await getUserDevices(authUser.id);

	return json({ success: 1, data: result });
};

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { device_id, title, type, notificationId, active } = body;

	if (!device_id) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	const tableId = authUser.id + '_' + device_id;

	return await addUpdateDevice(authUser.id, tableId, title, type, notificationId, active);
};
