import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import {
	fetchChanges,
	saveFileChanges,
	saveItemChanges,
	savePartChanges
} from '$lib/server/db/api';
import { ErrorCode } from '$lib/server/db/keys';

export const GET: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);
	const deviceId = authUser.did;
	// Fetch query parameters using url.searchParams
	const lastProfilesTS = parseInt(url.searchParams.get('last_profile_ts') || '0', 10);
	const lastFilesTS = parseInt(url.searchParams.get('last_file_ts') || '0', 10);
	const lastItemsTS = parseInt(url.searchParams.get('last_item_ts') || '0', 10);
	const lastPartsTS = parseInt(url.searchParams.get('last_part_ts') || '0', 10);

	const { profileRows, fileRows, partRows, itemRows } = await fetchChanges(
		authUser.id,
		deviceId,
		lastProfilesTS,
		lastFilesTS,
		lastItemsTS,
		lastPartsTS
	);

	return json({
		status: 1,
		data: { files: fileRows, parts: partRows, items: itemRows, profiles: profileRows }
	});
};

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	const userId = authUser.id;
	const deviceId = authUser.did;
	if (!deviceId) {
		return json({ status: 0, message: ErrorCode.MISSING_FIELDS });
	}

	try {
		const { table_maps } = await request.json();
		for (const { table, changes } of table_maps) {
			switch (table) {
				case 'files':
					await saveFileChanges(userId, deviceId, changes);
					break;
				case 'items':
					await saveItemChanges(userId, deviceId, changes);
					break;
				case 'parts':
					await savePartChanges(userId, deviceId, changes);
					break;
				default:
					break;
			}
		}
	} catch (e) {
		return json({ status: 0, message: e });
	}

	return json({ status: 1 });
};
