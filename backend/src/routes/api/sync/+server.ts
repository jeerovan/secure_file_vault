import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import {
	fetchChanges,
	saveFileChanges,
	saveItemChanges,
	savePartChanges
} from '$lib/server/db/api';

// ---------------------------------------------------
// GET /api/user-device
// Returns devices for the currently authenticated user
// ---------------------------------------------------
export const GET: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);
	const deviceId = authUser.did;
	// Fetch query parameters using url.searchParams
	const lastProfilesTimestamp = parseInt(
		url.searchParams.get('last_profiles_changes_fetched_at') || '0',
		10
	);
	const lastFilesTimestamp = parseInt(
		url.searchParams.get('last_files_changes_fetched_at') || '0',
		10
	);
	const lastItemsTimestamp = parseInt(
		url.searchParams.get('last_items_changes_fetched_at') || '0',
		10
	);
	const lastPartsTimestamp = parseInt(
		url.searchParams.get('last_parts_changes_fetched_at') || '0',
		10
	);

	const { profile, fileRows, partRows, itemRows } = await fetchChanges(
		authUser.id,
		deviceId,
		lastProfilesTimestamp,
		lastFilesTimestamp,
		lastItemsTimestamp,
		lastPartsTimestamp
	);

	return json({
		status: 1,
		data: { files: fileRows, parts: partRows, items: itemRows, profiles: profile }
	});
};

// ---------------------------------------------------
// POST /api/user-device
// ---------------------------------------------------
export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	const userId = authUser.id;
	const deviceId = authUser.did;
	if (!deviceId) {
		return json({ status: 0, error: 'Missing required fields: deviceId' });
	}

	try {
		const body = await request.json();
		const { table_maps } = body;
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
	} catch {
		return json({ status: 0, error: 'Invalid JSON body' });
	}

	return json({ status: 1 });
};
