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
import { eq, and, ne, gt, count, desc, sql, getTableColumns } from 'drizzle-orm';
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

export async function getUserBySupabaseId(supabaseId: string) {
	return db.select().from(user).where(eq(user[UserKeys.SUPABASE_ID], supabaseId)).get();
}

export async function getUser(userId: number) {
	return db.select().from(user).where(eq(user[UserKeys.ID], userId)).get();
}

export async function addUser(supabaseId: string, email: string, cipher: string, nonce: string) {
	const newUser = db
		.insert(user)
		.values({
			[UserKeys.SUPABASE_ID]: supabaseId,
			[UserKeys.EMAIL]: email,
			[UserKeys.CIPHER]: cipher,
			[UserKeys.NONCE]: nonce
		})
		.returning()
		.get();
	await db
		.insert(userData)
		.values({ [UserDataKeys.USER_ID]: newUser[UserKeys.ID], [UserDataKeys.DEVICE_UUID]: 'Server' });

	// add default fife storage for this user
	const fifeUser = await getUserBySupabaseId('fife');
	if (!fifeUser) {
		return;
	}
	const fifeCredentials = await getUserCredential(fifeUser[UserKeys.ID], StorageProvider.FIFE);
	if (fifeCredentials) {
		const fifeProvider = db
			.select()
			.from(provider)
			.where(eq(provider[ProviderKeys.ID], StorageProvider.FIFE))
			.get();
		if (fifeProvider) {
			await addStorage(
				newUser[UserKeys.ID],
				fifeCredentials[CredentialKeys.ID],
				fifeProvider[ProviderKeys.FREE_BYTES],
				fifeProvider[ProviderKeys.FREE_BYTES],
				fifeProvider[ProviderKeys.PRIORITY],
				{}
			);
		}
	}
}

export async function getUserData(userId: number) {
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

export async function getUserDevices(userId: number, deviceId?: string) {
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
		.where(eq(userDevice[UserDeviceKeys.USER_ID], userId));
}

export async function addUpdateDevice(
	userId: number,
	deviceUuid: string,
	title: string,
	type: number,
	notificationId: string,
	active: number
) {
	const deviceRow = db
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
		await db
			.update(userDevice)
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
			);

		return json({ success: 1 });
	} else {
		const result = db
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

			await db.insert(userDevice).values({
				[UserDeviceKeys.DEVICE_UUID]: deviceUuid,
				[UserDeviceKeys.USER_ID]: userId,
				[UserDeviceKeys.TITLE]: title,
				[UserDeviceKeys.DEVICE_TYPE]: type,
				[UserDeviceKeys.NOTIFICATION_ID]: notificationId,
				[UserDeviceKeys.ACTIVE]: 1
			});

			return json({ success: 1 });
		}
	}
}

export async function removeDevice(userId: number, deviceUuid: string) {
	const device = await db
		.select()
		.from(userDevice)
		.where(
			and(
				eq(userDevice[UserDeviceKeys.USER_ID], userId),
				eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
			)
		);
	if (device) {
		await db
			.delete(userDevice)
			.where(
				and(
					eq(userDevice[UserDeviceKeys.USER_ID], userId),
					eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
				)
			);
		return json({ success: 1 });
	} else {
		return json({ success: 0, message: ErrorCode.NO_DEVICE });
	}
}

export async function updateDeviceStatus(userId: number, deviceUuid: string, status: number) {
	await db
		.update(userDevice)
		.set({ [UserDeviceKeys.ACTIVE]: status })
		.where(
			and(
				eq(userDevice[UserDeviceKeys.USER_ID], userId),
				eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
			)
		);
	return json({ success: 1 });
}

