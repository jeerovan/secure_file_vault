import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import { getOptimalStorage } from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: ErrorCode.INVALID_JSON });
	}

	const { file_hash, file_size } = body;

	if (!file_hash || !file_size) {
		return json({ status: 0, error: ErrorCode.MISSING_FIELDS });
	}

	const storage = await getOptimalStorage(authUser.id, file_size);
	if (storage) {
		return json({ status: 1 });
	} else {
		return json({ status: 0, error: ErrorCode.NO_STORAGE });
	}
};
