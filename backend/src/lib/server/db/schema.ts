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
	5: integer('5').notNull().default(0), // Plan Type
	6: integer('6').notNull().default(0) // Profile Image Number
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
	5: integer('5').notNull().default(0), // Items Count
	6: integer('6').notNull().default(0), // Parts
	7: integer('7').notNull().default(0), // Parts Uploaded
	8: integer('8').notNull().default(0), // Uploaded At
	9: integer('9').default(0), // Service type: Backblaze, Cloudflare etc.
	10: text('10'), // Remote File Id
	11: text('11'), // File Access Token
	12: integer('12').notNull().default(0), // Token Expiry
	13: integer('13').notNull().default(0), // ClientCreatedAt
	14: integer('14').notNull().default(0) // ClientUpdatedAt
});

export const part = sqliteTable('part', {
	1: text('1').primaryKey(), // UserId_FileHash_PartNumber
	2: integer('2', { mode: 'timestamp' })
		.notNull()
		.$defaultFn(() => new Date()), // ServerCreatedAt
	3: integer('3', { mode: 'timestamp' })
		.$defaultFn(() => new Date())
		.$onUpdate(() => new Date()), // ServerUpdatedAt
	4: text('4').notNull(), // UserId_FileHash (FileId)
	5: integer('5').notNull(), // Part Size
	6: integer('6').notNull().default(0), // State
	7: text('7'), // Cipher
	8: text('8'), // Nonce
	9: text('9'), // Sha1
	10: integer('10').notNull().default(0), // ClientCreatedAt
	11: integer('11').notNull().default(0) // ClientUpdatedAt
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
	5: text('5').notNull(), // Cipher Text
	6: text('6').notNull(), // Cipher Nonce
	7: text('7').notNull(), // Key Cipher
	8: text('8').notNull(), // Key Nonce
	9: integer('9').notNull().default(0), // ClientCreatedAt
	10: integer('10').notNull().default(0) // ClientUpdatedAt
});
