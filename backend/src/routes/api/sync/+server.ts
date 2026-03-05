import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { db } from '$lib/server/db'; // your drizzle db instance
import { userData, file, item, part } from '$lib/server/db/schema';
import { eq, and, count, ne, gte } from 'drizzle-orm';

// ---------------------------------------------------
// GET /api/user-device
// Returns devices for the currently authenticated user
// ---------------------------------------------------
export const GET: RequestHandler = async ({ request, url }) => {
	const authUser = await requireAuth(request);
	const deviceId = authUser.did;
	// Fetch query parameters using url.searchParams
	const last_profiles_changes_fetched_at = parseInt(
		url.searchParams.get('last_profiles_changes_fetched_at') || '0',
		10
	);
	const last_files_changes_fetched_at = parseInt(
		url.searchParams.get('last_files_changes_fetched_at') || '0',
		10
	);
	const last_items_changes_fetched_at = parseInt(
		url.searchParams.get('last_items_changes_fetched_at') || '0',
		10
	);
	const last_parts_changes_fetched_at = parseInt(
		url.searchParams.get('last_parts_changes_fetched_at') || '0',
		10
	);

	const last_profiles_timestamp = new Date(last_profiles_changes_fetched_at);
	const last_files_timestamp = new Date(last_files_changes_fetched_at);
	const last_items_timestamp = new Date(last_items_changes_fetched_at);
	const last_parts_timestamp = new Date(last_parts_changes_fetched_at);

	const profile = db
		.select()
		.from(userData)
		.where(
			and(
				eq(userData[1], authUser.id),
				gte(userData[3], last_profiles_timestamp),
				ne(userData[5], deviceId)
			)
		)
		.get();

	const fileRows = db
		.select()
		.from(file)
		.where(and(eq(file[4], authUser.id), gte(file[3], last_files_timestamp), ne(file[5], deviceId)))
		.limit(300)
		.get();

	const partRows = db
		.select()
		.from(part)
		.where(and(eq(part[4], authUser.id), gte(part[3], last_parts_timestamp), ne(part[5], deviceId)))
		.limit(300)
		.get();

	const itemRows = db
		.select()
		.from(item)
		.where(and(eq(item[4], authUser.id), gte(item[3], last_items_timestamp), ne(item[5], deviceId)))
		.limit(300)
		.get();

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
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: 'Invalid JSON body' });
	}

	const { device_id, title, type, notificationId, active } = body;

	if (!device_id) {
		return json({ status: 0, error: 'Missing required fields: deviceId' });
	}

	return json({ status: 1 });
};
