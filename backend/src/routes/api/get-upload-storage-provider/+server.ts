import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import {
	addTempStorage,
	getCredentials,
	getOptimalStorage,
	getTempStorage,
	getUserFile
} from '$lib/server/db/api';
import {
	CredentialKeys,
	ErrorCode,
	FileKeys,
	StorageKeys,
	TempStorageKeys
} from '$lib/server/db/keys';

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
	const fileRow = await getUserFile(authUser.userId!, file_hash);
	if (!fileRow) {
		return json({ success: 0, message: ErrorCode.NO_DATA });
	}
	const fileId = fileRow[FileKeys.ID];
	const tempStorage = getTempStorage(authUser.userId!, fileId);
	if (tempStorage) {
		return json({
			success: 1,
			data: {
				provider_id: tempStorage[TempStorageKeys.PROVIDER_ID],
				storage_id: tempStorage[TempStorageKeys.STORAGE_ID]
			}
		});
	} else {
		const storage = getOptimalStorage(authUser.userId!, file_size);
		if (storage) {
			const credentialId = storage[StorageKeys.CREDENTIAL_ID];
			const credential = await getCredentials(credentialId);
			if (credential) {
				const providerId = credential[CredentialKeys.PROVIDER_ID];
				const storageId = storage[StorageKeys.ID];
				addTempStorage(authUser.userId!, fileId, storageId, file_size, providerId);
				return json({ success: 1, data: { provider_id: providerId, storage_id: storageId } });
			} else {
				return json({ success: 0, message: ErrorCode.NO_STORAGE });
			}
		} else {
			return json({ success: 0, message: ErrorCode.NO_STORAGE });
		}
	}
};
