import { pgTable, serial, integer, bigint, text, index, jsonb } from 'drizzle-orm/pg-core';
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

/* -- Keys --
  DEVICE_ID to track Made changes by, it changes on logout->login
	DEVICE_HASH for a user for its particular device, fixed, wont change, derived from user key
*/
export const provider = pgTable('provider', {
	[ProviderKeys.ID]: serial(ProviderKeys.ID).primaryKey(),
	[ProviderKeys.SERVER_CREATED_AT]: bigint(ProviderKeys.SERVER_CREATED_AT, { mode: 'number' })
		.notNull()
		.$defaultFn(() => Date.now()),

	[ProviderKeys.SERVER_UPDATED_AT]: bigint(ProviderKeys.SERVER_UPDATED_AT, { mode: 'number' })
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[ProviderKeys.TITLE]: text(ProviderKeys.TITLE).notNull(),
	[ProviderKeys.FREE_BYTES]: bigint(ProviderKeys.FREE_BYTES, { mode: 'number' }).notNull(),
	[ProviderKeys.PRIORITY]: integer(ProviderKeys.PRIORITY).notNull()
});

export const user = pgTable('user', {
	[UserKeys.ID]: serial(UserKeys.ID).primaryKey(),
	[UserKeys.SERVER_CREATED_AT]: bigint(UserKeys.SERVER_CREATED_AT, { mode: 'number' })
		.notNull()
		.$defaultFn(() => Date.now()),
	[UserKeys.SERVER_UPDATED_AT]: bigint(UserKeys.SERVER_UPDATED_AT, { mode: 'number' })
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserKeys.SUPABASE_ID]: text(UserKeys.SUPABASE_ID).notNull().unique(),
	[UserKeys.EMAIL]: text(UserKeys.EMAIL).notNull().unique(),
	[UserKeys.CIPHER]: text(UserKeys.CIPHER).notNull(),
	[UserKeys.NONCE]: text(UserKeys.NONCE).notNull()
});

