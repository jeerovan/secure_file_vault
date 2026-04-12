import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ErrorCode, FileKeys } from '$lib/server/db/keys';
import { db } from '$lib/server/db';
import { file } from '$lib/server/db/schema';
import { eq } from 'drizzle-orm';
import { deleteFileFromStorage } from '$lib/server/deleteWorker';

export const DELETE: RequestHandler = async ({ request, url }) => {
	let id = url.searchParams.get('id');

	if (!id) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const fileId = parseInt(id);
	const fileRow = db.select().from(file).where(eq(file[FileKeys.ID], fileId)).get();
	deleteFileFromStorage(fileRow);
	return json({ success: 1 });
};
