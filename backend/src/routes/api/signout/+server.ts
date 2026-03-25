import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import { removeDevice } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, message: ErrorCode.INVALID_JSON });
	}

	const { device_id } = body;

	if (!device_id) {
		return json({ status: 0, message: ErrorCode.MISSING_FIELDS });
	}

	const tableId = authUser.id + '_' + device_id;

	return await removeDevice(tableId);
};
