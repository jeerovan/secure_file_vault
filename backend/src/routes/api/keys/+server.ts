import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode, UserKeys } from '$lib/server/db/keys';
import { addUser, getUser } from '$lib/server/db/api';

export const GET: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	if (!authUser.userId) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	const user = await getUser(authUser.userId);
	if (!user) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}

	return json({ success: 1, data: { cipher: user[UserKeys.CIPHER], nonce: user[UserKeys.NONCE] } });
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

	const result = addUser(authUser.supabaseId, authUser.email, cipher, nonce);

	return json({ success: 1, data: result });
};
