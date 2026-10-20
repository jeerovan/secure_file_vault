import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireDeviceAuth as requireAuth } from '$lib/server/auth';
import { authenticate, listFileNames } from '$lib/server/backblaze';
import { findMatchingB2Upload } from '$lib/server/b2UploadRecovery';
import { ErrorCode } from '$lib/server/db/keys';
import { getDb } from '$lib/server/db';
import { isVaultPartName } from '$lib/server/recoveryStorage';
import { findBackblazeS3Upload } from '$lib/server/backblazeS3';
import { finalDeviceResponse } from '$lib/server/deviceAccess';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
	}

	let body;
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_id, storage_id, content_sha1, content_length } = body;
	if (file_id !== undefined && !isVaultPartName(file_id))
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
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

	const fileName = `${authUser.objectPrefix}${file_id}`;
	try {
		const match = await findBackblazeS3Upload(authData, fileName, content_sha1, content_length);
		if (match !== undefined)
			return finalDeviceResponse(db, authUser, json({ success: 1, data: match }));
	} catch {
		return json({ success: 0, message: 'provider_unavailable' });
	}
	// Native uploads may not expose their core SHA1 in S3 user metadata.
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
	return finalDeviceResponse(
		db,
		authUser,
		json({
			success: 1,
			data: match ? { fileId: match.fileId } : null
		})
	);
};
