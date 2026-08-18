import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { deleteUser, getUserCredential } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { CredentialKeys, ErrorCode, StorageProvider } from '$lib/server/db/keys';
import { deleteLocalTestObjects } from '$lib/server/localTest';
import type { GenericS3Credentials } from '$lib/server/s3';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request, platform?.env.FIFE_AUTH_CACHE);
	if (!authUser.authorized || !authUser.localTesting || !authUser.userId) {
		return json({ success: 0, message: authUser.message ?? ErrorCode.UNAUTHORIZED });
	}

	try {
		const credential = await getUserCredential(db, authUser.userId, StorageProvider.S3);
		if (credential) {
			await deleteLocalTestObjects(
				credential[CredentialKeys.CREDENTIALS] as GenericS3Credentials,
				authUser.remoteAuthId!
			);
		}
		await deleteUser(db, authUser.userId);
		return json({ success: 1 });
	} catch (error) {
		console.error('Failed to reset local integration profile', error);
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}
};
