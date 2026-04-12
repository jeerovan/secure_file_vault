import { json, error } from '@sveltejs/kit';
import { db } from '$lib/server/db';
import {
	user,
	userDevice,
	userData,
	file,
	item,
	part,
	credential,
	storage,
	tempStorage,
	provider
} from '$lib/server/db/schema';
import { eq, and, ne, gt, count, desc, sql, getTableColumns, inArray } from 'drizzle-orm';
import {
	UserKeys,
	UserDeviceKeys,
	UserDataKeys,
	FileKeys,
	PartKeys,
	ItemKeys,
	CredentialKeys,
	StorageKeys,
	ErrorCode,
	StorageProvider,
	TempStorageKeys,
	ProviderKeys
} from '$lib/server/db/keys';
import { deleteFileFromStorage } from '../deleteWorker';

const customDb: boolean = false;

export function getUserBySupabaseId(supabaseId: string, dbOrTx: any = db) {
	return dbOrTx.select().from(user).where(eq(user[UserKeys.SUPABASE_ID], supabaseId)).get();
}

export function getUser(userId: number, dbOrTx: any = db) {
	return dbOrTx.select().from(user).where(eq(user[UserKeys.ID], userId)).get();
}

export function addUser(supabaseId: string, email: string, cipher: string, nonce: string) {
	db.transaction((tx) => {
		const newUser = tx
			.insert(user)
			.values({
				[UserKeys.SUPABASE_ID]: supabaseId,
				[UserKeys.EMAIL]: email,
				[UserKeys.CIPHER]: cipher,
				[UserKeys.NONCE]: nonce
			})
			.returning()
			.get();
		tx.insert(userData)
			.values({
				[UserDataKeys.USER_ID]: newUser[UserKeys.ID],
				[UserDataKeys.DEVICE_UUID]: 'Server'
			})
			.run();

		// add default fife storage for this user
		const fifeUser = getUserBySupabaseId('fife', tx);
		if (!fifeUser) {
			return;
		}
		const fifeCredentials = getUserCredential(fifeUser[UserKeys.ID], StorageProvider.FIFE, tx);
		if (fifeCredentials) {
			const fifeProvider = tx
				.select()
				.from(provider)
				.where(eq(provider[ProviderKeys.ID], StorageProvider.FIFE))
				.get();
			if (fifeProvider) {
				addStorage(
					newUser[UserKeys.ID],
					fifeCredentials[CredentialKeys.ID],
					fifeProvider[ProviderKeys.FREE_BYTES],
					fifeProvider[ProviderKeys.FREE_BYTES],
					fifeProvider[ProviderKeys.PRIORITY],
					{},
					tx
				);
			}
		}
	});
}

export function getUserData(userId: number) {
	return db
		.select({
			userName: userData[UserDataKeys.USER_NAME],
			profileImage: userData[UserDataKeys.PROFILE_IMAGE],
			proId: userData[UserDataKeys.PRO_ID],
			planExpiresAt: userData[UserDataKeys.PLAN_EXPIRES_AT]
		})
		.from(userData)
		.where(eq(userData[UserDataKeys.USER_ID], userId))
		.get();
}

export function getUserDevices(userId: number, deviceId?: string) {
	if (deviceId) {
		return db
			.select({
				id: userDevice[UserDeviceKeys.DEVICE_UUID],
				lastAt: userDevice[UserDeviceKeys.SERVER_UPDATED_AT],
				title: userDevice[UserDeviceKeys.TITLE],
				type: userDevice[UserDeviceKeys.DEVICE_TYPE],
				active: userDevice[UserDeviceKeys.ACTIVE]
			})
			.from(userDevice)
			.where(
				and(
					eq(userDevice[UserDeviceKeys.USER_ID], userId),
					eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceId)
				)
			)
			.get();
	}
	return db
		.select({
			id: userDevice[UserDeviceKeys.DEVICE_UUID],
			lastAt: userDevice[UserDeviceKeys.SERVER_UPDATED_AT],
			title: userDevice[UserDeviceKeys.TITLE],
			type: userDevice[UserDeviceKeys.DEVICE_TYPE],
			active: userDevice[UserDeviceKeys.ACTIVE]
		})
		.from(userDevice)
		.where(eq(userDevice[UserDeviceKeys.USER_ID], userId))
		.all();
}