export async function fetchChanges(
	userId: number,
	deviceUuid: string,
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
			...getTableColumns(part), // Spreads all original columns from the part table
			[PartKeys.FILE_ID]: file[FileKeys.FILE_HASH] // Overrides FILE_ID with FILE_HASH
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

export async function saveFileChanges(userId: number, deviceUuid: string, changes: any[]) {
	for (const change of changes) {
		const fileHash = change['id'];
		const incomingUpdatedAt = change['updated_at'] || 0;
		const changeString = change['data'];
		const changedData = typeof changeString == 'string' ? JSON.parse(changeString) : changeString;
		const userFile = db
			.select()
			.from(file)
			.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
			.get();
		const providerId = change['provider_id'];
		const storageId = change['storage_id'];
		const uploadedAt = change['uploaded_at'];
		const itemCount = change['item_count'];
		if (userFile) {
			if (incomingUpdatedAt > userFile[FileKeys.CLIENT_UPDATED_AT]) {
				const existingUploadedAt = userFile[FileKeys.UPLOADED_AT];
				if (itemCount > 0 && existingUploadedAt > 0) {
					await db
						.update(file)
						.set({
							[FileKeys.DEVICE_UUID]: deviceUuid,
							[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
						})
						.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)));
				} else {
					await db
						.update(file)
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
						.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)));
				}

				if (itemCount == 0) {
					deleteFileFromStorage(userFile);
				}
			}
		} else {
			await db.insert(file).values({
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
			});
		}
		if (uploadedAt > 0) {
			const tempRow = db
				.select({
					bytes: tempStorage[TempStorageKeys.SIZE],
					storageId: tempStorage[TempStorageKeys.STORAGE_ID]
				})
				.from(tempStorage)
				.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
				.get();
			if (tempRow) {
				await db
					.delete(tempStorage)
					.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)));
			}
		}
	}
}

export async function savePartChanges(userId: number, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const filePartId = change['id'];
		const partData = filePartId.split('_');
		const fileHash = partData[0];
		const fileEntry = await getUserFile(userId, fileHash);
		if (!fileEntry) {
			continue;
		}
		const fileId = fileEntry[FileKeys.ID];
		const partNumber = parseInt(partData[1]);
		const incomingUpdatedAt = change['updated_at'] || 0;
		const changeString = change['data'];
		const changedData = typeof changeString == 'string' ? JSON.parse(changeString) : changeString;
		const existingRow = db
			.select({
				clientUpdatedAt: part[PartKeys.CLIENT_UPDATED_AT],
				uploaded: part[PartKeys.UPLOADED]
			})
			.from(part)
			.where(
				and(
					eq(part[PartKeys.USER_ID], userId),
					eq(part[PartKeys.FILE_ID], fileId),
					eq(part[PartKeys.PART_NUMBER], partNumber)
				)
			)
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
							eq(part[PartKeys.FILE_ID], fileHash),
							eq(part[PartKeys.PART_NUMBER], partNumber)
						)
					);
			}
		} else {
			await db.insert(part).values({
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
			});
		}
		if (updateUsedBytes) {
			const fileRow = db
				.select()
				.from(file)
				.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
				.get();
			if (fileRow) {
				const storageId = fileRow[FileKeys.STORAGE_ID];
				if (storageId != null) {
					await updateStorageUsedSize(storageId, userId, partBytes, true);
					await updateTempStorageSize(userId, fileHash, partBytes);
				}
			}
		}
	}
}

