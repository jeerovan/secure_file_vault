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
import { eq, and, ne, gt, count, desc, sql } from 'drizzle-orm';
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
import { deleteFileFromStorage } from '../deleteWorker';

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
	const fifeCredentials = await getCredentials('fife', StorageProvider.FIFE);
	if (fifeCredentials) {
		await addStorage(userId, fifeCredentials[CredentialsKeys.ID], 5368709120, 5368709120, 1, {});
	}
	await db
		.insert(userData)
		.values({ [UserDataKeys.ID]: userId, [UserDataKeys.DEVICE_ID]: 'Server' });
	return await db.insert(user).values({
		[UserKeys.ID]: userId,
		[UserKeys.EMAIL]: email,
		[UserKeys.CIPHER]: cipher,
		[UserKeys.NONCE]: nonce
	});
}

export async function getUserData(userId: string) {
	return db.select().from(userData).where(eq(userData[UserDataKeys.ID], userId)).get();
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

		return json({ success: 1 });
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
			return json({ success: 0, message: ErrorCode.DEVICE_LIMIT_REACHED });
		} else {
			if (!title || type === undefined) {
				return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
			}

			await db.insert(userDevice).values({
				[UserDeviceKeys.ID]: tableId,
				[UserDeviceKeys.USER_ID]: userId,
				[UserDeviceKeys.TITLE]: title,
				[UserDeviceKeys.DEVICE_TYPE]: type,
				[UserDeviceKeys.NOTIFICATION_ID]: notificationId,
				[UserDeviceKeys.STATUS]: 1
			});

			return json({ success: 1 });
		}
	}
}

export async function removeDevice(tableId: string) {
	const device = await db
		.select()
		.from(userDevice)
		.where(eq(userDevice[UserDeviceKeys.ID], tableId));
	if (device) {
		await db.delete(userDevice).where(eq(userDevice[UserDeviceKeys.ID], tableId));
		return json({ success: 1 });
	} else {
		return json({ success: 0, message: ErrorCode.NO_DEVICE });
	}
}

export async function fetchChanges(
	userId: string,
	deviceId: string,
	lastProfilesTS: number,
	lastFilesTS: number,
	lastItemsTS: number,
	lastPartsTS: number
) {
	const rowLimit = 100;
	const profileRows = db
		.select()
		.from(userData)
		.where(
			and(
				eq(userData[UserDataKeys.ID], userId),
				gt(userData[UserDataKeys.SERVER_UPDATED_AT], lastProfilesTS),
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
				gt(file[FileKeys.SERVER_UPDATED_AT], lastFilesTS),
				ne(file[FileKeys.DEVICE_ID], deviceId)
			)
		)
		.limit(rowLimit)
		.all();

	const partRows = db
		.select()
		.from(part)
		.where(
			and(
				eq(part[PartKeys.USER_ID], userId),
				gt(part[PartKeys.SERVER_UPDATED_AT], lastPartsTS),
				ne(part[PartKeys.DEVICE_ID], deviceId)
			)
		)
		.limit(rowLimit)
		.all();

	const itemRows = db
		.select()
		.from(item)
		.where(
			and(
				eq(item[ItemKeys.USER_ID], userId),
				gt(item[ItemKeys.SERVER_UPDATED_AT], lastItemsTS),
				ne(item[ItemKeys.DEVICE_ID], deviceId)
			)
		)
		.limit(rowLimit)
		.all();

	return { profileRows, fileRows, partRows, itemRows };
}

