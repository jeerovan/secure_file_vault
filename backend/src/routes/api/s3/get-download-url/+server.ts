import { GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { getCredentialByStorageId } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { CredentialKeys, ErrorCode, StorageProvider } from '$lib/server/db/keys';
import { createGenericS3Client, type GenericS3Credentials } from '$lib/server/s3';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) return json({ success: 0, message: authUser.message });

	let body: Record<string, unknown>;
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}
	const { file_id, storage_id } = body;
	if (typeof file_id !== 'string' || !file_id || typeof storage_id !== 'number') {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	const credential = await getCredentialByStorageId(db, authUser.userId!, storage_id);
	if (!credential || credential[CredentialKeys.PROVIDER_ID] !== StorageProvider.S3) {
		return json({ success: 0, message: ErrorCode.NO_STORAGE });
	}
	const credentials = credential[CredentialKeys.CREDENTIALS] as GenericS3Credentials;

	try {
		const command = new GetObjectCommand({
			Bucket: credentials.bucketName,
			Key: `${authUser.remoteAuthId}/${file_id}`
		});
		const url = await getSignedUrl(createGenericS3Client(credentials), command, {
			expiresIn: 3600
		});
		return json({ success: 1, data: url });
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}
};