export function addUpdateDevice(
	userId: number,
	deviceUuid: string,
	title: string,
	type: number,
	notificationId: string,
	active: number
) {
	return db.transaction((tx) => {
		const deviceRow = tx
			.select()
			.from(userDevice)
			.where(
				and(
					eq(userDevice[UserDeviceKeys.USER_ID], userId),
					eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
				)
			)
			.get();

		if (deviceRow) {
			tx.update(userDevice)
				.set({
					[UserDeviceKeys.TITLE]: title ?? deviceRow[UserDeviceKeys.TITLE],
					[UserDeviceKeys.DEVICE_TYPE]: type ?? deviceRow[UserDeviceKeys.DEVICE_TYPE],
					[UserDeviceKeys.NOTIFICATION_ID]:
						notificationId ?? deviceRow[UserDeviceKeys.NOTIFICATION_ID],
					[UserDeviceKeys.ACTIVE]: active ?? deviceRow[UserDeviceKeys.ACTIVE]
				})
				.where(
					and(
						eq(userDevice[UserDeviceKeys.USER_ID], userId),
						eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
					)
				)
				.run();

			return json({ success: 1 });
		} else {
			const result = tx
				.select({ count: count() })
				.from(userDevice)
				.where(
					and(
						eq(userDevice[UserDeviceKeys.USER_ID], userId),
						eq(userDevice[UserDeviceKeys.ACTIVE], 1)
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

				tx.insert(userDevice)
					.values({
						[UserDeviceKeys.DEVICE_UUID]: deviceUuid,
						[UserDeviceKeys.USER_ID]: userId,
						[UserDeviceKeys.TITLE]: title,
						[UserDeviceKeys.DEVICE_TYPE]: type,
						[UserDeviceKeys.NOTIFICATION_ID]: notificationId,
						[UserDeviceKeys.ACTIVE]: 1
					})
					.run();

				return json({ success: 1 });
			}
		}
	});
}

export function removeDevice(userId: number, deviceUuid: string) {
	db.delete(userDevice)
		.where(
			and(
				eq(userDevice[UserDeviceKeys.USER_ID], userId),
				eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
			)
		)
		.run();
	return json({ success: 1 });
}

export function updateDeviceStatus(userId: number, deviceUuid: string, status: number) {
	db.update(userDevice)
		.set({ [UserDeviceKeys.ACTIVE]: status })
		.where(
			and(
				eq(userDevice[UserDeviceKeys.USER_ID], userId),
				eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
			)
		)
		.run();
	return json({ success: 1 });
}

export function fetchChanges(
	userId: number,
	deviceUuid: string,
	lastProfilesTS: number,
	lastFilesTS: number,
	lastItemsTS: number,
	lastPartsTS: number
) {
	const rowLimit = 100;
	const profileRows = db
		.select({
			...getTableColumns(userData),
			[UserDataKeys.USER_ID]: user[UserKeys.SUPABASE_ID]
		})
		.from(userData)
		.innerJoin(user, eq(userData[UserDataKeys.USER_ID], user[UserKeys.ID]))
		.where(
			and(
				eq(userData[UserDataKeys.USER_ID], userId),
				gt(userData[UserDataKeys.SERVER_UPDATED_AT], lastProfilesTS),
				ne(userData[UserDataKeys.DEVICE_UUID], deviceUuid)
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
				ne(file[FileKeys.DEVICE_UUID], deviceUuid)
			)
		)
		.limit(rowLimit)
		.all();

	const partRows = db
		.select({
			...getTableColumns(part),
			[PartKeys.FILE_ID]: file[FileKeys.FILE_HASH]
		})
		.from(part)
		.innerJoin(file, eq(part[PartKeys.FILE_ID], file[FileKeys.ID]))
		.where(
			and(
				eq(part[PartKeys.USER_ID], userId),
				gt(part[PartKeys.SERVER_UPDATED_AT], lastPartsTS),
				ne(part[PartKeys.DEVICE_UUID], deviceUuid)
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
				ne(item[ItemKeys.DEVICE_UUID], deviceUuid)
			)
		)
		.limit(rowLimit)
		.all();

	return { profileRows, fileRows, partRows, itemRows };
}

export function saveFileChanges(userId: number, deviceUuid: string, changes: any[]) {
	if (!changes || changes.length === 0) return;

	// 1. Extract all file hashes to fetch existing data in bulk
	const fileHashes = changes.map((change) => change['id']).filter(Boolean);

	db.transaction((tx) => {
		// 2. Fetch all existing files for these hashes in ONE query
		const existingFiles =
			fileHashes.length > 0
				? tx
						.select()
						.from(file)
						.where(
							and(eq(file[FileKeys.USER_ID], userId), inArray(file[FileKeys.FILE_HASH], fileHashes))
						)
						.all()
				: [];

		// 3. Create a lookup map for files: O(1) access by fileHash
		const fileMap = new Map(existingFiles.map((f) => [f[FileKeys.FILE_HASH], f]));

		// 4. Fetch all relevant temp storage records in ONE query
		const existingFileIds = existingFiles.map((f) => f[FileKeys.ID]);
		const existingTempStorages =
			existingFileIds.length > 0
				? tx
						.select({
							fileId: tempStorage[TempStorageKeys.FILE_ID],
							bytes: tempStorage[TempStorageKeys.SIZE],
							storageId: tempStorage[TempStorageKeys.STORAGE_ID]
						})
						.from(tempStorage)
						.where(
							and(
								eq(tempStorage[TempStorageKeys.USER_ID], userId),
								inArray(tempStorage[TempStorageKeys.FILE_ID], existingFileIds)
							)
						)
						.all()
				: [];

		// 5. Create a lookup map for temp storages: O(1) access by fileId
		const tempStorageMap = new Map(existingTempStorages.map((ts) => [ts.fileId, ts]));

		// 6. Iterate through the changes using the in-memory maps
		for (const change of changes) {
			const fileHash = change['id'];
			const incomingUpdatedAt = change['updated_at'] || 0;
			const changeString = change['data'];

			// Protect against JSON parse errors crashing the entire transaction
			let changedData = {};
			try {
				changedData = typeof changeString === 'string' ? JSON.parse(changeString) : changeString;
			} catch (error) {
				console.error(`Invalid JSON in saveFileChanges for hash: ${fileHash}`);
				continue; // Skip this malformed record
			}

			const userFile = fileMap.get(fileHash); // O(1) memory lookup instead of DB query
			const providerId = change['provider_id'] || null;
			const storageId = change['storage_id'] || null;
			const uploadedAt = change['uploaded_at'];
			const itemCount = change['item_count'];

			if (userFile) {
				if (incomingUpdatedAt > userFile[FileKeys.CLIENT_UPDATED_AT]) {
					const existingUploadedAt = userFile[FileKeys.UPLOADED_AT];

					if (itemCount > 0 && existingUploadedAt > 0) {
						tx.update(file)
							.set({
								[FileKeys.DEVICE_UUID]: deviceUuid,
								[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
							})
							.where(
								and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash))
							)
							.run();
					} else {
						tx.update(file)
							.set({
								[FileKeys.DEVICE_UUID]: deviceUuid,
								[FileKeys.ITEMS_COUNT]: itemCount,
								[FileKeys.PARTS]: change['parts'] ?? 1,
								[FileKeys.UPLOADED_AT]: uploadedAt ?? 0,
								[FileKeys.PROVIDER_ID]: providerId,
								[FileKeys.STORAGE_ID]: storageId,
								[FileKeys.JSON]: changedData,
								[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
								[FileKeys.DELETED]: change['deleted']
							})
							.where(
								and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash))
							)
							.run();
					}

					if (itemCount == 0) {
						deleteFileFromStorage(userFile, tx);
					}
				}
			} else {
				tx.insert(file)
					.values({
						[FileKeys.FILE_HASH]: fileHash,
						[FileKeys.USER_ID]: userId,
						[FileKeys.DEVICE_UUID]: deviceUuid,
						[FileKeys.ITEMS_COUNT]: itemCount,
						[FileKeys.PARTS]: change['parts'] ?? 1,
						[FileKeys.UPLOADED_AT]: uploadedAt ?? 0,
						[FileKeys.STORAGE_ID]: storageId,
						[FileKeys.PROVIDER_ID]: providerId,
						[FileKeys.JSON]: changedData,
						[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
						[FileKeys.DELETED]: change['deleted']
					})
					.run();
			}

			// Check temp storage using the memory map instead of the database
			if (uploadedAt > 0 && userFile) {
				const tempRow = tempStorageMap.get(userFile[FileKeys.ID]);
				if (tempRow) {
					tx.delete(tempStorage)
						.where(
							and(
								eq(tempStorage[TempStorageKeys.USER_ID], userId),
								eq(tempStorage[TempStorageKeys.FILE_ID], userFile[FileKeys.ID])
							)
						)
						.run();
				}
			}
		}
	});
}

