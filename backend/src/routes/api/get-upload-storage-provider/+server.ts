import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import {
	addTempStorage,
	getCredentialsById,
	getOptimalStorage,
	getTempStorage,
	getUserData
} from '$lib/server/db/api';
import {
	CredentialsKeys,
	ErrorCode,
	StorageKeys,
	TempStorageKeys,
	UserDataKeys
} from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, message: ErrorCode.INVALID_JSON });
	}

	const { file_hash, file_size } = body;

	if (!file_hash || !file_size) {
		return json({ status: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const tempStorage = await getTempStorage(authUser.id, file_hash);
	if (tempStorage) {
		return json({
			status: 1,
			data: {
				provider: tempStorage[TempStorageKeys.PROVIDER],
				storage_id: tempStorage[TempStorageKeys.STORAGE_ID]
			}
		});
	} else {
		const storage = await getOptimalStorage(authUser.id, file_size);
		if (storage) {
			const credentialId = storage[StorageKeys.CREDENTIALS_ID];
			const credential = await getCredentialsById(credentialId);
			if (credential) {
				const provider = credential[CredentialsKeys.PROVIDER];
				const storageId = storage[StorageKeys.ID];
				await addTempStorage(authUser.id, file_hash, storageId, file_size, provider);
				return json({ status: 1, data: { provider, storage_id: storageId } });
			} else {
				return json({ status: 0, message: ErrorCode.NO_STORAGE });
			}
		} else {
			return json({ status: 0, message: ErrorCode.NO_STORAGE });
		}
	}
};
