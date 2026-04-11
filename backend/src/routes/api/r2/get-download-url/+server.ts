import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { CredentialKeys, ErrorCode } from '$lib/server/db/keys';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getCredentialByStorageId } from '$lib/server/db/api';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_id, storage_id } = body;

	if (!file_id) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const credentials = await getCredentialByStorageId(authUser.userId!, storage_id);
	if (!credentials) {
		return json({ success: 0, message: ErrorCode.NO_STORAGE });
	}
	const credsData = credentials[CredentialKeys.CREDENTIALS] as {
		accountId: string;
		appId: string;
		appKey: string;
		bucketName: string;
	};
	const file_path = `${authUser.supabaseId}/${file_id}`;
	const s3Endpoint = `https://${credsData.accountId}.r2.cloudflarestorage.com`;
	const region = 'auto';
	const s3Client = new S3Client({
		endpoint: s3Endpoint,
		region: region,
		credentials: {
			accessKeyId: credsData.appId,
			secretAccessKey: credsData.appKey
		}
	});
	const command = new GetObjectCommand({
		Bucket: credsData.bucketName,
		Key: file_path
	});

	try {
		// Generates the URL purely locally using cryptographic signing
		const presignedUrl = await getSignedUrl(s3Client, command, {
			expiresIn: 3600
		});

		return json({ success: 1, data: presignedUrl });
	} catch (e) {
		let error = e;
		if (e instanceof Error) {
			error = e.message;
		}
		return json({ success: 0, message: error });
	}
};