export function savePartChanges(userId: number, deviceId: string, changes: any[]) {
	if (!changes || changes.length === 0) return;

	const fileHashesSet = new Set<string>();

	for (const change of changes) {
		const filePartId = change['id'];
		const partData = filePartId.split('_');
		fileHashesSet.add(partData[0]);
	}

	const fileHashes = Array.from(fileHashesSet);

	db.transaction((tx) => {
		// 1. Fetch relevant files in a single query
		const existingFiles =
			fileHashes.length > 0
				? tx
						.select()
						.from(file)
						.where(
							and(eq(file[FileKeys.USER_ID], userId), inArray(file[FileKeys.FILE_HASH], fileHashes))
						)
						.all()
				: [];

		const fileMap = new Map(existingFiles.map((f) => [f[FileKeys.FILE_HASH], f]));
		const fileIds = existingFiles.map((f) => f[FileKeys.ID]);

		// 2. Fetch relevant parts for all those files in a single query
		const existingParts =
			fileIds.length > 0
				? tx
						.select({
							fileId: part[PartKeys.FILE_ID],
							partNumber: part[PartKeys.PART_NUMBER],
							clientUpdatedAt: part[PartKeys.CLIENT_UPDATED_AT],
							uploaded: part[PartKeys.UPLOADED]
						})
						.from(part)
						.where(
							and(eq(part[PartKeys.USER_ID], userId), inArray(part[PartKeys.FILE_ID], fileIds))
						)
						.all()
				: [];

		// Create a composite key map: "fileId_partNumber" -> partData
		const partMap = new Map(existingParts.map((p) => [`${p.fileId}_${p.partNumber}`, p]));

		// 3. Process changes using in-memory maps
		for (const change of changes) {
			const filePartId = change['id'];
			const partData = filePartId.split('_');
			const fileHash = partData[0];

			const fileEntry = fileMap.get(fileHash);
			if (!fileEntry) continue; // Equivalent to your previous DB check

			const fileId = fileEntry[FileKeys.ID];
			const partNumber = parseInt(partData[1]);
			const incomingUpdatedAt = change['updated_at'] || 0;
			const changeString = change['data'];

			let changedData = {};
			try {
				changedData = typeof changeString === 'string' ? JSON.parse(changeString) : changeString;
			} catch (error) {
				console.error(`Invalid JSON in savePartChanges: ${filePartId}`);
				continue;
			}

			const existingRow = partMap.get(`${fileId}_${partNumber}`);
			const deleted = change['deleted'];
			const uploaded = change['uploaded'];
			const partBytes = change['size'];
			let updateUsedBytes = uploaded === 1;

			if (existingRow) {
				if (existingRow.uploaded === 1) {
					updateUsedBytes = false;
				}
				if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
					tx.update(part)
						.set({
							[PartKeys.DEVICE_UUID]: deviceId,
							[PartKeys.PART_SIZE]: partBytes,
							[PartKeys.CIPHER]: change['cipher'] ?? null,
							[PartKeys.NONCE]: change['nonce'] ?? null,
							[PartKeys.JSON]: changedData,
							[PartKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
							[PartKeys.DELETED]: deleted,
							[PartKeys.UPLOADED]: uploaded
						})
						.where(
							and(
								eq(part[PartKeys.USER_ID], userId),
								eq(part[PartKeys.FILE_ID], fileId), // Use specific fileId
								eq(part[PartKeys.PART_NUMBER], partNumber)
							)
						)
						.run();
				}
			} else {
				tx.insert(part)
					.values({
						[PartKeys.FILE_ID]: fileId,
						[PartKeys.USER_ID]: userId,
						[PartKeys.PART_NUMBER]: partNumber,
						[PartKeys.DEVICE_UUID]: deviceId,
						[PartKeys.PART_SIZE]: partBytes,
						[PartKeys.CIPHER]: change['cipher'] ?? null,
						[PartKeys.NONCE]: change['nonce'] ?? null,
						[PartKeys.JSON]: changedData,
						[PartKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt,
						[PartKeys.DELETED]: deleted,
						[PartKeys.UPLOADED]: uploaded
					})
					.run();
			}

			if (updateUsedBytes) {
				const storageId = fileEntry[FileKeys.STORAGE_ID];
				if (storageId != null) {
					updateStorageUsedSize(storageId, userId, partBytes, true, tx);
					updateTempStorageSize(userId, fileId, partBytes, tx); // Switched to use DB ID directly
				}
			}
		}
	});
}

export function saveItemChanges(userId: number, deviceId: string, changes: any[]) {
	if (!changes || changes.length === 0) return;

	const itemIds = changes.map((change) => change['id']).filter(Boolean);

	db.transaction((tx) => {
		// 1. Fetch existing items in a single query
		const existingItems =
			itemIds.length > 0
				? tx
						.select({
							itemId: item[ItemKeys.ITEM_ID],
							clientUpdatedAt: item[ItemKeys.CLIENT_UPDATED_AT]
						})
						.from(item)
						.where(
							and(eq(item[ItemKeys.USER_ID], userId), inArray(item[ItemKeys.ITEM_ID], itemIds))
						)
						.all()
				: [];

		// 2. Create memory map: O(1) lookup
		const itemMap = new Map(existingItems.map((i) => [i.itemId, i]));

		// 3. Process loop purely in-memory
		for (const change of changes) {
			const itemId = change['id'];
			const incomingUpdatedAt = change['updated_at'] || 0;

			const existingRow = itemMap.get(itemId);

			if (existingRow) {
				if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
					tx.update(item)
						.set({
							[ItemKeys.DEVICE_UUID]: deviceId,
							[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
							[ItemKeys.TEXT_NONCE]: change['text_nonce'],
							[ItemKeys.KEY_CIPHER]: change['key_cipher'],
							[ItemKeys.KEY_NONCE]: change['key_nonce'],
							[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
						})
						.where(and(eq(item[ItemKeys.USER_ID], userId), eq(item[ItemKeys.ITEM_ID], itemId)))
						.run();
				}
			} else {
				tx.insert(item)
					.values({
						[ItemKeys.ITEM_ID]: itemId,
						[ItemKeys.USER_ID]: userId,
						[ItemKeys.DEVICE_UUID]: deviceId,
						[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
						[ItemKeys.TEXT_NONCE]: change['text_nonce'],
						[ItemKeys.KEY_CIPHER]: change['key_cipher'],
						[ItemKeys.KEY_NONCE]: change['key_nonce'],
						[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
					})
					.run();
			}
		}
	});
}

export function addCredentials(userId: number, credentialsData: any, providerId: number) {
	db.transaction((tx) => {
		const providerEntry = tx
			.select()
			.from(provider)
			.where(eq(provider[ProviderKeys.ID], providerId))
			.get();
		if (!providerEntry) {
			return;
		}
		const existingEntry = tx
			.select()
			.from(credential)
			.where(
				and(
					eq(credential[CredentialKeys.USER_ID], userId),
					eq(credential[CredentialKeys.PROVIDER_ID], providerId)
				)
			)
			.get();

		if (!existingEntry) {
			const newCredential = tx
				.insert(credential)
				.values({
					[CredentialKeys.USER_ID]: userId,
					[CredentialKeys.PROVIDER_ID]: providerId,
					[CredentialKeys.CREDENTIALS]: credentialsData
				})
				.returning()
				.get();

			if (providerEntry[ProviderKeys.ID] != StorageProvider.FIFE) {
				addStorage(
					userId,
					newCredential[CredentialKeys.ID],
					providerEntry[ProviderKeys.FREE_BYTES],
					providerEntry[ProviderKeys.FREE_BYTES],
					providerEntry[ProviderKeys.PRIORITY],
					{},
					tx
				);
			}
		} else {
			tx.update(credential)
				.set({
					[CredentialKeys.CREDENTIALS]: credentialsData
				})
				.where(eq(credential[CredentialKeys.ID], existingEntry[CredentialKeys.ID]))
				.run();
		}
	});
}

export function getUserCredential(userId: number, providerId: number, dbOrTx: any = db) {
	return dbOrTx
		.select()
		.from(credential)
		.where(
			and(
				eq(credential[CredentialKeys.USER_ID], userId),
				eq(credential[CredentialKeys.PROVIDER_ID], providerId)
			)
		)
		.get();
}

export function getCredentials(id: number, dbOrTx: any = db) {
	return dbOrTx.select().from(credential).where(eq(credential[CredentialKeys.ID], id)).get();
}

export function getCredentialByStorageId(userId: number, storageId: number, dbOrTx: any = db) {
	const storage = getStorage(storageId, dbOrTx);
	if (storage && storage[StorageKeys.USER_ID] == userId) {
		return getCredentials(storage[StorageKeys.CREDENTIAL_ID], dbOrTx);
	} else {
		return undefined;
	}
}

export function markCredentialsUpdating(Id: number) {
	return db
		.update(credential)
		.set({ [CredentialKeys.UPDATING]: 1 })
		.where(and(eq(credential[CredentialKeys.ID], Id), eq(credential[CredentialKeys.UPDATING], 0)))
		.returning()
		.all();
}

export function markCredentialsUpdated(Id: number) {
	db.update(credential)
		.set({ [CredentialKeys.UPDATING]: 0 })
		.where(eq(credential[CredentialKeys.ID], Id))
		.run();
}

export function updateCredentials(Id: number, creds: any) {
	db.update(credential)
		.set({
			[CredentialKeys.CREDENTIALS]: creds,
			[CredentialKeys.UPDATING]: 0
		})
		.where(eq(credential[CredentialKeys.ID], Id))
		.run();
}

export function addStorage(
	userId: number,
	credentialId: number,
	storageLimit: number,
	freeStorageLimit: number,
	priority: number = 0,
	json: {},
	dbOrTx: any = db
) {
	return dbOrTx
		.insert(storage)
		.values({
			[StorageKeys.USER_ID]: userId,
			[StorageKeys.CREDENTIAL_ID]: credentialId,
			[StorageKeys.LIMIT_BYTES]: storageLimit,
			[StorageKeys.PRIORITY]: priority,
			[StorageKeys.JSON]: json,
			[StorageKeys.LIMIT_FREE_BYTES]: freeStorageLimit
		})
		.run();
}

export function getStorage(id: number, dbOrTx: any = db) {
	return dbOrTx.select().from(storage).where(eq(storage[StorageKeys.ID], id)).get();
}

export function getOptimalStorage(userId: number, fileSizeBytes: number) {
	// Get User Plan
	const planData = getUserData(userId);
	let planExpiresAt = 0;
	if (planData) {
		planExpiresAt = planData.planExpiresAt;
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
export function updateStorageUsedSize(
	storageId: number,
	userId: number,
	bytes: number,
	add: boolean,
	dbOrTx: any = db
) {
	const newBytes = add
		? sql`${storage[StorageKeys.USED_BYTES]} + ${bytes}`
		: sql`MAX(0, ${storage[StorageKeys.USED_BYTES]} - ${bytes})`;

	dbOrTx
		.update(storage)
		.set({
			// Atomically add (or subtract) the bytes from the current USED_BYTES
			[StorageKeys.USED_BYTES]: newBytes
		})
		.where(and(eq(storage[StorageKeys.USER_ID], userId), eq(storage[StorageKeys.ID], storageId)))
		.run();
}

export function updateTempStorageSize(
	userId: number,
	fileId: number,
	bytes: number,
	dbOrTx: any = db
) {
	const row = dbOrTx
		.select()
		.from(tempStorage)
		.where(
			and(
				eq(tempStorage[TempStorageKeys.USER_ID], userId),
				eq(tempStorage[TempStorageKeys.FILE_ID], fileId)
			)
		)
		.get();
	const newBytes = sql`MAX(0, ${tempStorage[TempStorageKeys.SIZE]} - ${bytes})`;
	if (row) {
		dbOrTx
			.update(tempStorage)
			.set({
				[TempStorageKeys.SIZE]: newBytes
			})
			.where(
				and(
					eq(tempStorage[TempStorageKeys.USER_ID], userId),
					eq(tempStorage[TempStorageKeys.FILE_ID], fileId)
				)
			)
			.run();
	}
}

export function getTempStorage(userId: number, fileId: number) {
	return db
		.select()
		.from(tempStorage)
		.where(
			and(
				eq(tempStorage[TempStorageKeys.USER_ID], userId),
				eq(tempStorage[TempStorageKeys.FILE_ID], fileId)
			)
		)
		.get();
}

export function addTempStorage(
	userId: number,
	fileId: number,
	storageId: number,
	size: number,
	providerId: number
) {
	db.insert(tempStorage)
		.values({
			[TempStorageKeys.FILE_ID]: fileId,
			[TempStorageKeys.USER_ID]: userId,
			[TempStorageKeys.STORAGE_ID]: storageId,
			[TempStorageKeys.SIZE]: size,
			[TempStorageKeys.PROVIDER_ID]: providerId
		})
		.run();
}

export function getUserFile(userId: number, fileHash: string, dbOrTx: any = db) {
	return dbOrTx
		.select()
		.from(file)
		.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
		.get();
}

export function getUserFilePart(
	userId: number,
	fileId: number,
	partNumber: number,
	dbOrTx: any = db
) {
	return dbOrTx
		.select({
			...getTableColumns(part),
			[PartKeys.FILE_ID]: file[FileKeys.FILE_HASH]
		})
		.from(part)
		.innerJoin(file, eq(part[PartKeys.FILE_ID], file[FileKeys.ID]))
		.where(
			and(
				eq(part[PartKeys.USER_ID], userId),
				eq(part[PartKeys.FILE_ID], fileId),
				eq(part[PartKeys.PART_NUMBER], partNumber)
			)
		)
		.get();
}

export function resetUserFilePart(
	userId: number,
	fileId: number,
	partNumber: number,
	dbOrTx: any = db
) {
	return dbOrTx
		.update(part)
		.set({
			[PartKeys.DEVICE_UUID]: 'SERVER',
			[PartKeys.PART_SIZE]: 0,
			[PartKeys.CIPHER]: null,
			[PartKeys.NONCE]: null,
			[PartKeys.JSON]: {},
			[PartKeys.CLIENT_UPDATED_AT]: Date.now(),
			[PartKeys.DELETED]: 1,
			[PartKeys.UPLOADED]: 0
		})
		.where(
			and(
				eq(part[PartKeys.USER_ID], userId),
				eq(part[PartKeys.FILE_ID], fileId),
				eq(part[PartKeys.PART_NUMBER], partNumber)
			)
		)
		.run();
}
export function resetUserFileByHash(userId: number, fileHash: string, dbOrTx: any = db) {
	return dbOrTx
		.update(file)
		.set({
			[FileKeys.DEVICE_UUID]: 'SERVER',
			[FileKeys.PARTS]: 0,
			[FileKeys.UPLOADED_AT]: 0,
			[FileKeys.PROVIDER_ID]: null,
			[FileKeys.STORAGE_ID]: null,
			[FileKeys.JSON]: {},
			[FileKeys.CLIENT_UPDATED_AT]: Date.now(),
			[FileKeys.DELETED]: 1
		})
		.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
		.run();
}

export function getProviders() {
	return db
		.select({
			id: provider[ProviderKeys.ID],
			title: provider[ProviderKeys.TITLE],
			bytes: provider[ProviderKeys.FREE_BYTES]
		})
		.from(provider)
		.all();
}

export async function getUserStorage(userId: number) {
	// 1. Fetch data from all three tables concurrently for maximum performance
	const [allProviders, userCredentials, userStorages] = await Promise.all([
		db.select().from(provider).all(),
		db.select().from(credential).where(eq(credential[CredentialKeys.USER_ID], userId)).all(),
		db.select().from(storage).where(eq(storage[StorageKeys.USER_ID], userId)).all()
	]);

	// 2. Create O(1) lookup maps to map relations in memory
	const providerMap = new Map(allProviders.map((p) => [p[ProviderKeys.ID], p]));
	const credentialsMap = new Map(userCredentials.map((c) => [c[CredentialKeys.ID], c]));

	const storages = [];
	const addedProviderIds = new Set<number>();

	for (const storageRecord of userStorages) {
		const credId = storageRecord[StorageKeys.CREDENTIAL_ID];
		const credRecord = credentialsMap.get(credId);

		if (credRecord) {
			const providerId = credRecord[CredentialKeys.PROVIDER_ID];
			const providerRecord = providerMap.get(providerId);

			if (providerRecord) {
				storages.push({
					id: providerRecord[ProviderKeys.ID],
					title: providerRecord[ProviderKeys.TITLE],
					added: 1 as const,
					bytes: storageRecord[StorageKeys.LIMIT_BYTES],
					used: storageRecord[StorageKeys.USED_BYTES]
				});
				// Track this provider as added
				addedProviderIds.add(providerId);
			}
		}
	}

	for (const providerRecord of allProviders) {
		if (!addedProviderIds.has(providerRecord[ProviderKeys.ID])) {
			storages.push({
				id: providerRecord[ProviderKeys.ID],
				title: providerRecord[ProviderKeys.TITLE],
				added: 0 as const,
				bytes: providerRecord[ProviderKeys.FREE_BYTES],
				used: 0 as const
			});
		}
	}

	return storages;
}
