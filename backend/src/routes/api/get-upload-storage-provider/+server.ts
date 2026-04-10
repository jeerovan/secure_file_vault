import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import {
	addTempStorage,
	getCredentials,
	getOptimalStorage,
	getTempStorage
} from '$lib/server/db/api';
import { CredentialKeys, ErrorCode, StorageKeys, TempStorageKeys } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
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
	const tempStorage = await getTempStorage(authUser.id!, file_hash);
	if (tempStorage) {
		return json({
			success: 1,
			data: {
				provider_id: tempStorage[TempStorageKeys.PROVIDER_ID],
				storage_id: tempStorage[TempStorageKeys.STORAGE_ID]
			}
		});
	} else {
		const storage = await getOptimalStorage(authUser.id!, file_size);
		if (storage) {
			const credentialId = storage[StorageKeys.CREDENTIAL_ID];
			const credential = await getCredentials(credentialId);
			if (credential) {
				const providerId = credential[CredentialKeys.PROVIDER_ID];
				const storageId = storage[StorageKeys.ID];
				await addTempStorage(authUser.id!, file_hash, storageId, file_size, providerId);
				return json({ success: 1, data: { provider_id: providerId, storage_id: storageId } });
			} else {
				return json({ success: 0, message: ErrorCode.NO_STORAGE });
			}
		} else {
			return json({ success: 0, message: ErrorCode.NO_STORAGE });
		}
	}
};
