import {
	pgTable,
	serial,
	integer,
	bigint,
	text,
	index,
	jsonb,
	primaryKey,
	check
} from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
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

export const user = pgTable(
	'user',
	{
		[UserKeys.ID]: serial(UserKeys.ID).primaryKey(),
		[UserKeys.SERVER_CREATED_AT]: bigint(UserKeys.SERVER_CREATED_AT, { mode: 'number' })
			.notNull()
			.$defaultFn(() => Date.now()),
		[UserKeys.SERVER_UPDATED_AT]: bigint(UserKeys.SERVER_UPDATED_AT, { mode: 'number' })
			.$defaultFn(() => Date.now())
			.$onUpdate(() => Date.now()),
		[UserKeys.REMOTE_AUTH_ID]: text(UserKeys.REMOTE_AUTH_ID).notNull().unique(),
		[UserKeys.EMAIL]: text(UserKeys.EMAIL).notNull().unique(),
		[UserKeys.CIPHER]: text(UserKeys.CIPHER),
		[UserKeys.NONCE]: text(UserKeys.NONCE)
	},
	(table) => [
		check(
			'user_key_envelope_pair',
			sql`(${table[UserKeys.CIPHER]} IS NULL) = (${table[UserKeys.NONCE]} IS NULL)`
		)
	]
);

// Additive reset state: absence means a legacy, generation-zero vault.
export const vaultState = pgTable('vault_state', {
	userId: integer('user_id')
		.primaryKey()
		.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
	generation: text('generation').notNull(),
	resetAt: bigint('reset_at', { mode: 'number' }).notNull().default(0),
	initiatingSessionHash: text('initiating_session_hash'),
	ready: integer('ready').notNull().default(1)
}).enableRLS();

// Issuance and reset share the account lock. Absence is not evidence that old
// capabilities have expired: an explicit cutover bounds unaccounted issuances.
export const vaultUploadCapability = pgTable(
	'vault_upload_capability',
	{
		userId: integer('user_id')
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		generation: text('generation').notNull(),
		expiresAt: bigint('expires_at', { mode: 'number' }).notNull()
	},
	(table) => [primaryKey({ columns: [table.userId, table.generation] })]
).enableRLS();

// Operational upload records deliberately have no FK to files, parts, devices
// or storage: reset/removal must not erase an outstanding cleanup obligation.
export const vaultUpload = pgTable(
	'vault_upload',
	{
		id: text('id').primaryKey(),
		userId: integer('user_id')
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		deviceUuid: text('device_uuid').notNull(),
		generation: text('generation').notNull(),
		storageId: integer('storage_id').notNull(),
		providerId: integer('provider_id').notNull(),
		objectKey: text('object_key').notNull(),
		partName: text('part_name').notNull(),
		credentials: jsonb('credentials').$type<Record<string, unknown>>().notNull(),
		receiptHash: text('receipt_hash').notNull(),
		contentLength: bigint('content_length', { mode: 'number' }).notNull(),
		sha1: text('sha1').notNull(),
		md5: text('md5').notNull(),
		uploadId: text('upload_id'),
		versionId: text('version_id'),
		phase: text('phase').notNull().default('creating'),
		uncertain: text('uncertain'),
		cleanupCursor: jsonb('cleanup_cursor').$type<Record<string, unknown>>().notNull().default({}),
		operationId: text('operation_id'),
		retired: integer('retired').notNull().default(0),
		createdAt: bigint('created_at', { mode: 'number' }).notNull(),
		updatedAt: bigint('updated_at', { mode: 'number' }).notNull(),
		leaseOwner: text('lease_owner'),
		leaseUntil: bigint('lease_until', { mode: 'number' }).notNull().default(0),
		nextAttemptAt: bigint('next_attempt_at', { mode: 'number' }).notNull().default(0),
		attempts: integer('attempts').notNull().default(0),
		error: text('error')
	},
	(table) => [
		index('vault_upload_owner').on(table.userId, table.generation),
		index('vault_upload_object').on(table.userId, table.storageId, table.objectKey),
		index('vault_upload_due').on(table.phase, table.nextAttemptAt)
	]
).enableRLS();

export const recoveryReset = pgTable(
	'recovery_reset',
	{
		id: text('id').primaryKey(),
		userId: integer('user_id')
			.notNull()
			.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
		expectedGeneration: text('expected_generation').notNull(),
		nextGeneration: text('next_generation').notNull(),
		sessionHash: text('session_hash').notNull(),
		challengeHash: text('challenge_hash').notNull(),
		createdAt: bigint('created_at', { mode: 'number' }).notNull(),
		expiresAt: bigint('expires_at', { mode: 'number' }).notNull(),
		committedAt: bigint('committed_at', { mode: 'number' }),
		notBefore: bigint('not_before', { mode: 'number' }),
		envelopeHash: text('envelope_hash'),
		phase: text('phase').notNull().default('prepared'),
		error: text('error')
	},
	(table) => [
		index('recovery_reset_user').on(table.userId),
		index('recovery_reset_phase').on(table.phase)
	]
).enableRLS();

export const recoveryCleanupTarget = pgTable(
	'recovery_cleanup_target',
	{
		id: text('id').primaryKey(),
		operationId: text('operation_id')
			.notNull()
			.references(() => recoveryReset.id, { onDelete: 'cascade' }),
		providerId: integer('provider_id').notNull(),
		prefix: text('prefix').notNull(),
		credentials: jsonb('credentials').$type<Record<string, unknown>>().notNull(),
		cursor: jsonb('cursor').$type<Record<string, unknown>>().notNull().default({}),
		phase: text('phase').notNull().default('pending'),
		leaseOwner: text('lease_owner'),
		leaseUntil: bigint('lease_until', { mode: 'number' }).notNull().default(0),
		nextAttemptAt: bigint('next_attempt_at', { mode: 'number' }).notNull().default(0),
		attempts: integer('attempts').notNull().default(0),
		error: text('error')
	},
	(table) => [index('recovery_cleanup_due').on(table.phase, table.nextAttemptAt)]
).enableRLS();

export const recoveryWorkerState = pgTable('recovery_worker_state', {
	id: text('id').primaryKey(),
	lastRunAt: bigint('last_run_at', { mode: 'number' }).notNull()
}).enableRLS();

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
		.notNull()
		.$defaultFn(() => Date.now())
		.$onUpdate(() => Date.now()),
	[UserDataKeys.USER_ID]: integer(UserDataKeys.USER_ID)
		.notNull()
		.unique() // <- Creates index internally
		.references(() => user[UserKeys.ID], { onDelete: 'cascade' }),
	[UserDataKeys.USER_NAME]: text(UserDataKeys.USER_NAME).unique(),
	[UserDataKeys.DEVICE_UUID]: text(UserDataKeys.DEVICE_UUID).notNull(), // To track made changes by
	[UserDataKeys.PROFILE_IMAGE]: text(UserDataKeys.PROFILE_IMAGE),
	[UserDataKeys.PRO_ID]: text(UserDataKeys.PRO_ID).unique(), // revenue cat id
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
		index('part_idx_user_id').on(table[PartKeys.USER_ID]),
		index('part_managed_object')
			.on(sql`(${table[PartKeys.JSON]} ->> 'managedObjectKey')`)
			.where(sql`${table[PartKeys.UPLOADED]} = 1 AND ${table[PartKeys.DELETED]} = 0`)
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
