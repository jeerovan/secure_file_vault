import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireBootstrapAuth as requireAuth } from '$lib/server/auth';
import { withBootstrapWrite } from '$lib/server/vaultBootstrap';
import { getDb } from '$lib/server/db';
import { addUpdateDevice, getUserDevices, updateDeviceStatus } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const GET: RequestHandler = async ({ request, url, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	const deviceUuid = url.searchParams.get('device_uuid') || undefined;
	if (!authUser.authorized) {
		// Released clients discover removal only through this successful own-device
		// status response. Never grant the retired caller a device list or another
		// device's metadata, and never translate a retryable auth failure to removal.
		if (
			deviceUuid &&
			deviceUuid === request.headers.get('device_uuid') &&
			(authUser.reason === 'device_revoked' ||
				authUser.reason === 'vault_replaced' ||
				(authUser.message === ErrorCode.NO_USER && authUser.remoteAuthId))
		) {
			return json({ success: 1, data: { id: deviceUuid, active: 0 } });
		}
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
	}
	const result = await getUserDevices(db, authUser.userId!, deviceUuid);

	return json({ success: 1, data: result });
};

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
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

	return withBootstrapWrite(
		db,
		authUser,
		(tx) => addUpdateDevice(tx, authUser.userId!, device_uuid, title, type, notificationId, active),
		true
	);
};

export const DELETE: RequestHandler = async ({ request, url, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
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

	return withBootstrapWrite(db, authUser, (tx) =>
		updateDeviceStatus(tx, authUser.userId!, deviceUuid, 0)
	);
};
