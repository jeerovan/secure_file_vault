import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, cancelLargeFile } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: ErrorCode.INVALID_JSON });
	}

	const { file_id, storage_id } = body;

	if (!file_id || !storage_id) {
		return json({ status: 0, error: ErrorCode.MISSING_FIELDS });
	}
	const authData = await authenticate(authUser.id, storage_id);
	if (!authData) {
		return json({ status: 0, error: ErrorCode.NO_USER });
	}
	const result = await cancelLargeFile({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		fileId: file_id
	});
	return result;
};
