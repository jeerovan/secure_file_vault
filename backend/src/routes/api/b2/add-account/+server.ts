import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireDeviceAuth as requireAuth } from '$lib/server/auth';
import { authorize, addAccount } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';
import { getDb } from '$lib/server/db';
import { withDeviceWrite } from '$lib/server/deviceAccess';
import {
	BackblazeCredentialError,
	backblazeCredentialsFromAuthorization
} from '$lib/server/backblazeCredentials';
import { verifyGenericS3Credentials } from '$lib/server/s3';

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

	const { app_id, app_key } = body ?? {};

	if (typeof app_id !== 'string' || !app_id.trim() || typeof app_key !== 'string' || !app_key) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	const { data } = await authorize(app_id, app_key);
	if (!data) return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
	try {
		const credentials = backblazeCredentialsFromAuthorization(app_id, app_key, data);
		if (!(await verifyGenericS3Credentials(credentials))) {
			return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
		}
		return await withDeviceWrite(db, authUser, (tx) =>
			addAccount(tx, authUser.userId!, app_id, app_key, data)
		);
	} catch (error) {
		if (error instanceof BackblazeCredentialError) {
			return json({ success: 0, message: error.code });
		}
		throw error;
	}
};
