import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, getUploadUrl } from '$lib/server/backblaze';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	const authData = await authenticate(authUser.id);
	if (!authData) {
		return json({ status: 0, error: 'No Account Found' });
	}
	const result = await getUploadUrl({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		bucketId: authData.bucketId
	});
	return result;
};
