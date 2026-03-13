import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, deleteFileVersion } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: ErrorCode.INVALID_JSON });
	}

	const { file_name, file_id } = body;

	if (!file_name || !file_id) {
		return json({ status: 0, error: ErrorCode.MISSING_FIELDS });
	}
	const authData = await authenticate(authUser.id);
	if (!authData) {
		return json({ status: 0, error: ErrorCode.NO_USER });
	}
	const result = await deleteFileVersion({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		fileName: file_name,
		fileId: file_id
	});
	return result;
};
