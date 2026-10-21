import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireDeviceAuth as requireAuth } from '$lib/server/auth';
import { authenticate } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';
import { backblazeS3Download } from '$lib/server/backblazeS3';
import { getDb } from '$lib/server/db';
import { isVaultPartName } from '$lib/server/recoveryStorage';
import { finalDeviceResponse } from '$lib/server/deviceAccess';
import { getPartObjectKey } from '$lib/server/partObject';

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

	const { file_id, storage_id } = body;
	if (file_id !== undefined && !isVaultPartName(file_id))
		return json({ success: 0, message: ErrorCode.INVALID_DATA });

	if (!file_id) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const authData = await authenticate(db, authUser.userId!, storage_id);
	if (!authData) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	try {
		const key = await getPartObjectKey(
			db,
			authUser.userId!,
			storage_id,
			file_id,
			authUser.objectPrefix!
		);
		const presignedUrl = await backblazeS3Download(authData, key);
		return finalDeviceResponse(db, authUser, json({ success: 1, data: presignedUrl }));
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}
};
