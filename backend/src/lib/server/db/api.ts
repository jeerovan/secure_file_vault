import { json, error } from '@sveltejs/kit';
import { REVENUECAT_SECRET_KEY } from '$env/static/private';
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
import type { Db, Tx } from '.';

export async function getUserBySupabaseId(db: Db | Tx, supabaseId: string) {
	const [res] = await db
		.select()
		.from(user)
		.where(eq(user[UserKeys.SUPABASE_ID], supabaseId))
		.limit(1);
	return res;
}

export async function getUser(db: Db | Tx, userId: number) {
	const [res] = await db.select().from(user).where(eq(user[UserKeys.ID], userId)).limit(1);
	return res;
}

export async function addUser(
	db: Db | Tx,
	supabaseId: string,
	email: string,
	cipher: string,
	nonce: string
) {
	await db.transaction(async (tx) => {
		const [newUser] = await tx
			.insert(user)
			.values({
				[UserKeys.SUPABASE_ID]: supabaseId,
				[UserKeys.EMAIL]: email,
				[UserKeys.CIPHER]: cipher,
				[UserKeys.NONCE]: nonce
			})
			.returning();

		await tx.insert(userData).values({
			[UserDataKeys.USER_ID]: newUser[UserKeys.ID],
			[UserDataKeys.DEVICE_UUID]: 'Server'
		});

		// add default fife storage for this user
		const fifeUser = await getUserBySupabaseId(tx, 'fife');
		if (!fifeUser) {
			return;
		}

		const fifeCredentials = await getUserCredential(
			tx,
			fifeUser[UserKeys.ID],
			StorageProvider.FIFE
		);
		if (fifeCredentials) {
			const [fifeProvider] = await tx
				.select()
				.from(provider)
				.where(eq(provider[ProviderKeys.ID], StorageProvider.FIFE))
				.limit(1);

			if (fifeProvider) {
				await addStorage(
					tx,
					newUser[UserKeys.ID],
					fifeCredentials[CredentialKeys.ID],
					fifeProvider[ProviderKeys.FREE_BYTES],
					fifeProvider[ProviderKeys.FREE_BYTES],
					fifeProvider[ProviderKeys.PRIORITY],
					{}
				);
			}
		}
	});
}

export async function getUserData(db: Db | Tx, userId: number) {
	const [res] = await db
		.select({
			userName: userData[UserDataKeys.USER_NAME],
			profileImage: userData[UserDataKeys.PROFILE_IMAGE],
			proId: userData[UserDataKeys.PRO_ID],
			planExpiresAt: userData[UserDataKeys.PLAN_EXPIRES_AT],
			updatedAt: userData[UserDataKeys.SERVER_UPDATED_AT]
		})
		.from(userData)
		.where(eq(userData[UserDataKeys.USER_ID], userId))
		.limit(1);
	return res;
}

// On your backend (Node.js/Edge function)
export async function syncPlanExpiry(db: Db | Tx, userId: number, supaId: string) {
	// 1. Fetch the user's true subscription status from RevenueCat securely
	// Use your RevenueCat SECRET API key here (store in backend .env, never in app)
	const rcResponse = await fetch(`https://api.revenuecat.com/v1/subscribers/${supaId}`, {
		method: 'GET',
		headers: {
			Authorization: `Bearer ${REVENUECAT_SECRET_KEY}`,
			'Content-Type': 'application/json'
		}
	});

	if (!rcResponse.ok) {
		throw new Error('Failed to verify subscription with RevenueCat');
	}

	const rcData = await rcResponse.json();

	// 2. Extract the expiration date for your specific entitlement
	const entitlement = rcData.subscriber?.entitlements?.['pro'];

	let trueExpiresAt = 0;
	if (entitlement && entitlement.expires_date) {
		trueExpiresAt = new Date(entitlement.expires_date).getTime();
	}

	// 3. Compare and update your database safely
	const planData = await getUserData(db, userId);
	const currentPlanExpiresAt = planData ? planData.planExpiresAt : 0;

	// Only update if RevenueCat says they have more time than our DB currently thinks
	if (trueExpiresAt > currentPlanExpiresAt) {
		await db
			.update(userData)
			.set({ [UserDataKeys.PLAN_EXPIRES_AT]: trueExpiresAt })
			.where(eq(userData[UserDataKeys.USER_ID], userId));
	}

	return trueExpiresAt;
}

