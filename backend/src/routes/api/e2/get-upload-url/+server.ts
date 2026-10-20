import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireDeviceAuth as requireAuth } from '$lib/server/auth';
import { CredentialKeys, ErrorCode, StorageProvider } from '$lib/server/db/keys';
import { PRESIGNED_UPLOAD_EXPIRY_SECONDS, presignS3UploadUrl } from '$lib/server/s3';
import { getCredentialByStorageId } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { isVaultPartName } from '$lib/server/recoveryStorage';
import { withUploadAuthorization } from '$lib/server/uploadCapability';

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
	const { file_id, storage_id } = body;
	if (file_id !== undefined && !isVaultPartName(file_id))
		return json({ success: 0, message: ErrorCode.INVALID_DATA });

	if (
		!file_id ||
		typeof storage_id !== 'number' ||
		!Number.isSafeInteger(storage_id) ||
		storage_id <= 0
	) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	return withUploadAuthorization(
		db,
		authUser,
		PRESIGNED_UPLOAD_EXPIRY_SECONDS,
		async (tx, current) => {
			const credentials = await getCredentialByStorageId(tx, current.userId!, storage_id);
			if (!credentials || credentials[CredentialKeys.PROVIDER_ID] !== StorageProvider.IDRIVE) {
				return json({ success: 0, message: ErrorCode.NO_STORAGE });
			}
			const credsData = credentials[CredentialKeys.CREDENTIALS] as {
				appId: string;
				appKey: string;
				bucketName: string;
				region: string;
			};
			const file_path = `${current.objectPrefix}${file_id}`;
			const s3Endpoint = `https://s3.${credsData.region}.idrivee2.com`;
			try {
				const presignedUrl = await presignS3UploadUrl(
					{ ...credsData, endpoint: s3Endpoint, forcePathStyle: true },
					file_path
				);

				return json({ success: 1, data: presignedUrl });
			} catch {
				return json({ success: 0, message: ErrorCode.INVALID_DATA });
			}
		}
	);
};
