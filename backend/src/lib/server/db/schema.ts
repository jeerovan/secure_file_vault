import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';

export const user = sqliteTable('user', {
	1: text('1').primaryKey(), // Supabase user id
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull().unique(), // Email
	5: text('5').notNull(), // Cipher
	6: text('6').notNull() // Nonce
});

export const userData = sqliteTable('user_data', {
	1: text('1').primaryKey(), // Supabase user id
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').unique(), // User Name
	5: text('5').notNull(), // Device Id
	6: integer('6').notNull().default(0), // Plan Type
	7: text('7') // Profile Image
});

export const userDevice = sqliteTable('user_device', {
	1: text('1').primaryKey(), // UserId_DeviceId
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull(), // User Id
	5: text('5').notNull(), // Title
	6: integer('6').notNull().default(0), // Device Type -> 1:Android/2:iOS/3:MacOS/4:Windows/5:Linux
	7: text('7'), // Notification Id (FCM ID)
	8: integer('8').default(1) // Status -> 1:Active/0:Inactive
});

export const file = sqliteTable('file', {
	1: text('1').primaryKey(), // UserId_FileHash
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull(), // User Id
	5: text('5').notNull(), // Device Id
	6: integer('6').notNull().default(0), // Items Count
	7: integer('7').notNull().default(0), // Parts
	8: integer('8').notNull().default(0), // Parts Uploaded
	9: integer('9').notNull().default(0), // Uploaded At
	10: integer('10').default(0), // Service type: Backblaze, Cloudflare etc.
	11: text('11'), // Remote File Id
	12: text('12'), // File Access Token
	13: integer('13').notNull().default(0), // Token Expiry
	14: integer('14').notNull().default(0), // ClientUpdatedAt
	15: integer('15').notNull().default(0) // Deleted
});

export const part = sqliteTable('part', {
	1: text('1').primaryKey(), // UserId_FileHash_PartNumber
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull(), // UserId
	5: text('5').notNull(), // Device Id
	6: integer('6').notNull(), // Part Size
	7: integer('7').notNull().default(0), // State
	8: text('8'), // Cipher
	9: text('9'), // Nonce
	10: text('10'), // Sha1
	11: integer('11').notNull().default(0), // ClientUpdatedAt
	12: integer('12').notNull().default(0) // Deleted
});

export const item = sqliteTable('item', {
	1: text('1').primaryKey(), // UserId_UUID
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull(), // UserId
	5: text('5').notNull(), // Device Id
	6: text('6').notNull(), // Text Cipher
	7: text('7').notNull(), // Text Nonce
	8: text('8').notNull(), // Key Cipher
	9: text('9').notNull(), // Key Nonce
	10: integer('10').notNull().default(0) // ClientUpdatedAt
});

export const backblaze = sqliteTable('backblaze', {
	1: text('1').primaryKey(), // Account Id
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull(), // AppId
	5: text('5').notNull(), // AppKey
	6: text('6').notNull(), // B2 Access Token
	7: integer('7').notNull().default(0), // Updating (0/1)
	8: text('8').notNull(), // Api Url
	9: text('9').notNull(), // Storage Url
	10: text('10').notNull(), // Bucket Id
	11: text('11').notNull().unique(), // User Id
	12: integer('12', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // Token Updated At
	13: integer('13').notNull().default(10) // Bucket size limit, default: 10GB
});
