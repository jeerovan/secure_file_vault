import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireDeviceAuth as requireAuth } from '$lib/server/auth';
import { CredentialKeys, ErrorCode } from '$lib/server/db/keys';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getCredentialByStorageId } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { isVaultPartName } from '$lib/server/recoveryStorage';
import { finalDeviceResponse } from '$lib/server/deviceAccess';
import { getPartObjectKey } from '$lib/server/partObject';

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

	const { file_id, storage_id } = body;
	if (file_id !== undefined && !isVaultPartName(file_id))
		return json({ success: 0, message: ErrorCode.INVALID_DATA });

	if (!file_id) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const credentials = await getCredentialByStorageId(db, authUser.userId!, storage_id);
	if (!credentials) {
		return json({ success: 0, message: ErrorCode.NO_STORAGE });
	}
	const credsData = credentials[CredentialKeys.CREDENTIALS] as {
		appId: string;
		appKey: string;
		bucketName: string;
		namespace: string;
		region: string;
	};

	const s3Endpoint = `https://${credsData.namespace}.compat.objectstorage.${credsData.region}.oraclecloud.com`;
	const s3Client = new S3Client({
		region: credsData.region,
		endpoint: s3Endpoint,
		credentials: {
			accessKeyId: credsData.appId,
			secretAccessKey: credsData.appKey
		},
		forcePathStyle: true
	});

	try {
		const command = new GetObjectCommand({
			Bucket: credsData.bucketName,
			Key: await getPartObjectKey(db, authUser.userId!, storage_id, file_id, authUser.objectPrefix!)
		});
		// Generates the URL purely locally using cryptographic signing
		const presignedUrl = await getSignedUrl(s3Client, command, {
			expiresIn: 3600
		});

		return finalDeviceResponse(db, authUser, json({ success: 1, data: presignedUrl }));
	} catch (e) {
		let error = e;
		if (e instanceof Error) {
			error = e.message;
		}
		return json({ success: 0, message: error });
	}
};
