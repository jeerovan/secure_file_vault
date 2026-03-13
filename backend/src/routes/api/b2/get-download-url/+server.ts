import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, getDownloadAuthorization } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: ErrorCode.INVALID_JSON });
	}

	const { file_path } = body;

	if (!file_path) {
		return json({ status: 0, error: ErrorCode.MISSING_FIELDS });
	}
	const authData = await authenticate(authUser.id);
	if (!authData) {
		return json({ status: 0, error: ErrorCode.NO_USER });
	}
	const result = await getDownloadAuthorization({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		bucketId: authData.bucketId,
		fileNamePrefix: file_path,
		validDurationInSeconds: 604800 // one week in seconds
	});
	return result;
};
