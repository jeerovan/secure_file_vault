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

export const GET: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);
	const deviceUuid = authUser.deviceUuid;
	// Fetch query parameters using url.searchParams
	const lastProfilesTS = parseInt(url.searchParams.get('last_profile_ts') || '0', 10);
	const lastFilesTS = parseInt(url.searchParams.get('last_file_ts') || '0', 10);
	const lastItemsTS = parseInt(url.searchParams.get('last_item_ts') || '0', 10);
	const lastPartsTS = parseInt(url.searchParams.get('last_part_ts') || '0', 10);

	const { profileRows, fileRows, partRows, itemRows } = await fetchChanges(
		authUser.userId!,
		deviceUuid,
		lastProfilesTS,
		lastFilesTS,
		lastItemsTS,
		lastPartsTS
	);

	return json({
		success: 1,
		data: { files: fileRows, parts: partRows, items: itemRows, profiles: profileRows }
	});
};

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	const userId = authUser.userId!;
	const deviceUuid = authUser.deviceUuid;
	if (!deviceUuid) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}

	try {
		const { table_maps } = await request.json();
		for (const { table, changes } of table_maps) {
			switch (table) {
				case 'files':
					await saveFileChanges(userId, deviceUuid, changes);
					break;
				case 'items':
					await saveItemChanges(userId, deviceUuid, changes);
					break;
				case 'parts':
					await savePartChanges(userId, deviceUuid, changes);
					break;
				default:
					break;
			}
		}
		await updateDeviceStatus(userId, deviceUuid, 1); // This will set device active time
	} catch (e) {
		return json({ success: 0, message: e });
	}

	return json({ success: 1 });
};
