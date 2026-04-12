import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import { addUpdateDevice, getUserDevices, updateDeviceStatus } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const GET: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);
	const deviceUuid = url.searchParams.get('device_uuid') || undefined;
	const result = await getUserDevices(authUser.userId!, deviceUuid);

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

	const { device_uuid, title, type, notificationId, active } = body;

	if (!device_uuid) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	return addUpdateDevice(authUser.userId!, device_uuid, title, type, notificationId, active);
};

export const DELETE: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);

	let deviceUuid = url.searchParams.get('device_uuid');

	if (!deviceUuid) {
		try {
			const body = await request.json();
			deviceUuid = body.device_id;
		} catch {
			return json({ success: 0, message: ErrorCode.INVALID_JSON });
		}
	}

	if (!deviceUuid) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	return updateDeviceStatus(authUser.userId!, deviceUuid, 0);
};
