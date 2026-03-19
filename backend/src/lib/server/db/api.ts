import { json, error } from '@sveltejs/kit';
import { db } from '$lib/server/db';
import {
	user,
	userDevice,
	userData,
	file,
	item,
	part,
	credentials,
	storage,
	tempStorage
} from '$lib/server/db/schema';
import { eq, and, ne, gte, count, desc, sql } from 'drizzle-orm';
import {
	UserKeys,
	UserDeviceKeys,
	UserDataKeys,
	FileKeys,
	PartKeys,
	ItemKeys,
	CredentialsKeys,
	StorageKeys,
	ErrorCode,
	StorageProvider,
	TempStorageKeys
} from '$lib/server/db/keys';
import { table } from 'console';

export async function getKeys(userId: string) {
	return db
		.select({
			id: user[UserKeys.ID],
			cipher: user[UserKeys.CIPHER],
			nonce: user[UserKeys.NONCE]
		})
		.from(user)
		.where(eq(user[UserKeys.ID], userId))
		.get();
}

export async function addKey(userId: string, email: string, cipher: string, nonce: string) {
	// add default fife 5 gb storage for this user
	const fifeCredentials = await getCredentials('fife', StorageProvider.BACKBLAZE);
	if (fifeCredentials) {
		await addStorage(userId, fifeCredentials[CredentialsKeys.ID], 5368709120, 1);
	}

	return await db.insert(user).values({
		[UserKeys.ID]: userId,
		[UserKeys.EMAIL]: email,
		[UserKeys.CIPHER]: cipher,
		[UserKeys.NONCE]: nonce
	});
}

