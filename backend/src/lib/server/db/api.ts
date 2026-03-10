import { json, error } from '@sveltejs/kit';
import { db } from '$lib/server/db';
import { user, userDevice, userData, file, item, part, backblaze } from '$lib/server/db/schema';
import { eq, and, ne, gte, count } from 'drizzle-orm';

export async function getKeys(userId: string) {
	return db
		.select({
			id: user[1],
			cipher: user[5],
			nonce: user[6]
		})
		.from(user)
		.where(eq(user[1], userId))
		.get();
}
export async function addKey(userId: string, email: string, cipher: string, nonce: string) {
	return await db.insert(user).values({
		1: userId,
		4: email,
		5: cipher,
		6: nonce
	});
}
export async function getUserDevices(userId: string) {
	return db
		.select({
			id: userDevice[1],
			lastAt: userDevice[3],
			title: userDevice[5],
			type: userDevice[6],
			active: userDevice[8]
		})
		.from(userDevice)
		.where(eq(userDevice[4], userId))
		.get();
}

export async function addUpdateDevice(
	userId: string,
	tableId: string,
	title: string,
	type: number,
	notificationId: string,
	active: number
) {
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
			.where(and(eq(userDevice[4], userId), eq(userDevice[8], 1)))
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
				4: userId,
				5: title,
				6: type,
				7: notificationId,
				8: 1
			});

			return json({ status: 1, data: 'Device added successfully' });
		}
	}
}

export async function fetchChanges(
	userId: string,
	deviceId: string,
	lastProfilesTimestamp: number,
	lastFilesTimestamp: number,
	lastItemsTimestamp: number,
	lastPartsTimestamp: number
) {
	const profilesTimestamp = new Date(lastProfilesTimestamp);
	const filesTimestamp = new Date(lastFilesTimestamp);
	const itemsTimestamp = new Date(lastItemsTimestamp);
	const partsTimestamp = new Date(lastPartsTimestamp);
	const profileRows = db
		.select()
		.from(userData)
		.where(
			and(eq(userData[1], userId), gte(userData[3], profilesTimestamp), ne(userData[5], deviceId))
		)
		.all();

	const fileRows = db
		.select()
		.from(file)
		.where(and(eq(file[4], userId), gte(file[3], filesTimestamp), ne(file[5], deviceId)))
		.limit(300)
		.all();

	const partRows = db
		.select()
		.from(part)
		.where(and(eq(part[4], userId), gte(part[3], partsTimestamp), ne(part[5], deviceId)))
		.limit(300)
		.all();

	const itemRows = db
		.select()
		.from(item)
		.where(and(eq(item[4], userId), gte(item[3], itemsTimestamp), ne(item[5], deviceId)))
		.limit(300)
		.all();

	return { profileRows, fileRows, partRows, itemRows };
}

export async function saveFileChanges(userId: string, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const fileHash = change['id'];
		const tableKey = userId + '_' + fileHash;
		const incomingUpdatedAt = change['updated_at'] || 0;

		// 1. Check if row exists with tableKey
		const existingRow = await db
			.select({ clientUpdatedAt: file['14'] })
			.from(file)
			.where(eq(file['1'], tableKey))
			.get(); // .get() fetches a single row or undefined in Drizzle SQLite

		if (existingRow) {
			// 2. If exist, check value of column '14' (client updated at)
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				// 3. If incoming updated_at is more recent, update the row
				await db
					.update(file)
					.set({
						'5': deviceId, // Updating deviceId to the latest modifier
						'6': change['item_count'] ?? 0,
						'7': change['parts'] ?? 1,
						'8': change['parts_uploaded'] ?? 0,
						'9': change['uploaded_at'] ?? 0,
						'10': change['uploaded_to'] ?? 0,
						'11': change['remote_id'] ?? null,
						'12': change['access_token'] ?? null,
						'13': change['token_expiry'] ?? 0,
						'14': incomingUpdatedAt,
						'15': change['deleted']
					})
					.where(eq(file['1'], tableKey));
			}
			// 4. Else ignore (do nothing)
		} else {
			// 5. If it does not exist, insert a new row
			await db.insert(file).values({
				'1': tableKey,
				'4': userId,
				'5': deviceId,
				'6': change['item_count'] ?? 0,
				'7': change['parts'] ?? 1,
				'8': change['parts_uploaded'] ?? 0,
				'9': change['uploaded_at'] ?? 0,
				'10': change['uploaded_to'] ?? 0,
				'11': change['remote_id'] ?? null,
				'12': change['access_token'] ?? null,
				'13': change['token_expiry'] ?? 0,
				'14': incomingUpdatedAt,
				'15': change['deleted']
			});
		}
	}
}

