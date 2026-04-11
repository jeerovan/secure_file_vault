import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import {
	addTempStorage,
	getCredentials,
	getUserFile,
	getUserFilePart,
	getOptimalStorage,
	getTempStorage
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

	const { file_hash } = body;

	if (!file_hash) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const fileRow = await getUserFile(authUser.userId!, file_hash);
	if (fileRow) {
		if (fileRow[FileKeys.UPLOADED_AT] > 0) {
			const parts = [];
			const partNumbers = Array.from({ length: fileRow[FileKeys.PARTS] }, (_, i) => i + 1);
			for (const index in partNumbers) {
				const partNumber = partNumbers[index];
				const filePart = await getUserFilePart(authUser.userId!, fileRow[FileKeys.ID], partNumber);
				if (filePart) {
					parts.push(filePart);
				}
			}
			return json({ success: 1, data: { file: fileRow, parts } });
		} else {
			return json({ success: 0, message: ErrorCode.NO_DATA });
		}
	} else {
		return json({ success: 0, message: ErrorCode.NO_DATA });
	}
};
