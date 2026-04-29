export const UserKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	REMOTE_AUTH_ID: '4',
	EMAIL: '5',
	CIPHER: '6',
	NONCE: '7'
} as const;

export const UserDataKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	USER_NAME: '5',
	DEVICE_UUID: '6',
	PRO_ID: '7',
	PROFILE_IMAGE: '8',
	PLAN_EXPIRES_AT: '9'
} as const;

export const UserDeviceKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_UUID: '5',
	TITLE: '6',
	DEVICE_TYPE: '7',
	NOTIFICATION_ID: '8',
	ACTIVE: '9'
} as const;

export const FileKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_UUID: '5',
	FILE_HASH: '6',
	ITEMS_COUNT: '7',
	PARTS: '8',
	UPLOADED_AT: '9',
	PROVIDER_ID: '10',
	STORAGE_ID: '11',
	JSON: '12',
	CLIENT_UPDATED_AT: '13',
	DELETED: '14'
} as const;

export const PartKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_UUID: '5',
	FILE_ID: '6',
	PART_NUMBER: '7',
	PART_SIZE: '8',
	CIPHER: '9',
	NONCE: '10',
	JSON: '11',
	CLIENT_UPDATED_AT: '12',
	DELETED: '13',
	UPLOADED: '14'
} as const;

export const ItemKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	DEVICE_UUID: '5',
	ITEM_ID: '6',
	TEXT_CIPHER: '7',
	TEXT_NONCE: '8',
	KEY_CIPHER: '9',
	KEY_NONCE: '10',
	CLIENT_UPDATED_AT: '11'
} as const;

export const CredentialKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4', // Either a user ID, or 'fife'
	PROVIDER_ID: '5',
	CREDENTIALS: '6',
	UPDATING: '7'
} as const;

export const StorageKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	CREDENTIAL_ID: '5',
	LIMIT_BYTES: '6',
	USED_BYTES: '7',
	PRIORITY: '8',
	JSON: '9',
	LIMIT_FREE_BYTES: '10'
} as const;

export const TempStorageKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	USER_ID: '4',
	FILE_ID: '5',
	STORAGE_ID: '6',
	SIZE: '7',
	PROVIDER_ID: '8'
} as const;

export const ProviderKeys = {
	ID: '1',
	SERVER_CREATED_AT: '2',
	SERVER_UPDATED_AT: '3',
	TITLE: '4',
	FREE_BYTES: '5',
	PRIORITY: '6'
} as const;

export const ErrorCode = {
	NO_USER: 1,
	INVALID_JSON: 2,
	MISSING_FIELDS: 3,
	NO_STORAGE: 4,
	INVALID_CREDENTIALS: 5,
	CREDENTIALS_INCAPABLE: 6,
	DEVICE_LIMIT_REACHED: 7,
	NO_DEVICE: 8,
	NO_BUCKETS: 9,
	MULTIPLE_BUCKETS: 10,
	NAMEPREFIX_EXIST: 11,
	BUCKET_INFO: 12,
	NO_DATA: 13,
	UNAUTHORIZED: 14,
	INVALID_DATA: 15,
	NO_PRO: 16
} as const;

export const StorageProvider = {
	FIFE: 1,
	BACKBLAZE: 2,
	CLOUDFLARE: 3,
	OCI: 4,
	IDRIVE: 5
};
