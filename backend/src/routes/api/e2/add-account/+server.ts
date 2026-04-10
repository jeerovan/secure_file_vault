import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode, StorageProvider } from '$lib/server/db/keys';
import { S3Client, HeadBucketCommand } from '@aws-sdk/client-s3';
import { addCredentials } from '$lib/server/db/api';

async function verifyR2Credentials(
	bucket: string,
	appId: string,
	appKey: string,
	region: string
): Promise<boolean> {
	const s3Client = new S3Client({
		region: region,
		endpoint: `https://s3.${region}.idrivee2.com`,
		credentials: {
			accessKeyId: appId,
			secretAccessKey: appKey
		},
		forcePathStyle: true
	});

	try {
		// HeadBucket is a lightweight command that checks if the bucket exists
		// and if you have permission to access it
		const command = new HeadBucketCommand({ Bucket: bucket });
		await s3Client.send(command);

		return true;
	} catch (error) {
		return false;
	}
}

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { app_id, app_key, bucket, region } = body;

	if (!app_id || !app_key || !bucket || !region) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const validData = await verifyR2Credentials(bucket, app_id, app_key, region);
	if (validData) {
		const credentials = {
			appId: app_id,
			appKey: app_key,
			bucketName: bucket,
			region: region
		};
		const provider = StorageProvider.IDRIVE;
		await addCredentials(authUser.sid, app_id, credentials, provider);
		return json({ success: 1 });
	} else {
		// TODO flag user with attempt count
		return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
	}
};