export const credential = pgTable(
	'credential',
	{
		[CredentialKeys.ID]: serial(CredentialKeys.ID).primaryKey(),
		[CredentialKeys.SERVER_CREATED_AT]: bigint(CredentialKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[CredentialKeys.SERVER_UPDATED_AT]: bigint(CredentialKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[CredentialKeys.USER_ID]: integer(CredentialKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[CredentialKeys.PROVIDER_ID]: integer(CredentialKeys.PROVIDER_ID)
			.notNull()
			.references(() => provider[ProviderKeys.ID], { onDelete: 'cascade' }),
		[CredentialKeys.CREDENTIALS]: jsonb(CredentialKeys.CREDENTIALS).notNull(),
		[CredentialKeys.UPDATING]: integer(CredentialKeys.UPDATING).notNull().default(0)
	},
	(table) => [
		index('credential_idx_user_id_provider_id').on(
			table[CredentialKeys.USER_ID],
			table[CredentialKeys.PROVIDER_ID]
		)
	]
);

export const storage = pgTable(
	'storage',
	{
		[StorageKeys.ID]: serial(StorageKeys.ID).primaryKey(),
		[StorageKeys.SERVER_CREATED_AT]: bigint(StorageKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[StorageKeys.SERVER_UPDATED_AT]: bigint(StorageKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[StorageKeys.USER_ID]: integer(StorageKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[StorageKeys.CREDENTIAL_ID]: integer(StorageKeys.CREDENTIAL_ID)
			.notNull()
			.references(() => credential[CredentialKeys.ID], { onDelete: 'cascade' }),
		[StorageKeys.LIMIT_BYTES]: bigint(StorageKeys.LIMIT_BYTES, { mode: 'number' }).notNull(),
		[StorageKeys.USED_BYTES]: bigint(StorageKeys.USED_BYTES, { mode: 'number' })
			.default(0)
			.notNull(),
		[StorageKeys.PRIORITY]: integer(StorageKeys.PRIORITY).notNull().default(0),
		[StorageKeys.JSON]: jsonb(StorageKeys.JSON).notNull(),
		[StorageKeys.LIMIT_FREE_BYTES]: bigint(StorageKeys.LIMIT_FREE_BYTES, {
			mode: 'number'
		}).notNull()
	},
	(table) => [index('storage_idx_user_id').on(table[StorageKeys.USER_ID])]
);

export const tempStorage = pgTable(
	'temp_storage',
	{
		[TempStorageKeys.ID]: serial(TempStorageKeys.ID).primaryKey(),
		[TempStorageKeys.SERVER_CREATED_AT]: bigint(TempStorageKeys.SERVER_CREATED_AT, {
			mode: 'number'
		})
			.notNull()
			.$defaultFn(() => Date.now()),
		[TempStorageKeys.SERVER_UPDATED_AT]: bigint(TempStorageKeys.SERVER_UPDATED_AT, {
			mode: 'number'
		})
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[TempStorageKeys.USER_ID]: integer(TempStorageKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[TempStorageKeys.FILE_ID]: integer(TempStorageKeys.FILE_ID)
			.notNull()
			.references(() => file[FileKeys.ID], { onDelete: 'cascade' }),
		[TempStorageKeys.STORAGE_ID]: integer(TempStorageKeys.STORAGE_ID)
			.notNull()
			.references(() => storage[StorageKeys.ID], { onDelete: 'cascade' }),
		[TempStorageKeys.SIZE]: bigint(TempStorageKeys.SIZE, { mode: 'number' }).notNull(),
		[TempStorageKeys.PROVIDER_ID]: integer(TempStorageKeys.PROVIDER_ID)
			.notNull()
			.references(() => provider[ProviderKeys.ID], { onDelete: 'cascade' })
	},
	(table) => [
		index('temp_storage_user_id_file_id').on(
			table[TempStorageKeys.USER_ID],
			table[TempStorageKeys.FILE_ID]
		)
	]
);

export const userData = pgTable('user_data', {
	[UserDataKeys.ID]: serial(UserDataKeys.ID).primaryKey(),
	[UserDataKeys.SERVER_CREATED_AT]: bigint(UserDataKeys.SERVER_CREATED_AT, { mode: 'number' })
		.notNull()
		.$defaultFn(() => Date.now()),
	[UserDataKeys.SERVER_UPDATED_AT]: bigint(UserDataKeys.SERVER_UPDATED_AT, { mode: 'number' })
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserDataKeys.USER_ID]: integer(UserDataKeys.USER_ID)
		.notNull()
		.unique() // <- Creates index internally
		.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
	[UserDataKeys.USER_NAME]: text(UserDataKeys.USER_NAME).unique(),
	[UserDataKeys.DEVICE_UUID]: text(UserDataKeys.DEVICE_UUID).notNull(), // To track made changes by
	[UserDataKeys.PROFILE_IMAGE]: text(UserDataKeys.PROFILE_IMAGE),
	[UserDataKeys.PRO_ID]: text(UserDataKeys.PRO_ID),
	[UserDataKeys.PLAN_EXPIRES_AT]: bigint(UserDataKeys.PLAN_EXPIRES_AT, { mode: 'number' })
		.notNull()
		.default(0) // Plan expires at
});

export const userDevice = pgTable(
	'user_device',
	{
		[UserDeviceKeys.ID]: serial(UserDeviceKeys.ID).primaryKey(),
		[UserDeviceKeys.SERVER_CREATED_AT]: bigint(UserDeviceKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[UserDeviceKeys.SERVER_UPDATED_AT]: bigint(UserDeviceKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[UserDeviceKeys.USER_ID]: integer(UserDeviceKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[UserDeviceKeys.DEVICE_UUID]: text(UserDeviceKeys.DEVICE_UUID).notNull(),
		[UserDeviceKeys.TITLE]: text(UserDeviceKeys.TITLE).notNull(),
		[UserDeviceKeys.DEVICE_TYPE]: integer(UserDeviceKeys.DEVICE_TYPE).notNull().default(0), // Device Type -> 1:Android/2:iOS/3:MacOS/4:Windows/5:Linux
		[UserDeviceKeys.NOTIFICATION_ID]: text(UserDeviceKeys.NOTIFICATION_ID), // Notification Id (FCM ID)
		[UserDeviceKeys.ACTIVE]: integer(UserDeviceKeys.ACTIVE).default(1)
	},
	(table) => [index('user_device_idx_user_id').on(table[UserDeviceKeys.USER_ID])]
);

export const file = pgTable(
	'file',
	{
		[FileKeys.ID]: serial(FileKeys.ID).primaryKey(),
		[FileKeys.SERVER_CREATED_AT]: bigint(FileKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[FileKeys.SERVER_UPDATED_AT]: bigint(FileKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[FileKeys.USER_ID]: integer(FileKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[FileKeys.FILE_HASH]: text(FileKeys.FILE_HASH).notNull(),
		[FileKeys.DEVICE_UUID]: text(FileKeys.DEVICE_UUID).notNull(),
		[FileKeys.ITEMS_COUNT]: integer(FileKeys.ITEMS_COUNT).notNull().default(0),
		[FileKeys.PARTS]: integer(FileKeys.PARTS).notNull().default(0),
		[FileKeys.UPLOADED_AT]: bigint(FileKeys.UPLOADED_AT, { mode: 'number' }).notNull().default(0),
		[FileKeys.PROVIDER_ID]: integer(FileKeys.PROVIDER_ID).references(
			() => provider[ProviderKeys.ID],
			{ onDelete: 'cascade' }
		),
		[FileKeys.STORAGE_ID]: integer(FileKeys.STORAGE_ID).references(() => storage[StorageKeys.ID], {
			onDelete: 'cascade'
		}),
		[FileKeys.JSON]: jsonb(FileKeys.JSON),
		[FileKeys.CLIENT_UPDATED_AT]: bigint(FileKeys.CLIENT_UPDATED_AT, { mode: 'number' })
			.notNull()
			.default(0),
		[FileKeys.DELETED]: integer(FileKeys.DELETED).notNull().default(0)
	},
	(table) => [
		index('file_idx_user_id_file_hash').on(table[FileKeys.USER_ID], table[FileKeys.FILE_HASH]),
		index('file_idx_user_id').on(table[FileKeys.USER_ID])
	]
);

export const part = pgTable(
	'part',
	{
		[PartKeys.ID]: serial(PartKeys.ID).primaryKey(),
		[PartKeys.SERVER_CREATED_AT]: bigint(PartKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[PartKeys.SERVER_UPDATED_AT]: bigint(PartKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[PartKeys.USER_ID]: integer(PartKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[PartKeys.DEVICE_UUID]: text(PartKeys.DEVICE_UUID).notNull(),
		[PartKeys.FILE_ID]: integer(PartKeys.FILE_ID)
			.notNull()
			.references(() => file[FileKeys.ID], { onDelete: 'cascade' }),
		[PartKeys.PART_NUMBER]: integer(PartKeys.PART_NUMBER).notNull().default(0),
		[PartKeys.PART_SIZE]: integer(PartKeys.PART_SIZE).notNull().default(0),
		[PartKeys.CIPHER]: text(PartKeys.CIPHER),
		[PartKeys.NONCE]: text(PartKeys.NONCE),
		[PartKeys.JSON]: jsonb(PartKeys.JSON),
		[PartKeys.CLIENT_UPDATED_AT]: bigint(PartKeys.CLIENT_UPDATED_AT, { mode: 'number' })
			.notNull()
			.default(0),
		[PartKeys.DELETED]: integer(PartKeys.DELETED).notNull().default(0),
		[PartKeys.UPLOADED]: integer(PartKeys.UPLOADED).notNull().default(0)
	},
	(table) => [
		index('part_idx_user_id_file_id_part_number').on(
			table[PartKeys.USER_ID],
			table[PartKeys.FILE_ID],
			table[PartKeys.PART_NUMBER]
		),
		index('part_idx_user_id').on(table[PartKeys.USER_ID])
	]
);

export const item = pgTable(
	'item',
	{
		[ItemKeys.ID]: serial(ItemKeys.ID).primaryKey(),
		[ItemKeys.SERVER_CREATED_AT]: bigint(ItemKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[ItemKeys.SERVER_UPDATED_AT]: bigint(ItemKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[ItemKeys.ITEM_ID]: text(ItemKeys.ITEM_ID).notNull(),
		[ItemKeys.USER_ID]: integer(ItemKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[ItemKeys.DEVICE_UUID]: text(ItemKeys.DEVICE_UUID).notNull(),
		[ItemKeys.TEXT_CIPHER]: text(ItemKeys.TEXT_CIPHER).notNull(),
		[ItemKeys.TEXT_NONCE]: text(ItemKeys.TEXT_NONCE).notNull(),
		[ItemKeys.KEY_CIPHER]: text(ItemKeys.KEY_CIPHER).notNull(),
		[ItemKeys.KEY_NONCE]: text(ItemKeys.KEY_NONCE).notNull(),
		[ItemKeys.CLIENT_UPDATED_AT]: bigint(ItemKeys.CLIENT_UPDATED_AT, { mode: 'number' })
			.notNull()
			.default(0)
	},
	(table) => [
		index('item_idx_user_id').on(table[ItemKeys.USER_ID]),
		index('item_idx_user_id_item_id').on(table[ItemKeys.USER_ID], table[ItemKeys.ITEM_ID])
	]
);
