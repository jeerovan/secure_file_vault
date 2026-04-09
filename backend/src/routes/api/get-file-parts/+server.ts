import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';

import {
	addTempStorage,
	getCredentialsById,
	getFile,
	getFilePart,
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
	const file = await getFile(authUser.id, file_hash);
	if (file) {
		if (file[FileKeys.UPLOADED_AT] > 0) {
			const parts = [];
			const partIds = Array.from({ length: file[FileKeys.PARTS] }, (_, i) => `${i + 1}`);
			for (const index in partIds) {
				const partId = partIds[index];
				const partKey = `${authUser.id}_${file_hash}_${partId}`;
				const filePart = await getFilePart(partKey);
				if (filePart) {
					parts.push(filePart);
				}
			}
			return json({ success: 1, data: { file, parts } });
		} else {
			return json({ success: 0, message: ErrorCode.NO_DATA });
		}
	} else {
		return json({ success: 0, message: ErrorCode.NO_DATA });
	}
};
