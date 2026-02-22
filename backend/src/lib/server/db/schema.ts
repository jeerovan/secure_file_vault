import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';

export const user = sqliteTable('user', {
	id: text('id').primaryKey(), // Supabase user id
	email: text('email').notNull().unique(),
	cipher: text('cipher').notNull(),
	nonce: text('nonce').notNull(),
	updatedAt: integer('updated_at', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	createdAt: integer('created_at', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date())
});

export const userData = sqliteTable('user_data', {
	userId: text('user_id').primaryKey(),
	userName: text('user_name').unique(),
	planType: integer('plan_type').notNull().default(0),
	updatedAt: integer('updated_at', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	createdAt: integer('created_at', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date())
});

export const userDevice = sqliteTable('user_device', {
	id: text('id').primaryKey(), // UserId_DeviceId
	userId: text('user_id').notNull(),
	title: text('title').notNull(),
	type: integer('type').notNull().default(0), // 1:Android/2:iOS/3:MacOS/4:Windows/5:Linux
	notificationId: text('notification_id'),
	status: integer('status').default(1), // 1:Active/0:Inactive
	lastActiveAt: integer('last_active_at').default(0),
	updatedAt: integer('updated_at', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	createdAt: integer('created_at', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date())
});

export const file = sqliteTable('file', {
	id: text('id').primaryKey(), // UserId_FileHash
	userId: text('user_id').notNull(),
	itemCount: integer('item_count').notNull().default(0),
	parts: integer('parts').notNull().default(0),
	partsUploaded: integer('parts_uploaded').notNull().default(0),
	uploadedAt: integer('uploaded_at').notNull().default(0),
	remoteType: integer('remote_type'), // Service type
	remoteId: text('remote_id'),
	accessToken: text('access_token'),
	tokenExpiry: integer('token_expiry').notNull().default(0),
	updatedAt: integer('updated_at', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	createdAt: integer('created_at', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date())
});

export const part = sqliteTable('part', {
	id: text('id').primaryKey(),
	fileId: text('file_id').notNull(),
	partNumber: integer('part_number').notNull(),
	size: integer('size').notNull(),
	state: integer('state').notNull().default(0),
	cipher: text('cipher'),
	nonce: text('nonce'),
	updatedAt: integer('updated_at', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	createdAt: integer('created_at', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date())
});

export const item = sqliteTable('item', {
	id: text('id').primaryKey(), // UserId_UUID
	userId: text('user_id').notNull(),
	cipherText: text('cipher_text').notNull(),
	cipherNonce: text('cipher_nonce').notNull(),
	keyCipher: text('key_cipher').notNull(),
	keyNonce: text('key_nonce').notNull(),
	updatedAt: integer('updated_at', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()),
	createdAt: integer('created_at', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()),
	serverAt: integer('server_at').default(0)
});
