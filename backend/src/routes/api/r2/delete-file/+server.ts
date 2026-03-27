import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { CredentialsKeys, ErrorCode } from '$lib/server/db/keys';
import { S3Client, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getCredentialsByStorageId } from '$lib/server/db/api';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_id, storage_id } = body;

	if (!file_id) {
		return json({ status: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const credentials = await getCredentialsByStorageId(authUser.id, storage_id);
	if (!credentials) {
		return json({ status: 0, message: ErrorCode.NO_STORAGE });
	}
	const credsData = credentials[CredentialsKeys.CREDENTIALS] as {
		appId: string;
		appKey: string;
		bucketName: string;
	};
	const file_path = `${authUser.id}/${file_id}`;
	const accountId = credentials[CredentialsKeys.ID];
	const s3Endpoint = `https://${accountId}.r2.cloudflarestorage.com`;
	const region = 'auto';
	const s3Client = new S3Client({
		endpoint: s3Endpoint,
		region: region,
		credentials: {
			accessKeyId: credsData.appId,
			secretAccessKey: credsData.appKey
		}
	});
	const command = new DeleteObjectCommand({
		Bucket: credsData.bucketName,
		Key: file_path
	});
	try {
		await s3Client.send(command);
	} catch (e) {
		let error = e;
		if (e instanceof Error) {
			error = e.message;
		}
		return json({ status: 0, message: error });
	}
	return json({ status: 1 });
};
