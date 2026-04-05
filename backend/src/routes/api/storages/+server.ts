import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode } from '$lib/server/db/keys';
import { addKey, getStorages, getUserStorage } from '$lib/server/db/api';

export const GET: RequestHandler = async ({ request }) => {
	if (request.headers.has('Authorization')) {
		const authUser = await requireAuth(request);

		const result = await getUserStorage(authUser.id);

		if (!result) {
			return json({ success: 0, message: ErrorCode.NO_USER });
		}

		return json({ success: 1, data: result });
	} else {
		const result = await getStorages();
		return json({ success: 1, data: result });
	}
};

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	let body: { cipher?: string; nonce?: string };
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { cipher, nonce } = body;

	if (!cipher || !nonce) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	const result = await addKey(authUser.id, authUser.email, cipher, nonce);

	return json({ success: 1, data: result });
};
