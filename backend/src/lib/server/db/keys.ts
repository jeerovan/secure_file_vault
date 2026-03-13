export const UserKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	EMAIL: '4',
	CIPHER: '5',
	NONCE: '6'
} as const;

export const UserDataKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_NAME: '4',
	DEVICE_ID: '5',
	PLAN_TYPE: '6',
	PROFILE_IMAGE: '7',
	PLAN_EXPIRES_AT: '8'
} as const;

export const UserDeviceKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	TITLE: '5',
	DEVICE_TYPE: '6',
	NOTIFICATION_ID: '7',
	STATUS: '8'
} as const;

export const FileKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_ID: '5',
	ITEMS_COUNT: '6',
	PARTS: '7',
	PARTS_UPLOADED: '8',
	UPLOADED_AT: '9',
	PROVIDER: '10',
	REMOTE_FILE_ID: '11',
	FILE_ACCESS_TOKEN: '12',
	TOKEN_EXPIRY: '13',
	CLIENT_UPDATED_AT: '14',
	DELETED: '15'
} as const;

export const PartKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_ID: '5',
	PART_SIZE: '6',
	STATE: '7',
	CIPHER: '8',
	NONCE: '9',
	SHA1: '10',
	CLIENT_UPDATED_AT: '11',
	DELETED: '12'
} as const;

export const ItemKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_ID: '5',
	TEXT_CIPHER: '6',
	TEXT_NONCE: '7',
	KEY_CIPHER: '8',
	KEY_NONCE: '9',
	CLIENT_UPDATED_AT: '10'
} as const;

export const CredentialsKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	OWNER_ID: '4', // Either a user ID, or 'fife'
	PROVIDER: '5',
	CREDENTIALS: '6',
	UPDATING: '7'
} as const;

export const StorageKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	CREDENTIALS_ID: '5',
	LIMIT_BYTES: '6',
	USED_BYTES: '7',
	PRIORITY: '8'
} as const;

export const ErrorCode = {
	NO_USER: 1,
	INVALID_JSON: 2,
	MISSING_FIELDS: 3,
	NO_STORAGE: 4,
	INVALID_CREDENTIALS: 5,
	CREDENTIALS_INCAPABLE: 6,
	DEVICE_LIMIT_REACHED: 7
} as const;

export const StorageProvider = {
	FIFE: 1,
	BACKBLAZE: 2,
	CLOUDFLARE: 3
};