export async function saveItemChanges(userId: number, deviceId: string, changes: any[]) {
	for (const change of changes) {
		const itemId = change['id'];
		const incomingUpdatedAt = change['updated_at'] || 0;

		const existingRow = db
			.select({ clientUpdatedAt: item[ItemKeys.CLIENT_UPDATED_AT] })
			.from(item)
			.where(and(eq(item[ItemKeys.ITEM_ID], itemId), eq(item[ItemKeys.USER_ID], userId)))
			.get();

		if (existingRow) {
			if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
				await db
					.update(item)
					.set({
						[ItemKeys.DEVICE_UUID]: deviceId,
						[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
						[ItemKeys.TEXT_NONCE]: change['text_nonce'],
						[ItemKeys.KEY_CIPHER]: change['key_cipher'],
						[ItemKeys.KEY_NONCE]: change['key_nonce'],
						[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
					})
					.where(and(eq(item[ItemKeys.ITEM_ID], itemId), eq(item[ItemKeys.USER_ID], userId)));
			}
		} else {
			await db.insert(item).values({
				[ItemKeys.ITEM_ID]: itemId,
				[ItemKeys.USER_ID]: userId,
				[ItemKeys.DEVICE_UUID]: deviceId,
				[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
				[ItemKeys.TEXT_NONCE]: change['text_nonce'],
				[ItemKeys.KEY_CIPHER]: change['key_cipher'],
				[ItemKeys.KEY_NONCE]: change['key_nonce'],
				[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
			});
		}
	}
}

export async function addCredentials(userId: number, credentialsData: any, providerId: number) {
	const providerEntry = db
		.select()
		.from(provider)
		.where(eq(provider[ProviderKeys.ID], providerId))
		.get();
	if (!providerEntry) {
		return;
	}
	const existingEntry = db
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
		const newCredential = db
			.insert(credential)
			.values({
				[CredentialKeys.USER_ID]: userId,
				[CredentialKeys.PROVIDER_ID]: providerId,
				[CredentialKeys.CREDENTIALS]: credentialsData
			})
			.returning()
			.get();

		if (providerEntry[ProviderKeys.ID] != StorageProvider.FIFE) {
			await addStorage(
				userId,
				newCredential[CredentialKeys.ID],
				providerEntry[ProviderKeys.FREE_BYTES],
				providerEntry[ProviderKeys.FREE_BYTES],
				providerEntry[ProviderKeys.PRIORITY],
				{}
			);
		}
	} else {
		await db
			.update(credential)
			.set({
				[CredentialKeys.SERVER_UPDATED_AT]: Date.now(),
				[CredentialKeys.CREDENTIALS]: credentialsData
			})
			.where(eq(credential[CredentialKeys.ID], existingEntry[CredentialKeys.ID]));
	}
}

export async function getUserCredential(userId: number, providerId: number) {
	return db
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

export async function getCredentials(id: number) {
	return db.select().from(credential).where(eq(credential[CredentialKeys.ID], id)).get();
}

export async function getCredentialByStorageId(userId: number, storageId: number) {
	const storage = await getStorage(storageId);
	if (storage && storage[StorageKeys.USER_ID] == userId) {
		return await getCredentials(storage[StorageKeys.CREDENTIAL_ID]);
	} else {
		return undefined;
	}
}

export async function markCredentialsUpdating(Id: number) {
	return await db
		.update(credential)
		.set({ [CredentialKeys.UPDATING]: 1 })
		.where(and(eq(credential[CredentialKeys.ID], Id), eq(credential[CredentialKeys.UPDATING], 0)))
		.returning();
}

export async function markCredentialsUpdated(Id: number) {
	await db
		.update(credential)
		.set({ [CredentialKeys.UPDATING]: 0 })
		.where(eq(credential[CredentialKeys.ID], Id));
}

export async function updateCredentials(Id: number, creds: any) {
	await db
		.update(credential)
		.set({
			[CredentialKeys.SERVER_UPDATED_AT]: Date.now(),
			[CredentialKeys.CREDENTIALS]: creds,
			[CredentialKeys.UPDATING]: 0
		})
		.where(eq(credential[CredentialKeys.ID], Id));
}

export async function addStorage(
	userId: number,
	credentialId: number,
	storageLimit: number,
	freeStorageLimit: number,
	priority: number = 0,
	json: {}
) {
	return await db.insert(storage).values({
		[StorageKeys.USER_ID]: userId,
		[StorageKeys.CREDENTIAL_ID]: credentialId,
		[StorageKeys.LIMIT_BYTES]: storageLimit,
		[StorageKeys.PRIORITY]: priority,
		[StorageKeys.JSON]: json,
		[StorageKeys.LIMIT_FREE_BYTES]: freeStorageLimit
	});
}

export async function getStorage(id: number) {
	return db.select().from(storage).where(eq(storage[StorageKeys.ID], id)).get();
}

export async function getOptimalStorage(userId: number, fileSizeBytes: number) {
	// Get User Plan
	const planData = await getUserData(userId);
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
export async function updateStorageUsedSize(
	storageId: number,
	userId: number,
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

export async function updateTempStorageSize(userId: number, fileId: number, bytes: number) {
	const row = db
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
		await db
			.update(tempStorage)
			.set({
				[TempStorageKeys.SIZE]: newBytes
			})
			.where(
				and(
					eq(tempStorage[TempStorageKeys.USER_ID], userId),
					eq(tempStorage[TempStorageKeys.FILE_ID], fileId)
				)
			);
	}
}

export async function getTempStorage(userId: number, fileId: number) {
	return db
		.select()
		.from(tempStorage)
		.where(
			and(
				eq(tempStorage[TempStorageKeys.FILE_ID], fileId),
				eq(tempStorage[TempStorageKeys.USER_ID], userId)
			)
		)
		.get();
}

export async function addTempStorage(
	userId: number,
	fileId: number,
	storageId: number,
	size: number,
	providerId: number
) {
	await db.insert(tempStorage).values({
		[TempStorageKeys.FILE_ID]: fileId,
		[TempStorageKeys.USER_ID]: userId,
		[TempStorageKeys.STORAGE_ID]: storageId,
		[TempStorageKeys.SIZE]: size,
		[TempStorageKeys.PROVIDER_ID]: providerId
	});
}

export async function getUserFile(userId: number, fileHash: string) {
	return db
		.select()
		.from(file)
		.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
		.get();
}

export async function getUserFilePart(userId: number, fileId: number, partNumber: number) {
	return db
		.select()
		.from(part)
		.where(
			and(
				eq(part[PartKeys.FILE_ID], fileId),
				eq(part[PartKeys.USER_ID], userId),
				eq(part[PartKeys.PART_NUMBER], partNumber)
			)
		)
		.get();
}

export async function resetUserFilePart(userId: number, fileId: number, partNumber: number) {
	return db
		.update(part)
		.set({
			[PartKeys.DEVICE_UUID]: 'SERVER',
			[PartKeys.PART_SIZE]: 0,
			[PartKeys.CIPHER]: null,
			[PartKeys.NONCE]: null,
			[PartKeys.JSON]: {},
			[PartKeys.CLIENT_UPDATED_AT]: Date.now(),
			[PartKeys.DELETED]: 1
		})
		.where(
			and(
				eq(part[PartKeys.FILE_ID], fileId),
				eq(part[PartKeys.USER_ID], userId),
				eq(part[PartKeys.PART_NUMBER], partNumber)
			)
		);
}
export async function resetUserFileByHash(userId: number, fileHash: string) {
	return db
		.update(file)
		.set({
			[FileKeys.DEVICE_UUID]: 'SERVER',
			[FileKeys.PARTS]: 0,
			[FileKeys.UPLOADED_AT]: 0,
			[FileKeys.PROVIDER_ID]: 0,
			[FileKeys.STORAGE_ID]: null,
			[FileKeys.JSON]: {},
			[FileKeys.CLIENT_UPDATED_AT]: Date.now(),
			[FileKeys.DELETED]: 1
		})
		.where(and(eq(file[FileKeys.FILE_HASH], fileHash), eq(file[FileKeys.USER_ID], userId)));
}

export async function getProviders() {
	return db
		.select({
			id: provider[ProviderKeys.ID],
			title: provider[ProviderKeys.TITLE],
			bytes: provider[ProviderKeys.FREE_BYTES]
		})
		.from(provider);
}

export async function getUserStorage(userId: number) {
	// 1. Fetch data from all three tables concurrently for maximum performance
	const [allProviders, userCredentials, userStorages] = await Promise.all([
		db.select().from(provider),
		db.select().from(credential).where(eq(credential[CredentialKeys.USER_ID], userId)),
		db.select().from(storage).where(eq(storage[StorageKeys.USER_ID], userId))
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