export async function saveFileChanges(userId: string, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const fileHash = change['id'];
		const fileKey = userId + '_' + fileHash;
		const incomingUpdatedAt = change['updated_at'] || 0;
		const changeString = change['data'];
		const changedData = typeof changeString == 'string' ? JSON.parse(changeString) : changeString;
		const existingRow = db.select().from(file).where(eq(file[FileKeys.ID], fileKey)).get();
		const provider = change['provider'];
		const storageId = change['storage_id'];
		const uploadedAt = change['uploaded_at'];
		const itemCount = change['item_count'];
		if (existingRow) {
			if (incomingUpdatedAt > existingRow[FileKeys.CLIENT_UPDATED_AT]) {
				const existingUploadedAt = existingRow[FileKeys.UPLOADED_AT];
				if (itemCount > 0 && existingUploadedAt > 0) {
					await db
						.update(file)
						.set({
							[FileKeys.DEVICE_ID]: deviceId,
							[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
						})
						.where(eq(file[FileKeys.ID], fileKey));
				} else {
					await db
						.update(file)
						.set({
							[FileKeys.DEVICE_ID]: deviceId,
							[FileKeys.ITEMS_COUNT]: itemCount,
							[FileKeys.PARTS]: change['parts'] ?? 1,
							[FileKeys.UPLOADED_AT]: uploadedAt ?? 0,
							[FileKeys.PROVIDER]: change['provider'] ?? 0,
							[FileKeys.STORAGE_ID]: storageId ?? null,
							[FileKeys.JSON]: changedData,
							[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
							[FileKeys.DELETED]: change['deleted']
						})
						.where(eq(file[FileKeys.ID], fileKey));
				}

				if (itemCount == 0) {
					deleteFileFromStorage(userId, fileHash);
				}
			}
		} else {
			await db.insert(file).values({
				[FileKeys.ID]: fileKey,
				[FileKeys.USER_ID]: userId,
				[FileKeys.DEVICE_ID]: deviceId,
				[FileKeys.ITEMS_COUNT]: itemCount,
				[FileKeys.PARTS]: change['parts'] ?? 1,
				[FileKeys.UPLOADED_AT]: uploadedAt ?? 0,
				[FileKeys.STORAGE_ID]: storageId ?? null,
				[FileKeys.PROVIDER]: provider,
				[FileKeys.JSON]: changedData,
				[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
				[FileKeys.DELETED]: change['deleted']
			});
		}
		if (uploadedAt > 0) {
			const tempRow = db
				.select({
					bytes: tempStorage[TempStorageKeys.SIZE],
					storageId: tempStorage[TempStorageKeys.STORAGE_ID]
				})
				.from(tempStorage)
				.where(eq(tempStorage[TempStorageKeys.ID], fileKey))
				.get();
			if (tempRow) {
				await db.delete(tempStorage).where(eq(tempStorage[TempStorageKeys.ID], fileKey));
			}
		}
	}
}

export async function savePartChanges(userId: string, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const partId = change['id'];
		const partKey = userId + '_' + partId;
		const incomingUpdatedAt = change['updated_at'] || 0;
		const changeString = change['data'];
		const changedData = typeof changeString == 'string' ? JSON.parse(changeString) : changeString;
		const existingRow = db
			.select({
				clientUpdatedAt: part[PartKeys.CLIENT_UPDATED_AT],
				uploaded: part[PartKeys.UPLOADED]
			})
			.from(part)
			.where(eq(part[PartKeys.ID], partKey))
			.get();
		const deleted = change['deleted'];
		const uploaded = change['uploaded'];
		const partBytes = change['size'];
		let updateUsedBytes = uploaded == 1;
		if (existingRow) {
			if (existingRow.uploaded == 1) {
				updateUsedBytes = false;
			}
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(part)
					.set({
						[PartKeys.DEVICE_ID]: deviceId,
						[PartKeys.PART_SIZE]: partBytes,
						[PartKeys.CIPHER]: change['cipher'] ?? null,
						[PartKeys.NONCE]: change['nonce'] ?? null,
						[PartKeys.JSON]: changedData,
						[PartKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
						[PartKeys.DELETED]: deleted,
						[PartKeys.UPLOADED]: uploaded
					})
					.where(eq(part[PartKeys.ID], partKey));
			}
		} else {
			await db.insert(part).values({
				[PartKeys.ID]: partKey,
				[PartKeys.USER_ID]: userId,
				[PartKeys.DEVICE_ID]: deviceId,
				[PartKeys.PART_SIZE]: partBytes,
				[PartKeys.CIPHER]: change['cipher'] ?? null,
				[PartKeys.NONCE]: change['nonce'] ?? null,
				[PartKeys.JSON]: changedData,
				[PartKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
				[PartKeys.DELETED]: deleted,
				[PartKeys.UPLOADED]: uploaded
			});
		}
		if (updateUsedBytes) {
			const fileKey = partKey.slice(0, partKey.lastIndexOf('_'));
			const fileRow = db.select().from(file).where(eq(file[FileKeys.ID], fileKey)).get();
			if (fileRow) {
				const storageId = fileRow[FileKeys.STORAGE_ID];
				if (storageId != null) {
					await updateStorageUsedSize(storageId, userId, partBytes, true);
					await updateTempStorageSize(fileKey, partBytes);
				}
			}
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
			let storageLimit = 10737418240;
			if (provider == StorageProvider.CLOUDFLARE) {
				priority = 9;
			}
			await addStorage(userId, accountId, storageLimit, storageLimit, priority, {});
		}
	} else {
		await db
			.update(credentials)
			.set({
				[CredentialsKeys.SERVER_UPDATED_AT]: Date.now(),
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
export async function getCredentialsByStorageId(userId: string, storageId: string) {
	const storage = await getStorageById(storageId);
	if (storage && storage[StorageKeys.USER_ID] == userId) {
		return await getCredentialsById(storage[StorageKeys.CREDENTIALS_ID]);
	} else {
		return undefined;
	}
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
			[CredentialsKeys.SERVER_UPDATED_AT]: Date.now(),
			[CredentialsKeys.CREDENTIALS]: creds,
			[CredentialsKeys.UPDATING]: 0
		})
		.where(eq(credentials[CredentialsKeys.ID], accountId));
}

export async function addStorage(
	userId: string,
	accountId: string,
	storageLimit: number,
	freeStorageLimit: number,
	priority: number = 0,
	json: {}
) {
	return await db.insert(storage).values({
		[StorageKeys.USER_ID]: userId,
		[StorageKeys.CREDENTIALS_ID]: accountId,
		[StorageKeys.LIMIT_BYTES]: storageLimit,
		[StorageKeys.PRIORITY]: priority,
		[StorageKeys.JSON]: json,
		[StorageKeys.LIMIT_FREE_BYTES]: freeStorageLimit
	});
}
export async function getStorageById(id: string) {
	return db.select().from(storage).where(eq(storage[StorageKeys.ID], id)).get();
}
export async function getOptimalStorage(userId: string, fileSizeBytes: number) {
	// Get User Plan
	const planData = await getUserData(userId);
	let planExpiresAt = 0;
	if (planData) {
		planExpiresAt = planData[UserDataKeys.PLAN_EXPIRES_AT];
	}
	const hasPlan = planExpiresAt > Date.now();
	const storageKey = hasPlan ? StorageKeys.LIMIT_BYTES : StorageKeys.LIMIT_FREE_BYTES;
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
				sql`${storage[storageKey]} - ${storage[StorageKeys.USED_BYTES]} - ${pendingReservedBytes} >= ${fileSizeBytes}`
			)
		)
		.orderBy(desc(storage[StorageKeys.PRIORITY]))
		.limit(1)
		.get();

	return availableStorage;
}
export async function updateStorageUsedSize(
	storageId: string,
	userId: string,
	bytes: number,
	add: boolean
) {
	const newBytes = add
		? sql`${storage[StorageKeys.USED_BYTES]} + ${bytes}`
		: sql`${storage[StorageKeys.USED_BYTES]} - ${bytes}`;
	await db
		.update(storage)
		.set({
			// Atomically add (or subtract) the bytes from the current USED_BYTES
			[StorageKeys.USED_BYTES]: newBytes
		})
		.where(and(eq(storage[StorageKeys.USER_ID], userId), eq(storage[StorageKeys.ID], storageId)));
}

export async function updateTempStorageSize(storageKey: string, bytes: number) {
	const row = db
		.select()
		.from(tempStorage)
		.where(eq(tempStorage[TempStorageKeys.ID], storageKey))
		.get();
	const newBytes = sql`MAX(0, ${tempStorage[TempStorageKeys.SIZE]} - ${bytes})`;
	if (row) {
		await db
			.update(tempStorage)
			.set({
				[TempStorageKeys.SIZE]: newBytes
			})
			.where(eq(tempStorage[TempStorageKeys.ID], storageKey));
	}
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
export async function getFile(userId: string, fileHash: string) {
	const tableKey = userId + '_' + fileHash;
	return db.select().from(file).where(eq(file[FileKeys.ID], tableKey)).get();
}
export async function getFilePart(tableKey: string) {
	return db.select().from(part).where(eq(part[PartKeys.ID], tableKey)).get();
}
export async function resetFilePart(tableKey: string) {
	return db
		.update(part)
		.set({
			[PartKeys.DEVICE_ID]: 'SERVER',
			[PartKeys.PART_SIZE]: 0,
			[PartKeys.CIPHER]: null,
			[PartKeys.NONCE]: null,
			[PartKeys.JSON]: {},
			[PartKeys.CLIENT_UPDATED_AT]: Date.now(),
			[PartKeys.DELETED]: 1
		})
		.where(eq(part[PartKeys.ID], tableKey));
}
export async function resetFile(userId: string, fileHash: string) {
	const fileKey = userId + '_' + fileHash;
	return db
		.update(file)
		.set({
			[FileKeys.DEVICE_ID]: 'SERVER',
			[FileKeys.PARTS]: 0,
			[FileKeys.UPLOADED_AT]: 0,
			[FileKeys.PROVIDER]: 0,
			[FileKeys.STORAGE_ID]: null,
			[FileKeys.JSON]: {},
			[FileKeys.CLIENT_UPDATED_AT]: Date.now(),
			[FileKeys.DELETED]: 1
		})
		.where(eq(file[FileKeys.ID], fileKey));
}
