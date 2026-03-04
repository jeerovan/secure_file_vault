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

	const result = db
		.select({
			id: userDevice[1],
			lastAt: userDevice[3],
			title: userDevice[5],
			type: userDevice[6],
			active: userDevice[8]
		})
		.from(userDevice)
		.where(eq(userDevice[4], authUser.id))
		.get();

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

	const { device_id, title, type, notificationId, active } = body;

	if (!device_id) {
		return json({ status: 0, error: 'Missing required fields: deviceId' });
	}

	const tableId = authUser.id + '_' + device_id;

	// Check if the device already exists for this user
	const deviceRow = db.select().from(userDevice).where(eq(userDevice[1], tableId)).get();

	if (deviceRow) {
		// Device exists: update column with received values
		//  update the last active timestamp
		await db
			.update(userDevice)
			.set({
				5: title ?? deviceRow[5],
				6: type ?? deviceRow[6],
				7: notificationId ?? deviceRow[7],
				8: active ?? deviceRow[8]
			})
			.where(eq(userDevice[1], tableId));

		return json({ status: 1, data: 'Device updated successfully' });
	} else {
		// Device doesn't exist: fetch current active devices count
		const result = db
			.select({ count: count() })
			.from(userDevice)
			.where(and(eq(userDevice[4], authUser.id), eq(userDevice[8], 1)))
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
				1: tableId,
				4: authUser.id,
				5: title,
				6: type,
				7: notificationId,
				8: 1
			});

			return json({ status: 1, data: 'Device added successfully' });
		}
	}
};
