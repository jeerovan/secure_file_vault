import { db } from '$lib/server/db'; // your drizzle db instance
import { userData, file, item, part } from '$lib/server/db/schema';
import { eq, and, ne, gte } from 'drizzle-orm';

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
