import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { getDb } from '$lib/server/db';
import { getUserData, removeDevice, updateStorageLimit } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

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

	const { provider_id, bytes } = body;

	if (!provider_id || !bytes) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	if (bytes < 1073741824) {
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}
	const planData = await getUserData(db, authUser.userId!);
	let planExpiresAt = 0;
	if (planData) {
		planExpiresAt = planData.planExpiresAt;
	}
	const hasPlan = planExpiresAt > Date.now();
	if (hasPlan) {
		await updateStorageLimit(db, authUser.userId!, provider_id, bytes);
	} else {
		return json({ success: 0, message: ErrorCode.NO_PRO });
	}
	return json({ success: 1 });
};
