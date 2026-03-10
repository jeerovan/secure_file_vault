import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, finishLargeFile } from '$lib/server/backblaze';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: 'Invalid JSON body' });
	}

	const { file_id, part_array } = body;

	if (!file_id || !part_array) {
		return json({ status: 0, error: 'Missing required fields' });
	}
	const authData = await authenticate(authUser.id);
	if (!authData) {
		return json({ status: 0, error: 'No Account Found' });
	}
	const result = await finishLargeFile({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		fileId: file_id,
		partSha1Array: part_array
	});
	return result;
};
