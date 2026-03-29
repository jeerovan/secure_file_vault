import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ErrorCode } from '$lib/server/db/keys';
import { deleteFileFromStorage } from '$lib/server/deleteWorker';

export const POST: RequestHandler = async ({ request }) => {
	let body;
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { userId, fileHash } = body;

	if (!userId || !fileHash) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	deleteFileFromStorage(userId, fileHash);
	return json({ success: 1 });
};
