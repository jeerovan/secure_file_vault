import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import { addUpdateDevice, getUserDevices, updateDeviceStatus } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const GET: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);
	const deviceId = url.searchParams.get('device_id') || undefined;
	const result = await getUserDevices(authUser.id!, deviceId);

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

	return await addUpdateDevice(authUser.id!, device_id, title, type, notificationId, active);
};

export const DELETE: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);

	let device_id = url.searchParams.get('device_id');

	if (!device_id) {
		try {
			const body = await request.json();
			device_id = body.device_id;
		} catch {
			return json({ success: 0, message: ErrorCode.INVALID_JSON });
		}
	}

	if (!device_id) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	return updateDeviceStatus(authUser.id!, device_id, 0);
};
