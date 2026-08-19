import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, listFileNames } from '$lib/server/backblaze';
import { findMatchingB2Upload } from '$lib/server/b2UploadRecovery';
import { ErrorCode } from '$lib/server/db/keys';
import { getDb } from '$lib/server/db';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}

	let body;
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_id, storage_id, content_sha1, content_length } = body;
	if (
		!file_id ||
		!storage_id ||
		typeof content_sha1 !== 'string' ||
		!Number.isSafeInteger(content_length) ||
		content_length < 0
	) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	const authData = await authenticate(db, authUser.userId!, storage_id);
	if (!authData) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}

	const fileName = `${authUser.remoteAuthId}/${file_id}`;
	const response = await listFileNames({
		apiUrl: authData.apiUrl,
		authorizationToken: authData.authorizationToken,
		bucketId: authData.bucketId,
		fileName
	});
	const result = await response.json();
	if (result.success !== 1) return json(result);

	const match = findMatchingB2Upload(
		Array.isArray(result.data?.files) ? result.data.files : [],
		fileName,
		content_sha1,
		content_length
	);
	return json({
		success: 1,
		data: match ? { fileId: match.fileId } : null
	});
};
