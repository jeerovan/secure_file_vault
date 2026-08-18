import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode, StorageProvider } from '$lib/server/db/keys';
import { addCredentials } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import {
	normalizePublicS3Endpoint,
	verifyGenericS3Credentials,
	type GenericS3Credentials
} from '$lib/server/s3';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}

	let body: Record<string, unknown>;
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { endpoint, region, bucket, app_id, app_key, force_path_style } = body;
	if (
		typeof endpoint !== 'string' ||
		typeof region !== 'string' ||
		typeof bucket !== 'string' ||
		typeof app_id !== 'string' ||
		typeof app_key !== 'string' ||
		!endpoint.trim() ||
		!region.trim() ||
		!bucket.trim() ||
		!app_id.trim() ||
		!app_key
	) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	if (force_path_style !== undefined && typeof force_path_style !== 'boolean') {
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}

	let normalizedEndpoint: string;
	try {
		normalizedEndpoint = normalizePublicS3Endpoint(endpoint);
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}

	const credentials: GenericS3Credentials = {
		endpoint: normalizedEndpoint,
		region: region.trim(),
		bucketName: bucket.trim(),
		appId: app_id.trim(),
		appKey: app_key,
		forcePathStyle: force_path_style ?? true
	};
	if (!(await verifyGenericS3Credentials(credentials))) {
		return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
	}

	await addCredentials(db, authUser.userId!, credentials, StorageProvider.S3);
	return json({ success: 1 });
};