export async function savePartChanges(userId: string, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const partId = change['id'];
		const tableKey = userId + '_' + partId;
		const incomingUpdatedAt = change['updated_at'] || 0;

		const existingRow = await db
			.select({ clientUpdatedAt: part['11'] })
			.from(part)
			.where(eq(part['1'], tableKey))
			.get();

		if (existingRow) {
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(part)
					.set({
						'5': deviceId,
						'7': change['state'] ?? 0,
						'11': incomingUpdatedAt,
						'12': change['deleted']
					})
					.where(eq(part['1'], tableKey));
			}
		} else {
			await db.insert(part).values({
				'1': tableKey,
				'4': userId,
				'5': deviceId,
				'6': change['size'] ?? 0,
				'7': change['state'] ?? 1,
				'8': change['cipher'] ?? null,
				'9': change['nonce'] ?? null,
				'10': change['sha1'] ?? null,
				'11': incomingUpdatedAt,
				'12': change['deleted']
			});
		}
	}
}

export async function saveItemChanges(userId: string, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const itemId = change['id'];
		const tableKey = userId + '_' + itemId;
		const incomingUpdatedAt = change['updated_at'] || 0;

		const existingRow = await db
			.select({ clientUpdatedAt: item['10'] })
			.from(item)
			.where(eq(item['1'], tableKey))
			.get();

		if (existingRow) {
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(item)
					.set({
						'5': deviceId,
						'6': change['text_cipher'],
						'7': change['text_nonce'],
						'8': change['key_cipher'],
						'9': change['key_nonce'],
						'10': incomingUpdatedAt
					})
					.where(eq(item['1'], tableKey));
			}
		} else {
			await db.insert(item).values({
				'1': tableKey,
				'4': userId,
				'5': deviceId,
				'6': change['text_cipher'],
				'7': change['text_nonce'],
				'8': change['key_cipher'],
				'9': change['key_nonce'],
				'10': incomingUpdatedAt
			});
		}
	}
}

// --- BACKBLAZE ---
export async function addB2Account(
	UserId: string,
	AppId: string,
	KeyId: string,
	BucketId: string,
	data: any
) {
	const {
		accountId,
		authorizationToken,
		apiInfo: {
			storageApi: { apiUrl, downloadUrl }
		}
	} = data;
	return await db
		.insert(backblaze)
		.values({
			'1': accountId,
			'4': AppId,
			'5': KeyId,
			'6': authorizationToken,
			'8': apiUrl,
			'9': downloadUrl,
			'10': BucketId,
			'11': UserId,
			'12': new Date()
		})
		.onConflictDoUpdate({
			target: backblaze['1'], // The primary key to check for conflicts
			set: {
				'3': new Date(),
				'6': authorizationToken,
				'8': apiUrl,
				'9': downloadUrl,
				'12': new Date()
			}
		});
}

export async function getB2Account(UserId: string) {
	return db.select().from(backblaze).where(eq(backblaze['11'], UserId)).get();
}
export async function markB2TokenUpdating(Id: string) {
	return await db
		.update(backblaze)
		.set({ '7': 1 })
		.where(
			and(
				eq(backblaze['1'], Id),
				eq(backblaze['7'], 0) // Ensure it hasn't been locked by another request in the last millisecond
			)
		)
		.returning();
}
export async function markB2TokenUpdated(Id: string) {
	await db.update(backblaze).set({ '7': 0 }).where(eq(backblaze['1'], Id));
}
export async function updateB2Account(Id: string, data: any) {
	const {
		authorizationToken,
		apiInfo: {
			storageApi: { apiUrl, downloadUrl }
		}
	} = data;
	await db
		.update(backblaze)
		.set({
			'3': new Date(),
			'6': authorizationToken,
			'7': 0,
			'8': apiUrl,
			'9': downloadUrl,
			'12': new Date()
		})
		.where(eq(backblaze['1'], Id));
}