export async function updatePlanExpiryFromWebhook(
	db: Db | Tx,
	supaId: string,
	newExpiresAt: number
) {
	const user = await getUserBySupabaseId(db, supaId);
	if (!user) {
		console.error(`RC Webhook, user: ${supaId} not found`);
		return;
	}
	const userId = user[UserKeys.ID];
	const planData = await getUserData(db, userId);
	let currentPlanExpiresAt = 0;

	if (planData) {
		currentPlanExpiresAt = planData.planExpiresAt;
	}

	// Logic: Webhooks dictate the absolute state (including downgrades/refunds).
	// Update if the value is different to ensure sync.
	// Note: If revenuecat sends out-of-order webhooks, you may also want to
	// compare an `eventTimestamp` payload to `planData.updatedAt` to ignore stale webhooks.
	const update = newExpiresAt !== currentPlanExpiresAt;

	if (update) {
		await db
			.update(userData)
			.set({ [UserDataKeys.PLAN_EXPIRES_AT]: newExpiresAt })
			.where(eq(userData[UserDataKeys.USER_ID], userId));
	}
}

export async function getUserDevices(db: Db | Tx, userId: number, deviceId?: string) {
	if (deviceId) {
		const [res] = await db
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
			.limit(1);
		return res;
	}
	return await db
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
	db: Db | Tx,
	userId: number,
	deviceUuid: string,
	title: string,
	type: number,
	notificationId: string,
	active: number
) {
	return await db.transaction(async (tx) => {
		const [deviceRow] = await tx
			.select()
			.from(userDevice)
			.where(
				and(
					eq(userDevice[UserDeviceKeys.USER_ID], userId),
					eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
				)
			)
			.limit(1);

		if (deviceRow) {
			await tx
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
			const planData = await getUserData(tx, userId);
			let planExpiresAt = 0;
			if (planData) {
				planExpiresAt = planData.planExpiresAt;
			}
			const hasPlan = planExpiresAt > Date.now();
			const deviceLimit = hasPlan ? 10 : 5;

			const [activeDeviceRows] = await tx
				.select({ count: count() })
				.from(userDevice)
				.where(
					and(
						eq(userDevice[UserDeviceKeys.USER_ID], userId),
						eq(userDevice[UserDeviceKeys.ACTIVE], 1)
					)
				)
				.limit(1);

			const activeDevicesCount = activeDeviceRows?.count ?? 0;

			if (activeDevicesCount >= deviceLimit) {
				return json({ success: 0, message: ErrorCode.DEVICE_LIMIT_REACHED });
			} else {
				if (!title || type === undefined) {
					return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
				}

				await tx.insert(userDevice).values({
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
	});
}

export async function removeDevice(db: Db | Tx, userId: number, deviceUuid: string) {
	await db
		.delete(userDevice)
		.where(
			and(
				eq(userDevice[UserDeviceKeys.USER_ID], userId),
				eq(userDevice[UserDeviceKeys.DEVICE_UUID], deviceUuid)
			)
		);
	return json({ success: 1 });
}

export async function updateDeviceStatus(
	db: Db | Tx,
	userId: number,
	deviceUuid: string,
	status: number
) {
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
	db: Db | Tx,
	userId: number,
	deviceUuid: string,
	lastProfilesTS: number,
	lastFilesTS: number,
	lastItemsTS: number,
	lastPartsTS: number
) {
	const rowLimit = 100;
	const profileRows = await db
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
		);

	const fileRows = await db
		.select()
		.from(file)
		.where(
			and(
				eq(file[FileKeys.USER_ID], userId),
				gt(file[FileKeys.SERVER_UPDATED_AT], lastFilesTS),
				ne(file[FileKeys.DEVICE_UUID], deviceUuid)
			)
		)
		.limit(rowLimit);

	const partRows = await db
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
		.limit(rowLimit);

	const itemRows = await db
		.select()
		.from(item)
		.where(
			and(
				eq(item[ItemKeys.USER_ID], userId),
				gt(item[ItemKeys.SERVER_UPDATED_AT], lastItemsTS),
				ne(item[ItemKeys.DEVICE_UUID], deviceUuid)
			)
		)
		.limit(rowLimit);

	return { profileRows, fileRows, partRows, itemRows };
}

export async function saveFileChanges(
	db: Db | Tx,
	userId: number,
	deviceUuid: string,
	changes: any[]
) {
	if (!changes || changes.length === 0) return;

	const fileHashes = changes.map((change) => change['id']).filter(Boolean);

	await db.transaction(async (tx) => {
		const existingFiles =
			fileHashes.length > 0
				? await tx
						.select()
						.from(file)
						.where(
							and(eq(file[FileKeys.USER_ID], userId), inArray(file[FileKeys.FILE_HASH], fileHashes))
						)
				: [];

		const fileMap = new Map(existingFiles.map((f) => [f[FileKeys.FILE_HASH], f]));

		const existingFileIds = existingFiles.map((f) => f[FileKeys.ID]);
		const existingTempStorages =
			existingFileIds.length > 0
				? await tx
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
				: [];

		const tempStorageMap = new Map(existingTempStorages.map((ts) => [ts.fileId, ts]));

		for (const change of changes) {
			const fileHash = change['id'];
			const incomingUpdatedAt = change['updated_at'] || 0;
			const changeString = change['data'];

			let changedData = {};
			try {
				changedData = typeof changeString === 'string' ? JSON.parse(changeString) : changeString;
			} catch (error) {
				console.error(`Invalid JSON in saveFileChanges for hash: ${fileHash}`);
				continue;
			}

			const userFile = fileMap.get(fileHash);
			const providerId = change['provider_id'] || null;
			const storageId = change['storage_id'] || null;
			const uploadedAt = change['uploaded_at'];
			const itemCount = change['item_count'];

			if (userFile) {
				if (incomingUpdatedAt > userFile[FileKeys.CLIENT_UPDATED_AT]) {
					const existingUploadedAt = userFile[FileKeys.UPLOADED_AT];

					if (itemCount > 0 && existingUploadedAt > 0) {
						await tx
							.update(file)
							.set({
								[FileKeys.DEVICE_UUID]: deviceUuid,
								[FileKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
							})
							.where(
								and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash))
							);
					} else {
						await tx
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
							.where(
								and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash))
							);
					}

					if (itemCount == 0) {
						// Ensure deleteFileFromStorage is awaited if it performs async operations
						await deleteFileFromStorage(tx, userFile);
					}
				}
			} else {
				await tx.insert(file).values({
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

			if (uploadedAt > 0 && userFile) {
				const tempRow = tempStorageMap.get(userFile[FileKeys.ID]);
				if (tempRow) {
					await tx
						.delete(tempStorage)
						.where(
							and(
								eq(tempStorage[TempStorageKeys.USER_ID], userId),
								eq(tempStorage[TempStorageKeys.FILE_ID], userFile[FileKeys.ID])
							)
						);
				}
			}
		}
	});
}

export async function savePartChanges(
	db: Db | Tx,
	userId: number,
	deviceId: string,
	changes: any[]
) {
	if (!changes || changes.length === 0) return;

	const fileHashesSet = new Set<string>();

	for (const change of changes) {
		const filePartId = change['id'];
		const partData = filePartId.split('_');
		fileHashesSet.add(partData[0]);
	}

	const fileHashes = Array.from(fileHashesSet);

	await db.transaction(async (tx) => {
		const existingFiles =
			fileHashes.length > 0
				? await tx
						.select()
						.from(file)
						.where(
							and(eq(file[FileKeys.USER_ID], userId), inArray(file[FileKeys.FILE_HASH], fileHashes))
						)
				: [];

		const fileMap = new Map(existingFiles.map((f) => [f[FileKeys.FILE_HASH], f]));
		const fileIds = existingFiles.map((f) => f[FileKeys.ID]);

		const existingParts =
			fileIds.length > 0
				? await tx
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
				: [];

		const partMap = new Map(existingParts.map((p) => [`${p.fileId}_${p.partNumber}`, p]));

		for (const change of changes) {
			const filePartId = change['id'];
			const partData = filePartId.split('_');
			const fileHash = partData[0];

			const fileEntry = fileMap.get(fileHash);
			if (!fileEntry) continue;

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
					await tx
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
								eq(part[PartKeys.FILE_ID], fileId),
								eq(part[PartKeys.PART_NUMBER], partNumber)
							)
						);
				}
			} else {
				await tx.insert(part).values({
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
				const storageId = fileEntry[FileKeys.STORAGE_ID];
				if (storageId != null) {
					await updateStorageUsedSize(tx, storageId, userId, partBytes, true);
					await updateTempStorageSize(tx, userId, fileId, partBytes);
				}
			}
		}
	});
}

export async function saveItemChanges(
	db: Db | Tx,
	userId: number,
	deviceId: string,
	changes: any[]
) {
	if (!changes || changes.length === 0) return;

	const itemIds = changes.map((change) => change['id']).filter(Boolean);

	await db.transaction(async (tx) => {
		const existingItems =
			itemIds.length > 0
				? await tx
						.select({
							itemId: item[ItemKeys.ITEM_ID],
							clientUpdatedAt: item[ItemKeys.CLIENT_UPDATED_AT]
						})
						.from(item)
						.where(
							and(eq(item[ItemKeys.USER_ID], userId), inArray(item[ItemKeys.ITEM_ID], itemIds))
						)
				: [];

		const itemMap = new Map(existingItems.map((i) => [i.itemId, i]));

		for (const change of changes) {
			const itemId = change['id'];
			const incomingUpdatedAt = change['updated_at'] || 0;

			const existingRow = itemMap.get(itemId);

			if (existingRow) {
				if (incomingUpdatedAt > existingRow.clientUpdatedAt) {
					await tx
						.update(item)
						.set({
							[ItemKeys.DEVICE_UUID]: deviceId,
							[ItemKeys.TEXT_CIPHER]: change['text_cipher'],
							[ItemKeys.TEXT_NONCE]: change['text_nonce'],
							[ItemKeys.KEY_CIPHER]: change['key_cipher'],
							[ItemKeys.KEY_NONCE]: change['key_nonce'],
							[ItemKeys.CLIENT_UPDATED_AT]: incomingUpdatedAt
						})
						.where(and(eq(item[ItemKeys.USER_ID], userId), eq(item[ItemKeys.ITEM_ID], itemId)));
				}
			} else {
				await tx.insert(item).values({
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
	});
}

export async function addCredentials(
	db: Db | Tx,
	userId: number,
	credentialsData: any,
	providerId: number
) {
	await db.transaction(async (tx) => {
		const [providerEntry] = await tx
			.select()
			.from(provider)
			.where(eq(provider[ProviderKeys.ID], providerId))
			.limit(1);

		if (!providerEntry) {
			return;
		}

		const [existingEntry] = await tx
			.select()
			.from(credential)
			.where(
				and(
					eq(credential[CredentialKeys.USER_ID], userId),
					eq(credential[CredentialKeys.PROVIDER_ID], providerId)
				)
			)
			.limit(1);

		if (!existingEntry) {
			const [newCredential] = await tx
				.insert(credential)
				.values({
					[CredentialKeys.USER_ID]: userId,
					[CredentialKeys.PROVIDER_ID]: providerId,
					[CredentialKeys.CREDENTIALS]: credentialsData
				})
				.returning();

			if (providerEntry[ProviderKeys.ID] != StorageProvider.FIFE) {
				await addStorage(
					tx,
					userId,
					newCredential[CredentialKeys.ID],
					providerEntry[ProviderKeys.FREE_BYTES],
					providerEntry[ProviderKeys.FREE_BYTES],
					providerEntry[ProviderKeys.PRIORITY],
					{}
				);
			}
		} else {
			await tx
				.update(credential)
				.set({
					[CredentialKeys.CREDENTIALS]: credentialsData
				})
				.where(eq(credential[CredentialKeys.ID], existingEntry[CredentialKeys.ID]));
		}
	});
}

export async function getUserCredential(db: Db | Tx, userId: number, providerId: number) {
	const [res] = await db
		.select()
		.from(credential)
		.where(
			and(
				eq(credential[CredentialKeys.USER_ID], userId),
				eq(credential[CredentialKeys.PROVIDER_ID], providerId)
			)
		)
		.limit(1);
	return res;
}

export async function getCredentials(db: Db | Tx, id: number) {
	const [res] = await db
		.select()
		.from(credential)
		.where(eq(credential[CredentialKeys.ID], id))
		.limit(1);
	return res;
}

export async function getCredentialByStorageId(db: Db | Tx, userId: number, storageId: number) {
	const storage = await getStorage(db, storageId);
	if (storage && storage[StorageKeys.USER_ID] == userId) {
		return await getCredentials(db, storage[StorageKeys.CREDENTIAL_ID]);
	} else {
		return undefined;
	}
}

export async function markCredentialsUpdating(db: Db | Tx, Id: number) {
	return await db
		.update(credential)
		.set({ [CredentialKeys.UPDATING]: 1 })
		.where(and(eq(credential[CredentialKeys.ID], Id), eq(credential[CredentialKeys.UPDATING], 0)))
		.returning();
}

export async function markCredentialsUpdated(db: Db | Tx, Id: number) {
	await db
		.update(credential)
		.set({ [CredentialKeys.UPDATING]: 0 })
		.where(eq(credential[CredentialKeys.ID], Id));
}

export async function updateCredentials(db: Db | Tx, Id: number, creds: any) {
	await db
		.update(credential)
		.set({
			[CredentialKeys.CREDENTIALS]: creds,
			[CredentialKeys.UPDATING]: 0
		})
		.where(eq(credential[CredentialKeys.ID], Id));
}

export async function addStorage(
	db: Db | Tx,
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

export async function getStorage(db: Db | Tx, id: number) {
	const [res] = await db.select().from(storage).where(eq(storage[StorageKeys.ID], id)).limit(1);
	return res;
}

export async function getOptimalStorage(db: Db | Tx, userId: number, fileSizeBytes: number) {
	const planData = await getUserData(db, userId);
	let planExpiresAt = 0;
	if (planData) {
		planExpiresAt = planData.planExpiresAt;
	}
	const hasPlan = planExpiresAt > Date.now();
	const storageKey = hasPlan ? StorageKeys.LIMIT_BYTES : StorageKeys.LIMIT_FREE_BYTES;

	const pendingReservedBytes = sql`(
        SELECT COALESCE(SUM(${tempStorage[TempStorageKeys.SIZE]}), 0) 
        FROM ${tempStorage} 
        WHERE ${tempStorage[TempStorageKeys.STORAGE_ID]} = ${storage[StorageKeys.ID]}
    )`;

	const [availableStorage] = await db
		.select()
		.from(storage)
		.where(
			and(
				eq(storage[StorageKeys.USER_ID], userId),
				sql`${storage[storageKey]} - ${storage[StorageKeys.USED_BYTES]} - ${pendingReservedBytes} >= ${fileSizeBytes}`
			)
		)
		.orderBy(desc(storage[StorageKeys.PRIORITY]))
		.limit(1);

	return availableStorage;
}

export async function updateStorageUsedSize(
	db: Db | Tx,
	storageId: number,
	userId: number,
	bytes: number,
	add: boolean
) {
	const newBytes = add
		? sql`${storage[StorageKeys.USED_BYTES]} + ${bytes}`
		: sql`MAX(0, ${storage[StorageKeys.USED_BYTES]} - ${bytes})`;

	await db
		.update(storage)
		.set({
			[StorageKeys.USED_BYTES]: newBytes
		})
		.where(and(eq(storage[StorageKeys.USER_ID], userId), eq(storage[StorageKeys.ID], storageId)));
}

export async function updateTempStorageSize(
	db: Db | Tx,
	userId: number,
	fileId: number,
	bytes: number
) {
	const [row] = await db
		.select()
		.from(tempStorage)
		.where(
			and(
				eq(tempStorage[TempStorageKeys.USER_ID], userId),
				eq(tempStorage[TempStorageKeys.FILE_ID], fileId)
			)
		)
		.limit(1);

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

export async function getTempStorage(db: Db | Tx, userId: number, fileId: number) {
	const [res] = await db
		.select()
		.from(tempStorage)
		.where(
			and(
				eq(tempStorage[TempStorageKeys.USER_ID], userId),
				eq(tempStorage[TempStorageKeys.FILE_ID], fileId)
			)
		)
		.limit(1);
	return res;
}

export async function addTempStorage(
	db: Db | Tx,
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

export async function getUserFile(db: Db | Tx, userId: number, fileHash: string) {
	const [res] = await db
		.select()
		.from(file)
		.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)))
		.limit(1);
	return res;
}

export async function getUserFilePart(
	db: Db | Tx,
	userId: number,
	fileId: number,
	partNumber: number
) {
	const [res] = await db
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
		.limit(1);
	return res;
}

export async function resetUserFilePart(
	db: Db | Tx,
	userId: number,
	fileId: number,
	partNumber: number
) {
	return await db
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
		);
}

export async function resetUserFileByHash(db: Db | Tx, userId: number, fileHash: string) {
	return await db
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
		.where(and(eq(file[FileKeys.USER_ID], userId), eq(file[FileKeys.FILE_HASH], fileHash)));
}

export async function getProviders(db: Db | Tx) {
	return await db
		.select({
			id: provider[ProviderKeys.ID],
			title: provider[ProviderKeys.TITLE],
			bytes: provider[ProviderKeys.FREE_BYTES]
		})
		.from(provider);
}

export async function getUserStorage(db: Db | Tx, userId: number) {
	const fifeUser = await getUserBySupabaseId(db, 'fife');
	if (!fifeUser) {
		return [];
	}
	const [allProviders, userCredentials, userStorages] = await Promise.all([
		db.select().from(provider),
		db
			.select()
			.from(credential)
			.where(inArray(credential[CredentialKeys.USER_ID], [userId, fifeUser[UserKeys.ID]])),
		db.select().from(storage).where(eq(storage[StorageKeys.USER_ID], userId))
	]);

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
