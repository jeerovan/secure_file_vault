import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { getDb } from '$lib/server/db';
import {
	addTempStorage,
	getCredentials,
	getOptimalStorage,
	getTempStorage,
	getUserFile,
	lockStorageAllocation
} from '$lib/server/db/api';
import {
	CredentialKeys,
	ErrorCode,
	FileKeys,
	StorageKeys,
	TempStorageKeys
} from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_hash, file_size } = body;

	if (!file_hash || !file_size) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const result = await db.transaction(async (tx) => {
		const userId = authUser.userId!;
		await lockStorageAllocation(tx, userId);
		const fileRow = await getUserFile(tx, userId, file_hash);
		if (!fileRow) return { success: 0, message: ErrorCode.NO_DATA };

		const fileId = fileRow[FileKeys.ID];
		const existing = await getTempStorage(tx, userId, fileId);
		if (existing) {
			return {
				success: 1,
				data: {
					provider_id: existing[TempStorageKeys.PROVIDER_ID],
					storage_id: existing[TempStorageKeys.STORAGE_ID]
				}
			};
		}

		const storage = await getOptimalStorage(tx, userId, file_size);
		if (!storage) return { success: 0, message: ErrorCode.NO_STORAGE };
		const credential = await getCredentials(tx, storage[StorageKeys.CREDENTIAL_ID]);
		if (!credential) return { success: 0, message: ErrorCode.NO_STORAGE };

		const providerId = credential[CredentialKeys.PROVIDER_ID];
		const storageId = storage[StorageKeys.ID];
		await addTempStorage(tx, userId, fileId, storageId, file_size, providerId);
		return { success: 1, data: { provider_id: providerId, storage_id: storageId } };
	});

	return json(result);
};
