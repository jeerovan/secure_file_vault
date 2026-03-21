import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import {
	UserKeys,
	UserDataKeys,
	UserDeviceKeys,
	FileKeys,
	PartKeys,
	ItemKeys,
	CredentialsKeys,
	StorageKeys,
	TempStorageKeys
} from './keys';
import { json } from 'stream/consumers';

export const user = sqliteTable('user', {
	[UserKeys.ID]: text(UserKeys.ID).primaryKey(), // Supabase user id
	[UserKeys.SERVER_CREATED_AT]: integer(UserKeys.SERVER_CREATED_AT, { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	[UserKeys.SERVER_UPDATED_AT]: integer(UserKeys.SERVER_UPDATED_AT, { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[UserKeys.EMAIL]: text(UserKeys.EMAIL).notNull().unique(),
	[UserKeys.CIPHER]: text(UserKeys.CIPHER).notNull(),
	[UserKeys.NONCE]: text(UserKeys.NONCE).notNull()
});

export const userData = sqliteTable('user_data', {
	[UserDataKeys.ID]: text(UserDataKeys.ID).primaryKey(), // Supabase user id
	[UserDataKeys.SERVER_CREATED_AT]: integer(UserDataKeys.SERVER_CREATED_AT, { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	[UserDataKeys.SERVER_UPDATED_AT]: integer(UserDataKeys.SERVER_UPDATED_AT, { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[UserDataKeys.USER_NAME]: text(UserDataKeys.USER_NAME).unique(),
	[UserDataKeys.DEVICE_ID]: text(UserDataKeys.DEVICE_ID).notNull(),
	[UserDataKeys.PLAN_TYPE]: integer(UserDataKeys.PLAN_TYPE).notNull().default(0), // Plan Type: Free/Paid, Default: Free
	[UserDataKeys.PROFILE_IMAGE]: text(UserDataKeys.PROFILE_IMAGE),
	[UserDataKeys.PLAN_EXPIRES_AT]: integer(UserDataKeys.PLAN_EXPIRES_AT, { mode: 'timestamp' }) // Plan expires at. Can be null for free plan
});

export const userDevice = sqliteTable('user_device', {
	[UserDeviceKeys.ID]: text(UserDeviceKeys.ID).primaryKey(), // UserId_DeviceId
	[UserDeviceKeys.SERVER_CREATED_AT]: integer(UserDeviceKeys.SERVER_CREATED_AT, {
		mode: 'timestamp'
	})
		.notNull()
		.$defaultFn(() => new Date()),
	[UserDeviceKeys.SERVER_UPDATED_AT]: integer(UserDeviceKeys.SERVER_UPDATED_AT, {
		mode: 'timestamp'
	})
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[UserDeviceKeys.USER_ID]: text(UserDeviceKeys.USER_ID).notNull(),
	[UserDeviceKeys.TITLE]: text(UserDeviceKeys.TITLE).notNull(),
	[UserDeviceKeys.DEVICE_TYPE]: integer(UserDeviceKeys.DEVICE_TYPE).notNull().default(0), // Device Type -> 1:Android/2:iOS/3:MacOS/4:Windows/5:Linux
	[UserDeviceKeys.NOTIFICATION_ID]: text(UserDeviceKeys.NOTIFICATION_ID), // Notification Id (FCM ID)
	[UserDeviceKeys.STATUS]: integer(UserDeviceKeys.STATUS).default(1) // Status -> 1:Active/0:Inactive
});

export const file = sqliteTable('file', {
	[FileKeys.ID]: text(FileKeys.ID).primaryKey(), // UserId_FileHash
	[FileKeys.SERVER_CREATED_AT]: integer(FileKeys.SERVER_CREATED_AT, { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	[FileKeys.SERVER_UPDATED_AT]: integer(FileKeys.SERVER_UPDATED_AT, { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[FileKeys.USER_ID]: text(FileKeys.USER_ID).notNull(),
	[FileKeys.DEVICE_ID]: text(FileKeys.DEVICE_ID).notNull(),
	[FileKeys.ITEMS_COUNT]: integer(FileKeys.ITEMS_COUNT).notNull().default(0),
	[FileKeys.PARTS]: integer(FileKeys.PARTS).notNull().default(0),
	[FileKeys.PARTS_UPLOADED]: integer(FileKeys.PARTS_UPLOADED).notNull().default(0),
	[FileKeys.UPLOADED_AT]: integer(FileKeys.UPLOADED_AT).notNull().default(0),
	[FileKeys.PROVIDER]: integer(FileKeys.PROVIDER).default(0), // Provider: FiFe, Backblaze, Cloudflare etc.
	[FileKeys.STORAGE_ID]: text(FileKeys.STORAGE_ID), // Storage
	[FileKeys.JSON]: text(FileKeys.JSON, { mode: 'json' }),
	[FileKeys.CLIENT_UPDATED_AT]: integer(FileKeys.CLIENT_UPDATED_AT).notNull().default(0),
	[FileKeys.DELETED]: integer(FileKeys.DELETED).notNull().default(0)
});

export const part = sqliteTable('part', {
	[PartKeys.ID]: text(PartKeys.ID).primaryKey(), // UserId_FileHash_PartNumber
	[PartKeys.SERVER_CREATED_AT]: integer(PartKeys.SERVER_CREATED_AT, { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	[PartKeys.SERVER_UPDATED_AT]: integer(PartKeys.SERVER_UPDATED_AT, { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[PartKeys.USER_ID]: text(PartKeys.USER_ID).notNull(),
	[PartKeys.DEVICE_ID]: text(PartKeys.DEVICE_ID).notNull(),
	[PartKeys.PART_SIZE]: integer(PartKeys.PART_SIZE).notNull(),
	[PartKeys.CIPHER]: text(PartKeys.CIPHER),
	[PartKeys.NONCE]: text(PartKeys.NONCE),
	[PartKeys.JSON]: text(PartKeys.JSON, { mode: 'json' }),
	[PartKeys.CLIENT_UPDATED_AT]: integer(PartKeys.CLIENT_UPDATED_AT).notNull().default(0),
	[PartKeys.DELETED]: integer(PartKeys.DELETED).notNull().default(0)
});

export const item = sqliteTable('item', {
	[ItemKeys.ID]: text(ItemKeys.ID).primaryKey(), // UserId_UUID
	[ItemKeys.SERVER_CREATED_AT]: integer(ItemKeys.SERVER_CREATED_AT, { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	[ItemKeys.SERVER_UPDATED_AT]: integer(ItemKeys.SERVER_UPDATED_AT, { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[ItemKeys.USER_ID]: text(ItemKeys.USER_ID).notNull(),
	[ItemKeys.DEVICE_ID]: text(ItemKeys.DEVICE_ID).notNull(),
	[ItemKeys.TEXT_CIPHER]: text(ItemKeys.TEXT_CIPHER).notNull(),
	[ItemKeys.TEXT_NONCE]: text(ItemKeys.TEXT_NONCE).notNull(),
	[ItemKeys.KEY_CIPHER]: text(ItemKeys.KEY_CIPHER).notNull(),
	[ItemKeys.KEY_NONCE]: text(ItemKeys.KEY_NONCE).notNull(),
	[ItemKeys.CLIENT_UPDATED_AT]: integer(ItemKeys.CLIENT_UPDATED_AT).notNull().default(0)
});

export const credentials = sqliteTable('credentials', {
	[CredentialsKeys.ID]: text(CredentialsKeys.ID).primaryKey(), // Provider Account Id
	[CredentialsKeys.SERVER_CREATED_AT]: integer(CredentialsKeys.SERVER_CREATED_AT, {
		mode: 'timestamp'
	})
		.notNull()
		.$defaultFn(() => new Date()),
	[CredentialsKeys.SERVER_UPDATED_AT]: integer(CredentialsKeys.SERVER_UPDATED_AT, {
		mode: 'timestamp'
	})
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[CredentialsKeys.OWNER_ID]: text(CredentialsKeys.OWNER_ID).notNull(), // Either a user ID, or 'fife'
	[CredentialsKeys.PROVIDER]: integer(CredentialsKeys.PROVIDER).notNull(), // Provider: 'fife', 'backblaze', 'cloudflare'
	[CredentialsKeys.CREDENTIALS]: text(CredentialsKeys.CREDENTIALS, { mode: 'json' }).notNull(),
	[CredentialsKeys.UPDATING]: integer(CredentialsKeys.UPDATING).notNull().default(0)
});

export const storage = sqliteTable('storage', {
	[StorageKeys.ID]: text(StorageKeys.ID)
		.primaryKey()
		.$defaultFn(() => crypto.randomUUID()),
	[StorageKeys.SERVER_CREATED_AT]: integer(StorageKeys.SERVER_CREATED_AT, { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	[StorageKeys.SERVER_UPDATED_AT]: integer(StorageKeys.SERVER_UPDATED_AT, { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[StorageKeys.USER_ID]: text(StorageKeys.USER_ID).notNull(),
	[StorageKeys.CREDENTIALS_ID]: text(StorageKeys.CREDENTIALS_ID).notNull(),
	[StorageKeys.LIMIT_BYTES]: integer(StorageKeys.LIMIT_BYTES).notNull(),
	[StorageKeys.USED_BYTES]: integer(StorageKeys.USED_BYTES).default(0).notNull(),
	[StorageKeys.PRIORITY]: integer(StorageKeys.PRIORITY).notNull().default(0)
});

export const tempStorage = sqliteTable('temp_storage', {
	[TempStorageKeys.ID]: text(TempStorageKeys.ID).primaryKey(), // UserId_FileHash
	[TempStorageKeys.SERVER_CREATED_AT]: integer(TempStorageKeys.SERVER_CREATED_AT, {
		mode: 'timestamp'
	})
		.notNull()
		.$defaultFn(() => new Date()),
	[TempStorageKeys.SERVER_UPDATED_AT]: integer(TempStorageKeys.SERVER_UPDATED_AT, {
		mode: 'timestamp'
	})
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	[TempStorageKeys.USER_ID]: text(TempStorageKeys.USER_ID).notNull(),
	[TempStorageKeys.STORAGE_ID]: text(TempStorageKeys.STORAGE_ID).notNull(),
	[TempStorageKeys.SIZE]: integer(TempStorageKeys.SIZE).notNull(),
	[TempStorageKeys.PROVIDER]: integer(TempStorageKeys.PROVIDER).notNull()
});
