import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import {
	fetchChanges,
	saveFileChanges,
	saveItemChanges,
	savePartChanges,
	updateDeviceStatus
} from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';
import { getDb } from '$lib/server/db';
import { assertSyncTable } from '$lib/server/syncValidation';

function optionalCursorId(url: URL, name: string): number | null {
	const value = url.searchParams.get(name);
	if (value === null) return null;
	const parsed = parseInt(value, 10);
	return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

export const GET: RequestHandler = async ({ request, url, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	if (!authUser.deviceUuid) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const deviceUuid = authUser.deviceUuid;
	// Fetch query parameters using url.searchParams
	const lastProfilesTS = parseInt(url.searchParams.get('last_profile_ts') || '0', 10);
	const lastProfileId = optionalCursorId(url, 'last_profile_id');
	const lastFilesTS = parseInt(url.searchParams.get('last_file_ts') || '0', 10);
	const lastFileId = optionalCursorId(url, 'last_file_id');
	const lastItemsTS = parseInt(url.searchParams.get('last_item_ts') || '0', 10);
	const lastItemId = optionalCursorId(url, 'last_item_id');
	const lastPartsTS = parseInt(url.searchParams.get('last_part_ts') || '0', 10);
	const lastPartId = optionalCursorId(url, 'last_part_id');

	const { profileRows, fileRows, partRows, itemRows } = await fetchChanges(
		db,
		authUser.userId!,
		deviceUuid,
		lastProfilesTS,
		lastProfileId,
		lastFilesTS,
		lastFileId,
		lastItemsTS,
		lastItemId,
		lastPartsTS,
		lastPartId
	);

	return json({
		success: 1,
		data: { files: fileRows, parts: partRows, items: itemRows, profiles: profileRows }
	});
};

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	const userId = authUser.userId!;
	const deviceUuid = authUser.deviceUuid;
	if (!deviceUuid) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	try {
		const { table_maps } = await request.json();
		for (const { table, changes } of table_maps) {
			assertSyncTable(table);
			switch (table) {
				case 'files':
					await saveFileChanges(db, userId, deviceUuid, changes);
					break;
				case 'items':
					await saveItemChanges(db, userId, deviceUuid, changes);
					break;
				case 'parts':
					await savePartChanges(db, userId, deviceUuid, changes);
					break;
			}
		}
		await updateDeviceStatus(db, userId, deviceUuid, 1);
	} catch (error) {
		if (error instanceof Error) {
			console.log(error.stack);
		}
		return json({ success: 0, message: error });
	}

	return json({ success: 1 });
};