export async function getUserDevices(userId: string) {
	return db
		.select({
			id: userDevice[UserDeviceKeys.ID],
			lastAt: userDevice[UserDeviceKeys.SERVER_UPDATED_AT],
			title: userDevice[UserDeviceKeys.TITLE],
			type: userDevice[UserDeviceKeys.DEVICE_TYPE],
			active: userDevice[UserDeviceKeys.STATUS]
		})
		.from(userDevice)
		.where(eq(userDevice[UserDeviceKeys.USER_ID], userId))
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
	const deviceRow = db
		.select()
		.from(userDevice)
		.where(eq(userDevice[UserDeviceKeys.ID], tableId))
		.get();

	if (deviceRow) {
		await db
			.update(userDevice)
			.set({
				[UserDeviceKeys.TITLE]: title ?? deviceRow[UserDeviceKeys.TITLE],
				[UserDeviceKeys.DEVICE_TYPE]: type ?? deviceRow[UserDeviceKeys.DEVICE_TYPE],
				[UserDeviceKeys.NOTIFICATION_ID]:
					notificationId ?? deviceRow[UserDeviceKeys.NOTIFICATION_ID],
				[UserDeviceKeys.STATUS]: active ?? deviceRow[UserDeviceKeys.STATUS]
			})
			.where(eq(userDevice[UserDeviceKeys.ID], tableId));

		return json({ status: 1 });
	} else {
		const result = db
			.select({ count: count() })
			.from(userDevice)
			.where(
				and(
					eq(userDevice[UserDeviceKeys.USER_ID], userId),
					eq(userDevice[UserDeviceKeys.STATUS], 1)
				)
			)
			.get();

		const activeDevicesCount = result?.count ?? 0;

		if (activeDevicesCount >= 5) {
			return json({ status: 0, error: ErrorCode.DEVICE_LIMIT_REACHED });
		} else {
			if (!title || type === undefined) {
				return json({ status: 0, error: ErrorCode.MISSING_FIELDS });
			}

			await db.insert(userDevice).values({
				[UserDeviceKeys.ID]: tableId,
				[UserDeviceKeys.USER_ID]: userId,
				[UserDeviceKeys.TITLE]: title,
				[UserDeviceKeys.DEVICE_TYPE]: type,
				[UserDeviceKeys.NOTIFICATION_ID]: notificationId,
				[UserDeviceKeys.STATUS]: 1
			});

			return json({ status: 1 });
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
			and(
				eq(userData[UserDataKeys.ID], userId),
				gte(userData[UserDataKeys.SERVER_UPDATED_AT], profilesTimestamp),
				ne(userData[UserDataKeys.DEVICE_ID], deviceId)
			)
		)
		.all();

	const fileRows = db
		.select()
		.from(file)
		.where(
			and(
				eq(file[FileKeys.USER_ID], userId),
				gte(file[FileKeys.SERVER_UPDATED_AT], filesTimestamp),
				ne(file[FileKeys.DEVICE_ID], deviceId)
			)
		)
		.limit(300)
		.all();

	const partRows = db
		.select()
		.from(part)
		.where(
			and(
				eq(part[PartKeys.USER_ID], userId),
				gte(part[PartKeys.SERVER_UPDATED_AT], partsTimestamp),
				ne(part[PartKeys.DEVICE_ID], deviceId)
			)
		)
		.limit(300)
		.all();

	const itemRows = db
		.select()
		.from(item)
		.where(
			and(
				eq(item[ItemKeys.USER_ID], userId),
				gte(item[ItemKeys.SERVER_UPDATED_AT], itemsTimestamp),
				ne(item[ItemKeys.DEVICE_ID], deviceId)
			)
		)
		.limit(300)
		.all();

	return { profileRows, fileRows, partRows, itemRows };
}

export async function saveFileChanges(userId: string, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const fileHash = change['id'];
		const tableKey = userId + '_' + fileHash;
		const incomingUpdatedAt = change['updated_at'] || 0;

		const existingRow = db
			.select({ clientUpdatedAt: file[FileKeys.CLIENT_UPDATED_AT] })
			.from(file)
			.where(eq(file[FileKeys.ID], tableKey))
			.get();

		if (existingRow) {
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(file)
					.set({
						[FileKeys.DEVICE_ID]: deviceId,
						[FileKeys.ITEMS_COUNT]: change['item_count'] ?? 0,
						[FileKeys.PARTS]: change['parts'] ?? 1,
						[FileKeys.PARTS_UPLOADED]: change['parts_uploaded'] ?? 0,
						[FileKeys.UPLOADED_AT]: change['uploaded_at'] ?? 0,
						[FileKeys.PROVIDER]: change['provider'] ?? 0,
						[FileKeys.STORAGE_ID]: change['storage_id'] ?? null,
						[FileKeys.JSON]: change['access_data'] ?? null,
						[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
						[FileKeys.DELETED]: change['deleted']
					})
					.where(eq(file[FileKeys.ID], tableKey));
			}
		} else {
			await db.insert(file).values({
				[FileKeys.ID]: tableKey,
				[FileKeys.USER_ID]: userId,
				[FileKeys.DEVICE_ID]: deviceId,
				[FileKeys.ITEMS_COUNT]: change['item_count'] ?? 0,
				[FileKeys.PARTS]: change['parts'] ?? 1,
				[FileKeys.PARTS_UPLOADED]: change['parts_uploaded'] ?? 0,
				[FileKeys.UPLOADED_AT]: change['uploaded_at'] ?? 0,
				[FileKeys.STORAGE_ID]: change['storage_id'] ?? null,
				[FileKeys.PROVIDER]: change['provider'] ?? 0,
				[FileKeys.JSON]: change['access_data'] ?? null,
				[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
				[FileKeys.DELETED]: change['deleted']
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
			.select({ clientUpdatedAt: part[PartKeys.CLIENT_UPDATED_AT] })
			.from(part)
			.where(eq(part[PartKeys.ID], tableKey))
			.get();

		if (existingRow) {
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(part)
					.set({
						[PartKeys.DEVICE_ID]: deviceId,
						[PartKeys.STATE]: change['state'] ?? 0,
						[PartKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
						[PartKeys.DELETED]: change['deleted']
					})
					.where(eq(part[PartKeys.ID], tableKey));
			}
		} else {
			await db.insert(part).values({
				[PartKeys.ID]: tableKey,
				[PartKeys.USER_ID]: userId,
				[PartKeys.DEVICE_ID]: deviceId,
				[PartKeys.PART_SIZE]: change['size'] ?? 0,
				[PartKeys.STATE]: change['state'] ?? 1,
				[PartKeys.CIPHER]: change['cipher'] ?? null,
				[PartKeys.NONCE]: change['nonce'] ?? null,
				[PartKeys.JSON]: change['sha1'] ?? null,
				[PartKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
				[PartKeys.DELETED]: change['deleted']
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
			.select({ clientUpdatedAt: item[ItemKeys.CLIENT_UPDATED_AT] })
			.from(item)
			.where(eq(item[ItemKeys.ID], tableKey))
			.get();

		if (existingRow) {
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(item)
					.set({
						[ItemKeys.DEVICE_ID]: deviceId,
						[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
						[ItemKeys.TEXT_NONCE]: change['text_nonce'],
						[ItemKeys.KEY_CIPHER]: change['key_cipher'],
						[ItemKeys.KEY_NONCE]: change['key_nonce'],
						[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
					})
					.where(eq(item[ItemKeys.ID], tableKey));
			}
		} else {
			await db.insert(item).values({
				[ItemKeys.ID]: tableKey,
				[ItemKeys.USER_ID]: userId,
				[ItemKeys.DEVICE_ID]: deviceId,
				[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
				[ItemKeys.TEXT_NONCE]: change['text_nonce'],
				[ItemKeys.KEY_CIPHER]: change['key_cipher'],
				[ItemKeys.KEY_NONCE]: change['key_nonce'],
				[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
			});
		}
	}
}

export async function addCredentials(
	userId: string,
	accountId: string,
	credentialsData: any,
	provider: number
) {
	const existingEntry = db
		.select()
		.from(credentials)
		.where(eq(credentials[CredentialsKeys.ID], accountId))
		.get();

	if (!existingEntry) {
		await db.insert(credentials).values({
			[CredentialsKeys.ID]: accountId,
			[CredentialsKeys.OWNER_ID]: userId,
			[CredentialsKeys.PROVIDER]: provider,
			[CredentialsKeys.CREDENTIALS]: credentialsData
		});

		if (provider != StorageProvider.FIFE) {
			let priority = 10;
			if (provider == StorageProvider.CLOUDFLARE) {
				priority = 9;
			}
			await addStorage(userId, accountId, 10737418240, priority);
		}
	} else {
		await db
			.update(credentials)
			.set({
				[CredentialsKeys.SERVER_UPDATED_AT]: new Date(),
				[CredentialsKeys.CREDENTIALS]: credentialsData
			})
			.where(eq(credentials[CredentialsKeys.ID], accountId));
	}
}

export async function getCredentials(userId: string, provider: number) {
	return db
		.select()
		.from(credentials)
		.where(
			and(
				eq(credentials[CredentialsKeys.OWNER_ID], userId),
				eq(credentials[CredentialsKeys.PROVIDER], provider)
			)
		)
		.get();
}
export async function getCredentialsById(id: string) {
	return db.select().from(credentials).where(eq(credentials[CredentialsKeys.ID], id)).get();
}

export async function markCredentialsUpdating(Id: string) {
	return await db
		.update(credentials)
		.set({ [CredentialsKeys.UPDATING]: 1 })
		.where(
			and(eq(credentials[CredentialsKeys.ID], Id), eq(credentials[CredentialsKeys.UPDATING], 0))
		)
		.returning();
}

export async function markCredentialsUpdated(Id: string) {
	await db
		.update(credentials)
		.set({ [CredentialsKeys.UPDATING]: 0 })
		.where(eq(credentials[CredentialsKeys.ID], Id));
}

export async function updateCredentials(accountId: string, creds: any) {
	await db
		.update(credentials)
		.set({
			[CredentialsKeys.SERVER_UPDATED_AT]: new Date(),
			[CredentialsKeys.CREDENTIALS]: creds,
			[CredentialsKeys.UPDATING]: 0
		})
		.where(eq(credentials[CredentialsKeys.ID], accountId));
}

export async function addStorage(
	userId: string,
	accountId: string,
	storageLimit: number,
	priority: number = 0
) {
	return await db.insert(storage).values({
		[StorageKeys.USER_ID]: userId,
		[StorageKeys.CREDENTIALS_ID]: accountId,
		[StorageKeys.LIMIT_BYTES]: storageLimit,
		[StorageKeys.PRIORITY]: priority
	});
}
export async function getStorageById(id: string) {
	return db.select().from(storage).where(eq(storage[StorageKeys.ID], id)).get();
}
export async function getOptimalStorage(userId: string, fileSizeBytes: number) {
	// Subquery to sum the size of all pending files for a specific storage provider
	// COALESCE is used to return 0 instead of NULL if there are no pending files
	const pendingReservedBytes = sql`(
        SELECT COALESCE(SUM(${tempStorage[TempStorageKeys.SIZE]}), 0) 
        FROM ${tempStorage} 
        WHERE ${tempStorage[TempStorageKeys.STORAGE_ID]} = ${storage[StorageKeys.ID]}
    )`;

	const availableStorage = db
		.select()
		.from(storage)
		.where(
			and(
				eq(storage[StorageKeys.USER_ID], userId),
				// Available space = Limit - Used - Pending Reserved >= Requested Size
				sql`${storage[StorageKeys.LIMIT_BYTES]} - ${storage[StorageKeys.USED_BYTES]} - ${pendingReservedBytes} >= ${fileSizeBytes}`
			)
		)
		.orderBy(desc(storage[StorageKeys.PRIORITY]))
		.limit(1)
		.get();

	return availableStorage;
}

export async function getTempStorage(userId: string, file_hash: string) {
	const tableId = userId + '_' + file_hash;
	return db.select().from(tempStorage).where(eq(tempStorage[TempStorageKeys.ID], tableId)).get();
}
export async function addTempStorage(
	userId: string,
	file_hash: string,
	storageId: string,
	size: number,
	provider: number
) {
	const tableId = userId + '_' + file_hash;
	await db.insert(tempStorage).values({
		[TempStorageKeys.ID]: tableId,
		[TempStorageKeys.USER_ID]: userId,
		[TempStorageKeys.STORAGE_ID]: storageId,
		[TempStorageKeys.SIZE]: size,
		[TempStorageKeys.PROVIDER]: provider
	});
}
