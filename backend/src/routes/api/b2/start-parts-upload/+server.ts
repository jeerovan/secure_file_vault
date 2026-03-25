import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, startLargeFile } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_hash, storage_id } = body;

	if (!file_hash) {
		return json({ status: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const authData = await authenticate(authUser.id, storage_id);
	if (!authData) {
		return json({ status: 0, message: ErrorCode.NO_USER });
	}
	const file_name = `${authUser.id}/${file_hash}`;
	const result = await startLargeFile({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		bucketId: authData.bucketId,
		fileName: file_name,
		contentType: 'application/octet-stream'
	});
	return result;
};
