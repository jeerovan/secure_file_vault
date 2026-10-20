import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireDeviceAuth as requireAuth } from '$lib/server/auth';
import { authenticate, getUploadUrl } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';
import { getDb } from '$lib/server/db';
import {
	withUploadAuthorization,
	LEGACY_B2_UPLOAD_EXPIRY_SECONDS
} from '$lib/server/uploadCapability';
import { PRESIGNED_UPLOAD_EXPIRY_SECONDS } from '$lib/server/s3';
import { backblazeS3Upload, validBackblazeUploadIntegrity } from '$lib/server/backblazeS3';
import { isVaultPartName } from '$lib/server/recoveryStorage';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
	}
	let body: Record<string, unknown>;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	if (!body || typeof body !== 'object' || Array.isArray(body))
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	const { storage_id, upload_protocol, file_id } = body;
	if (typeof storage_id !== 'number' || !Number.isSafeInteger(storage_id) || storage_id <= 0)
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	if (upload_protocol !== undefined && upload_protocol !== 's3')
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	if (
		upload_protocol === 's3' &&
		(!isVaultPartName(file_id) || !validBackblazeUploadIntegrity(body))
	)
		return json({ success: 0, message: ErrorCode.INVALID_DATA });

	return withUploadAuthorization(
		db,
		authUser,
		upload_protocol === 's3' ? PRESIGNED_UPLOAD_EXPIRY_SECONDS : LEGACY_B2_UPLOAD_EXPIRY_SECONDS,
		async (tx, current) => {
			try {
				const authData = await authenticate(tx, current.userId!, storage_id);
				if (!authData) {
					return json({ success: 0, message: ErrorCode.NO_USER });
				}
				if (
					upload_protocol === 's3' &&
					typeof file_id === 'string' &&
					validBackblazeUploadIntegrity(body)
				) {
					try {
						const data = await backblazeS3Upload(
							authData,
							`${current.objectPrefix}${file_id}`,
							body
						);
						return json({ success: 1, data });
					} catch {
						return json({ success: 0, message: ErrorCode.INVALID_DATA });
					}
				}
				// Older clients only supply storage_id and require the original POST/token contract.
				const result = await getUploadUrl({
					apiUrl: authData.apiUrl,
					authorizationToken: authData.authorizationToken,
					bucketId: authData.bucketId
				});
				return result;
			} catch {
				return json({ success: 0, message: ErrorCode.INVALID_DATA });
			}
		}
	);
};
