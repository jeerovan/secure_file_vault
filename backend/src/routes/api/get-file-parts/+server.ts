import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { getDb } from '$lib/server/db';
import { getUserFile, getUserFilePart } from '$lib/server/db/api';
import { ErrorCode, FileKeys } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
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
	const fileRow = await getUserFile(db, authUser.userId!, file_hash);
	if (fileRow) {
		if (fileRow[FileKeys.UPLOADED_AT] > 0) {
			const parts = [];
			const partNumbers = Array.from({ length: fileRow[FileKeys.PARTS] }, (_, i) => i + 1);
			for (const index in partNumbers) {
				const partNumber = partNumbers[index];
				const filePart = await getUserFilePart(
					db,
					authUser.userId!,
					fileRow[FileKeys.ID],
					partNumber
				);
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
