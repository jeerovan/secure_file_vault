import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { ErrorCode, StorageProvider, UserKeys } from '$lib/server/db/keys';
import { addUser, getUser } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { env } from '$env/dynamic/private';
import { getLocalTestS3Credentials } from '$lib/server/localTest';
import { verifyGenericS3Credentials } from '$lib/server/s3';

export const GET: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	if (!authUser.userId) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	const user = await getUser(db, authUser.userId);
	if (!user) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}

	return json({ success: 1, data: { cipher: user[UserKeys.CIPHER], nonce: user[UserKeys.NONCE] } });
};

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (authUser.message == ErrorCode.UNAUTHORIZED) {
		return json({ success: 0, message: authUser.message });
	}
	let body: { cipher?: string; nonce?: string };
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { cipher, nonce } = body;

	if (!cipher || !nonce) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	if (authUser.authorized) {
		const existingUser = authUser.userId ? await getUser(db, authUser.userId) : undefined;
		if (existingUser?.[UserKeys.CIPHER] === cipher && existingUser[UserKeys.NONCE] === nonce) {
			return json({ success: 1 });
		}
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}

	let initialStorage;
	if (authUser.localTesting) {
		try {
			const credentials = getLocalTestS3Credentials(env);
			if (!(await verifyGenericS3Credentials(credentials))) {
				return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
			}
			initialStorage = {
				providerId: StorageProvider.S3,
				credentials
			};
		} catch (error) {
			console.error('Local S3 configuration failed', error);
			return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
		}
	}

	const result = await addUser(
		db,
		authUser.remoteAuthId!,
		authUser.email!,
		cipher,
		nonce,
		initialStorage
	);

	return json({ success: 1, data: result });
};
