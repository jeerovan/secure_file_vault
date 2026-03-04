import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { db } from '$lib/server/db'; // your drizzle db instance
import { userData, file, item, part } from '$lib/server/db/schema';
import { eq, and, count } from 'drizzle-orm';

// ---------------------------------------------------
// GET /api/user-device
// Returns devices for the currently authenticated user
// ---------------------------------------------------
export const GET: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	const fileRows = db.select().from(file).where(eq(file[4], authUser.id)).limit(300).get();

	const partRows = db.select().from(part).where(eq(part[4], authUser.id)).limit(300).get();

	const itemRows = db.select().from(item).where(eq(item[4], authUser.id)).limit(300).get();

	return json({ status: 1, data: { files: fileRows, parts: partRows, items: itemRows } });
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
