import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { getDb } from '$lib/server/db';
import { addUpdateDevice, getUserDevices, updateDeviceStatus } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const GET: RequestHandler = async ({ request, url, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	const deviceUuid = url.searchParams.get('device_uuid') || undefined;
	const result = await getUserDevices(db, authUser.userId!, deviceUuid);

	return json({ success: 1, data: result });
};

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
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

	return await addUpdateDevice(
		db,
		authUser.userId!,
		device_uuid,
		title,
		type,
		notificationId,
		active
	);
};

export const DELETE: RequestHandler = async ({ request, url, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}

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

	return await updateDeviceStatus(db, authUser.userId!, deviceUuid, 0);
};
