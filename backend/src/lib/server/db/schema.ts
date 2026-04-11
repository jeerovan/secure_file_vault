import { integer, sqliteTable, text, index } from 'drizzle-orm/sqlite-core';
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
  DEVICE_ID to track Made changes by, changes on logout->login
	DEVICE_HASH for a user for its particular device, fixed, wont change, derived from user key
*/
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

export const user = sqliteTable('user', {
	[UserKeys.ID]: integer(UserKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
	[UserKeys.SERVER_CREATED_AT]: integer(UserKeys.SERVER_CREATED_AT)
		.notNull()
		.$defaultFn(() => Date.now()),
	[UserKeys.SERVER_UPDATED_AT]: integer(UserKeys.SERVER_UPDATED_AT)
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserKeys.SUPABASE_ID]: text(UserKeys.SUPABASE_ID).notNull().unique(),
	[UserKeys.EMAIL]: text(UserKeys.EMAIL).notNull().unique(),
	[UserKeys.CIPHER]: text(UserKeys.CIPHER).notNull(),
	[UserKeys.NONCE]: text(UserKeys.NONCE).notNull()
});

export const credential = sqliteTable(
	'credential',
	{
		[CredentialKeys.ID]: integer(CredentialKeys.ID, { mode: 'number' }).primaryKey({
			autoIncrement: true
		}),
		[CredentialKeys.SERVER_CREATED_AT]: integer(CredentialKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[CredentialKeys.SERVER_UPDATED_AT]: integer(CredentialKeys.SERVER_UPDATED_AT)
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[CredentialKeys.USER_ID]: integer(CredentialKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[CredentialKeys.PROVIDER_ID]: integer(CredentialKeys.PROVIDER_ID)
			.notNull()
			.references(() => provider[ProviderKeys.ID], { onDelete: 'cascade' }),
		[CredentialKeys.CREDENTIALS]: text(CredentialKeys.CREDENTIALS, { mode: 'json' }).notNull(),
		[CredentialKeys.UPDATING]: integer(CredentialKeys.UPDATING).notNull().default(0)
	},
	(table) => [
		index('credential_idx_user_id_provider_id').on(
			table[CredentialKeys.USER_ID],
			table[CredentialKeys.PROVIDER_ID]
		)
	]
);

export const storage = sqliteTable(
	'storage',
	{
		[StorageKeys.ID]: integer(StorageKeys.ID, { mode: 'number' }).primaryKey({
			autoIncrement: true
		}),
		[StorageKeys.SERVER_CREATED_AT]: integer(StorageKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[StorageKeys.SERVER_UPDATED_AT]: integer(StorageKeys.SERVER_UPDATED_AT)
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[StorageKeys.USER_ID]: integer(StorageKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[StorageKeys.CREDENTIAL_ID]: integer(StorageKeys.CREDENTIAL_ID)
			.notNull()
			.references(() => credential[CredentialKeys.ID], { onDelete: 'cascade' }),
		[StorageKeys.LIMIT_BYTES]: integer(StorageKeys.LIMIT_BYTES).notNull(),
		[StorageKeys.USED_BYTES]: integer(StorageKeys.USED_BYTES).default(0).notNull(),
		[StorageKeys.PRIORITY]: integer(StorageKeys.PRIORITY).notNull().default(0),
		[StorageKeys.JSON]: text(StorageKeys.JSON, { mode: 'json' }).notNull(),
		[StorageKeys.LIMIT_FREE_BYTES]: integer(StorageKeys.LIMIT_FREE_BYTES).notNull()
	},
	(table) => [index('storage_idx_user_id').on(table[StorageKeys.USER_ID])]
);

export const tempStorage = sqliteTable(
	'temp_storage',
	{
		[TempStorageKeys.ID]: integer(TempStorageKeys.ID, { mode: 'number' }).primaryKey({
			autoIncrement: true
		}),
		[TempStorageKeys.SERVER_CREATED_AT]: integer(TempStorageKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[TempStorageKeys.SERVER_UPDATED_AT]: integer(TempStorageKeys.SERVER_UPDATED_AT)
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
		[TempStorageKeys.SIZE]: integer(TempStorageKeys.SIZE).notNull(),
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
	[UserDataKeys.USER_ID]: integer(UserDataKeys.USER_ID)
		.notNull()
		.unique() // <- Creates index internally
		.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
	[UserDataKeys.USER_NAME]: text(UserDataKeys.USER_NAME).unique(),
	[UserDataKeys.DEVICE_UUID]: text(UserDataKeys.DEVICE_UUID).notNull(), // To track made changes by
	[UserDataKeys.PROFILE_IMAGE]: text(UserDataKeys.PROFILE_IMAGE),
	[UserDataKeys.PRO_ID]: text(UserDataKeys.PRO_ID),
	[UserDataKeys.PLAN_EXPIRES_AT]: integer(UserDataKeys.PLAN_EXPIRES_AT).notNull().default(0) // Plan expires at
});

export const userDevice = sqliteTable(
	'user_device',
	{
		[UserDeviceKeys.ID]: integer(UserDeviceKeys.ID, { mode: 'number' }).primaryKey({
			autoIncrement: true
		}),
		[UserDeviceKeys.SERVER_CREATED_AT]: integer(UserDeviceKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[UserDeviceKeys.SERVER_UPDATED_AT]: integer(UserDeviceKeys.SERVER_UPDATED_AT)
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

export const file = sqliteTable(
	'file',
	{
		[FileKeys.ID]: integer(FileKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
		[FileKeys.SERVER_CREATED_AT]: integer(FileKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[FileKeys.SERVER_UPDATED_AT]: integer(FileKeys.SERVER_UPDATED_AT)
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[FileKeys.USER_ID]: integer(FileKeys.USER_ID)
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		[FileKeys.FILE_HASH]: text(FileKeys.FILE_HASH).notNull(),
		[FileKeys.DEVICE_UUID]: text(FileKeys.DEVICE_UUID).notNull(),
		[FileKeys.ITEMS_COUNT]: integer(FileKeys.ITEMS_COUNT).notNull().default(0),
		[FileKeys.PARTS]: integer(FileKeys.PARTS).notNull().default(0),
		[FileKeys.UPLOADED_AT]: integer(FileKeys.UPLOADED_AT).notNull().default(0),
		[FileKeys.PROVIDER_ID]: integer(FileKeys.PROVIDER_ID).references(
			() => provider[ProviderKeys.ID],
			{ onDelete: 'cascade' }
		),
		[FileKeys.STORAGE_ID]: integer(FileKeys.STORAGE_ID).references(() => storage[StorageKeys.ID], {
			onDelete: 'cascade'
		}),
		[FileKeys.JSON]: text(FileKeys.JSON, { mode: 'json' }),
		[FileKeys.CLIENT_UPDATED_AT]: integer(FileKeys.CLIENT_UPDATED_AT).notNull().default(0),
		[FileKeys.DELETED]: integer(FileKeys.DELETED).notNull().default(0)
	},
	(table) => [
		index('file_idx_user_id_file_hash').on(table[FileKeys.USER_ID], table[FileKeys.FILE_HASH]),
		index('file_idx_user_id').on(table[FileKeys.USER_ID])
	]
);

export const part = sqliteTable(
	'part',
	{
		[PartKeys.ID]: integer(PartKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
		[PartKeys.SERVER_CREATED_AT]: integer(PartKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[PartKeys.SERVER_UPDATED_AT]: integer(PartKeys.SERVER_UPDATED_AT)
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
		[PartKeys.JSON]: text(PartKeys.JSON, { mode: 'json' }),
		[PartKeys.CLIENT_UPDATED_AT]: integer(PartKeys.CLIENT_UPDATED_AT).notNull().default(0),
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

export const item = sqliteTable(
	'item',
	{
		[ItemKeys.ID]: integer(ItemKeys.ID, { mode: 'number' }).primaryKey({ autoIncrement: true }),
		[ItemKeys.SERVER_CREATED_AT]: integer(ItemKeys.SERVER_CREATED_AT)
			.notNull()
			.$defaultFn(() => Date.now()),
		[ItemKeys.SERVER_UPDATED_AT]: integer(ItemKeys.SERVER_UPDATED_AT)
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
		[ItemKeys.CLIENT_UPDATED_AT]: integer(ItemKeys.CLIENT_UPDATED_AT).notNull().default(0)
	},
	(table) => [
		index('item_idx_user_id').on(table[ItemKeys.USER_ID]),
		index('item_idx_user_id_item_id').on(table[ItemKeys.USER_ID], table[ItemKeys.ITEM_ID])
	]
);
