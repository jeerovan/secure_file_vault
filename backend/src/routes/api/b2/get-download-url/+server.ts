import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authenticate, getDownloadAuthorization } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

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
	const authData = await authenticate(authUser.id, storage_id);
	if (!authData) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	const file_path = `${authUser.id}/${file_id}`;
	const s3Endpoint = authData.s3ApiUrl;
	const region = extractRegion(s3Endpoint);
	const s3Client = new S3Client({
		endpoint: s3Endpoint,
		region: region,
		credentials: {
			accessKeyId: authData.appId,
			secretAccessKey: authData.appKey
		}
	});
	const command = new GetObjectCommand({
		Bucket: authData.bucketName,
		Key: file_path
	});

	// Generates the URL purely locally using cryptographic signing
	const presignedUrl = await getSignedUrl(s3Client, command, {
		expiresIn: 3600
	});

	return json({ success: 1, data: presignedUrl });
};

function extractRegion(url: string): string {
	const { hostname } = new URL(url);

	const parts = hostname.split('.');
	return parts[1];
}
