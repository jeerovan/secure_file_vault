import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import {
	UserKeys,
	UserDataKeys,
	UserDeviceKeys,
	FileKeys,
	PartKeys,
	ItemKeys,
	CredentialKeys,
	StorageKeys,
	TempStorageKeys,
	ProviderKeys
} from './keys';

// USER_ID -> Supabase user id
export const user = sqliteTable('user', {
	[UserKeys.ID]: integer(UserKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
	[UserKeys.SERVER_CREATED_AT]: integer(UserKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[UserKeys.SERVER_UPDATED_AT]: integer(UserKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserKeys.USER_ID]: text(UserKeys.USER_ID).notNull().unique(),
	[UserKeys.EMAIL]: text(UserKeys.EMAIL).notNull().unique(),
	[UserKeys.CIPHER]: text(UserKeys.CIPHER).notNull(),
	[UserKeys.NONCE]: text(UserKeys.NONCE).notNull()
});

export const userData = sqliteTable('user_data', {
	[UserDataKeys.ID]: integer(UserDataKeys.ID, { mode: 'number' }).primaryKey({
		autoIncrement: true
	}),
	[UserDataKeys.SERVER_CREATED_AT]: integer(UserDataKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[UserDataKeys.SERVER_UPDATED_AT]: integer(UserDataKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserKeys.USER_ID]: text(UserKeys.USER_ID).notNull().unique(),
	[UserDataKeys.USER_NAME]: text(UserDataKeys.USER_NAME).unique(),
	[UserDataKeys.DEVICE_ID]: text(UserDataKeys.DEVICE_ID).notNull(), // Made changes by
	[UserDataKeys.PROFILE_IMAGE]: text(UserDataKeys.PROFILE_IMAGE),
	[UserDataKeys.PRO_ID]: text(UserDataKeys.PRO_ID),
	[UserDataKeys.PLAN_EXPIRES_AT]: integer(UserDataKeys.PLAN_EXPIRES_AT).notNull().default(0) // Plan expires at
});

export const userDevice = sqliteTable('user_device', {
	[UserDeviceKeys.ID]: integer(UserDeviceKeys.ID, { mode: 'number' }).primaryKey({
		autoIncrement: true
	}),
	[UserDeviceKeys.SERVER_CREATED_AT]: integer(UserDeviceKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[UserDeviceKeys.SERVER_UPDATED_AT]: integer(UserDeviceKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserDeviceKeys.USER_ID]: text(UserDeviceKeys.USER_ID).notNull(),
	[UserDeviceKeys.DEVICE_ID]: text(UserDeviceKeys.DEVICE_ID).notNull(),
	[UserDeviceKeys.TITLE]: text(UserDeviceKeys.TITLE).notNull(),
	[UserDeviceKeys.DEVICE_TYPE]: integer(UserDeviceKeys.DEVICE_TYPE).notNull().default(0), // Device Type -> 1:Android/2:iOS/3:MacOS/4:Windows/5:Linux
	[UserDeviceKeys.NOTIFICATION_ID]: text(UserDeviceKeys.NOTIFICATION_ID), // Notification Id (FCM ID)
	[UserDeviceKeys.STATUS]: integer(UserDeviceKeys.STATUS).default(1) // Status -> 1:Active/0:Inactive
});

export const file = sqliteTable('file', {
	[FileKeys.ID]: integer(FileKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
	[FileKeys.SERVER_CREATED_AT]: integer(FileKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[FileKeys.SERVER_UPDATED_AT]: integer(FileKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[FileKeys.USER_ID]: text(FileKeys.USER_ID).notNull(),
	[FileKeys.FILE_ID]: text(FileKeys.FILE_ID).notNull(),
	[FileKeys.DEVICE_ID]: text(FileKeys.DEVICE_ID).notNull(),
	[FileKeys.ITEMS_COUNT]: integer(FileKeys.ITEMS_COUNT).notNull().default(0),
	[FileKeys.PARTS]: integer(FileKeys.PARTS).notNull().default(0),
	[FileKeys.UPLOADED_AT]: integer(FileKeys.UPLOADED_AT).notNull().default(0),
	[FileKeys.PROVIDER]: integer(FileKeys.PROVIDER).default(0), // Provider: FiFe, Backblaze, Cloudflare etc.
	[FileKeys.STORAGE_ID]: text(FileKeys.STORAGE_ID), // Storage
	[FileKeys.JSON]: text(FileKeys.JSON, { mode: 'json' }),
	[FileKeys.CLIENT_UPDATED_AT]: integer(FileKeys.CLIENT_UPDATED_AT).notNull().default(0),
	[FileKeys.DELETED]: integer(FileKeys.DELETED).notNull().default(0)
});

export const part = sqliteTable('part', {
	[PartKeys.ID]: integer(PartKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
	[PartKeys.SERVER_CREATED_AT]: integer(PartKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[PartKeys.SERVER_UPDATED_AT]: integer(PartKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[PartKeys.USER_ID]: text(PartKeys.USER_ID).notNull(),
	[PartKeys.DEVICE_ID]: text(PartKeys.DEVICE_ID).notNull(),
	[PartKeys.FILE_ID]: text(PartKeys.FILE_ID).notNull(),
	[PartKeys.PART]: integer(PartKeys.PART).notNull().default(0),
	[PartKeys.PART_SIZE]: integer(PartKeys.PART_SIZE).notNull().default(0),
	[PartKeys.CIPHER]: text(PartKeys.CIPHER),
	[PartKeys.NONCE]: text(PartKeys.NONCE),
	[PartKeys.JSON]: text(PartKeys.JSON, { mode: 'json' }),
	[PartKeys.CLIENT_UPDATED_AT]: integer(PartKeys.CLIENT_UPDATED_AT).notNull().default(0),
	[PartKeys.DELETED]: integer(PartKeys.DELETED).notNull().default(0),
	[PartKeys.UPLOADED]: integer(PartKeys.UPLOADED).notNull().default(0)
});

export const item = sqliteTable('item', {
	[ItemKeys.ID]: integer(ItemKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
	[ItemKeys.SERVER_CREATED_AT]: integer(ItemKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[ItemKeys.SERVER_UPDATED_AT]: integer(ItemKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[ItemKeys.ITEM_ID]: text(ItemKeys.ITEM_ID).notNull(),
	[ItemKeys.USER_ID]: text(ItemKeys.USER_ID).notNull(),
	[ItemKeys.DEVICE_ID]: text(ItemKeys.DEVICE_ID).notNull(),
	[ItemKeys.TEXT_CIPHER]: text(ItemKeys.TEXT_CIPHER).notNull(),
	[ItemKeys.TEXT_NONCE]: text(ItemKeys.TEXT_NONCE).notNull(),
	[ItemKeys.KEY_CIPHER]: text(ItemKeys.KEY_CIPHER).notNull(),
	[ItemKeys.KEY_NONCE]: text(ItemKeys.KEY_NONCE).notNull(),
	[ItemKeys.CLIENT_UPDATED_AT]: integer(ItemKeys.CLIENT_UPDATED_AT).notNull().default(0)
});

export const credentials = sqliteTable('credentials', {
	[CredentialKeys.ID]: integer(CredentialKeys.ID, { mode: 'number' }).primaryKey({
		autoIncrement: true
	}),
	[CredentialKeys.SERVER_CREATED_AT]: integer(CredentialKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[CredentialKeys.SERVER_UPDATED_AT]: integer(CredentialKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[CredentialKeys.OWNER_ID]: text(CredentialKeys.OWNER_ID).notNull(), // Either a user ID, or 'fife'
	[CredentialKeys.PROVIDER_ID]: integer(CredentialKeys.PROVIDER_ID).notNull(), // Provider: 'fife', 'backblaze', 'cloudflare'
	[CredentialKeys.CREDENTIALS]: text(CredentialKeys.CREDENTIALS, { mode: 'json' }).notNull(),
	[CredentialKeys.UPDATING]: integer(CredentialKeys.UPDATING).notNull().default(0)
});

export const storage = sqliteTable('storage', {
	[StorageKeys.ID]: integer(StorageKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
	[StorageKeys.SERVER_CREATED_AT]: integer(StorageKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[StorageKeys.SERVER_UPDATED_AT]: integer(StorageKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[StorageKeys.USER_ID]: text(StorageKeys.USER_ID).notNull(),
	[StorageKeys.CREDENTIAL_ID]: text(StorageKeys.CREDENTIAL_ID).notNull(),
	[StorageKeys.LIMIT_BYTES]: integer(StorageKeys.LIMIT_BYTES).notNull(),
	[StorageKeys.USED_BYTES]: integer(StorageKeys.USED_BYTES).default(0).notNull(),
	[StorageKeys.PRIORITY]: integer(StorageKeys.PRIORITY).notNull().default(0),
	[StorageKeys.JSON]: text(StorageKeys.JSON, { mode: 'json' }).notNull(),
	[StorageKeys.LIMIT_FREE_BYTES]: integer(StorageKeys.LIMIT_FREE_BYTES).notNull()
});

export const provider = sqliteTable('provider', {
	[ProviderKeys.ID]: integer(ProviderKeys.ID, { mode: 'number' }).primaryKey({
		autoIncrement: true
	}),
	[ProviderKeys.SERVER_CREATED_AT]: integer(ProviderKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[ProviderKeys.SERVER_UPDATED_AT]: integer(ProviderKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[ProviderKeys.TITLE]: text(ProviderKeys.TITLE).notNull(),
	[ProviderKeys.FREE_BYTES]: integer(ProviderKeys.FREE_BYTES).notNull(),
	[ProviderKeys.PRIORITY]: integer(ProviderKeys.PRIORITY).notNull()
});

export const tempStorage = sqliteTable('temp_storage', {
	[TempStorageKeys.ID]: integer(TempStorageKeys.ID, { mode: 'number' }).primaryKey({
		autoIncrement: true
	}),
	[TempStorageKeys.SERVER_CREATED_AT]: integer(TempStorageKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[TempStorageKeys.SERVER_UPDATED_AT]: integer(TempStorageKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[TempStorageKeys.USER_ID]: text(TempStorageKeys.USER_ID).notNull(),
	[TempStorageKeys.FILE_ID]: text(TempStorageKeys.FILE_ID).notNull(),
	[TempStorageKeys.STORAGE_ID]: text(TempStorageKeys.STORAGE_ID).notNull(),
	[TempStorageKeys.SIZE]: integer(TempStorageKeys.SIZE).notNull(),
	[TempStorageKeys.PROVIDER_ID]: integer(TempStorageKeys.PROVIDER_ID).notNull()
});
