import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, getUploadUrl } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { storage_id } = body;

	const authData = await authenticate(authUser.userId!, storage_id);
	if (!authData) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	const result = await getUploadUrl({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		bucketId: authData.bucketId
	});
	return result;
};
