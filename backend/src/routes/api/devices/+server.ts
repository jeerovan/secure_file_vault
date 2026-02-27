import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { db } from '$lib/server/db'; // your drizzle db instance
import { userDevice } from '$lib/server/db/schema';
import { eq, and, count } from 'drizzle-orm';

// ---------------------------------------------------
// GET /api/user-device
// Returns devices for the currently authenticated user
// ---------------------------------------------------
export const GET: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	const result = db.select().from(userDevice).where(eq(userDevice.userId, authUser.id)).get();

	return json({ status: 1, data: result });
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

	const { deviceId, title, type, notificationId, status } = body;

	if (!deviceId) {
		return json({ status: 0, error: 'Missing required fields: deviceId' });
	}

	const tableId = authUser.id + '_' + deviceId;

	// Check if the device already exists for this user
	const deviceRow = db.select().from(userDevice).where(eq(userDevice.id, tableId)).get();

	if (deviceRow) {
		// Device exists: update column with received values
		//  update the last active timestamp
		await db
			.update(userDevice)
			.set({
				title: title ?? deviceRow.title,
				type: type ?? deviceRow.type,
				notificationId: notificationId ?? deviceRow.notificationId,
				status: status ?? deviceRow.status,
				lastActiveAt: new Date().getUTCMilliseconds()
			})
			.where(eq(userDevice.id, tableId));

		return json({ status: 1, data: 'Device updated successfully' });
	} else {
		// Device doesn't exist: fetch current active devices count
		const result = db
			.select({ count: count() })
			.from(userDevice)
			.where(and(eq(userDevice.userId, authUser.id), eq(userDevice.status, 1)))
			.get();

		const activeDevicesCount = result?.count ?? 0;

		if (activeDevicesCount >= 5) {
			return json({ status: 0, error: 'Max 5 active devices only' });
		} else {
			// Require title and type for a new device insertion
			if (!title || type === undefined) {
				return json({ status: 0, error: 'Missing required fields for new device: title, type' });
			}

			// Insert new device with values
			await db.insert(userDevice).values({
				id: tableId,
				userId: authUser.id,
				title: title,
				type: type,
				notificationId: notificationId,
				status: 1,
				lastActiveAt: new Date().getUTCMilliseconds()
			});

			return json({ status: 1, data: 'Device added successfully' });
		}
	}
};
