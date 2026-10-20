import { json } from '@sveltejs/kit';
import {
	addCredentials,
	getCredentialByStorageId,
	markCredentialsUpdated,
	markCredentialsUpdating,
	updateCredentials
} from './db/api';
import { CredentialKeys, StorageProvider } from './db/keys';
import type { Db, Tx } from './db';
import { backblazeCredentialsFromAuthorization } from './backblazeCredentials';

export async function authorize(appId: string, appKey: string) {
	let data;
	let message;
	const B2_API_URL = 'https://api.backblazeb2.com/b2api/v4';
	try {
		const authResponse = await fetch(`${B2_API_URL}/b2_authorize_account`, {
			headers: { Authorization: `Basic ${btoa(`${appId}:${appKey}`)}` },
			redirect: 'manual',
			signal: AbortSignal.timeout(15_000)
		});

		if (!authResponse.ok) {
			const errorData = await authResponse.json();
			message =
				typeof errorData?.code === 'string' && /^[a-z0-9_]+$/.test(errorData.code)
					? errorData.code
					: 'authorization_failed';
		} else {
			data = await authResponse.json();
		}
	} catch {
		message = 'authorization_failed';
	}
	return { message, data };
}

export async function addAccount(
	db: Db | Tx,
	userId: number,
	appId: string,
	appKey: string,
	data: unknown
) {
	const credentials = backblazeCredentialsFromAuthorization(appId, appKey, data);
	const providerId = StorageProvider.BACKBLAZE;
	await addCredentials(db, userId, credentials, providerId);
	return json({ success: 1 });
}

export async function authenticate(db: Db | Tx, userId: number, storageId: number) {
	const credential = await getCredentialByStorageId(db, userId, storageId);

	if (!credential) {
		// TODO user should be flagged here
		return undefined;
	}
	if (
		![StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(
			credential[CredentialKeys.PROVIDER_ID]
		)
	)
		return undefined;

	const creds = credential[CredentialKeys.CREDENTIALS] as {
		accountId: string;
		appId: string;
		appKey: string;
		authorizationToken: string;
		bucketId: string;
		bucketName: string;
		apiUrl: string;
		downloadUrl: string;
		s3ApiUrl: string;
	};

	const {
		accountId,
		appId,
		appKey,
		authorizationToken: existingToken,
		bucketId,
		bucketName,
		apiUrl: existingApiUrl,
		downloadUrl: existingDownloadUrl,
		s3ApiUrl: existingS3ApiUrl
	} = creds;
	const isUpdating = credential[CredentialKeys.UPDATING];
	const updatedAt = credential[CredentialKeys.SERVER_UPDATED_AT] || Date.now();

	// Bundle the existing credentials to easily return them
	const existingData = {
		...creds,
		accountId,
		appId,
		appKey,
		authorizationToken: existingToken,
		bucketId,
		bucketName,
		apiUrl: existingApiUrl,
		downloadUrl: existingDownloadUrl,
		s3ApiUrl: existingS3ApiUrl
	};
	const currentCredentials = async () => {
		const latest = await getCredentialByStorageId(db, userId, storageId);
		return latest?.[CredentialKeys.CREDENTIALS] as typeof existingData | undefined;
	};

	// 2. If another process is currently updating, return the old data immediately
	if (isUpdating === 1) {
		return existingData;
	}

	// 3. Check if we actually need to update
	// Token lasts 24 hours, but we refresh after 20 hours
	const now = Date.now();
	const diffHours = (now - updatedAt) / (1000 * 60 * 60);

	// If token exists and was updated less than 20 hours ago, return it
	if (existingToken && existingS3ApiUrl && diffHours < 20) {
		return existingData;
	}

	// 4. Mark as updating (Atomic lock to prevent race conditions)
	const lockResult = await markCredentialsUpdating(db, credential[CredentialKeys.ID], creds);

	// If no rows are returned, another process grabbed the lock right before us
	if (lockResult.length === 0) {
		return currentCredentials();
	}

	// 5. Authenticate with B2
	const { data } = await authorize(appId, appKey);
	if (data) {
		let credentials;
		try {
			const discovered = backblazeCredentialsFromAuthorization(appId, appKey, data);
			if (discovered.bucketId !== bucketId) throw new Error('Bucket changed');
			credentials = { ...creds, ...discovered };
		} catch {
			await markCredentialsUpdated(db, credential[CredentialKeys.ID], creds);
			return currentCredentials();
		}
		const updated = await updateCredentials(db, credential[CredentialKeys.ID], credentials, creds);
		if (!updated.length) return currentCredentials();

		// Return the newly fetched credentials alongside the existing bucketId
		return credentials;
	} else {
		await markCredentialsUpdated(db, credential[CredentialKeys.ID], creds);
		return currentCredentials();
	}
}

// --- Shared Types ---
export interface B2BaseParams {
	apiUrl: string;
	authorizationToken: string;
}

// Helper to handle the repetitive fetch boilerplate
async function b2Fetch(
	endpoint: string,
	params: B2BaseParams,
	payload: any,
	options: Pick<RequestInit, 'signal' | 'redirect'> = {}
) {
	const response = await fetch(`${params.apiUrl}/b2api/v4/${endpoint}`, {
		...options,
		method: 'POST',
		headers: {
			Authorization: params.authorizationToken,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(payload)
	});
	if (!response.ok) {
		const error = await response.json();
		return json({ success: 0, message: error.code, description: error.message });
	}

	return json({ success: 1, data: await response.json() });
}

// --- 1. b2_get_upload_url ---
export interface GetUploadUrlParams extends B2BaseParams {
	bucketId: string;
}

/**
 * Gets an upload URL and upload authorization token for uploading a standard file.
 */
export async function getUploadUrl(params: GetUploadUrlParams) {
	return b2Fetch(
		'b2_get_upload_url',
		params,
		{ bucketId: params.bucketId },
		{ signal: AbortSignal.timeout(15_000), redirect: 'manual' }
	);
}

export interface ListFileNamesParams extends B2BaseParams {
	bucketId: string;
	fileName: string;
}

export async function listFileNames(params: ListFileNamesParams) {
	return b2Fetch('b2_list_file_names', params, {
		bucketId: params.bucketId,
		startFileName: params.fileName,
		prefix: params.fileName,
		maxFileCount: 100
	});
}

// --- 2. b2_get_download_authorization ---
export interface GetDownloadAuthParams extends B2BaseParams {
	bucketId: string;
	fileNamePrefix: string;
	validDurationInSeconds: number; // e.g., 86400 for 24 hours
}

/**
 * Gets an authorization token that can be used to download private files.
 */
export async function getDownloadAuthorization(params: GetDownloadAuthParams) {
	return b2Fetch('b2_get_download_authorization', params, {
		bucketId: params.bucketId,
		fileNamePrefix: params.fileNamePrefix,
		validDurationInSeconds: params.validDurationInSeconds
	});
}

// --- 3. b2_start_large_file ---
export interface StartLargeFileParams extends B2BaseParams {
	bucketId: string;
	fileName: string;
	contentType: string; // e.g., "video/mp4" or "b2/x-auto"
}

/**
 * Starts a large file upload, returning a fileId to be used for uploading parts.
 */
export async function startLargeFile(params: StartLargeFileParams) {
	return b2Fetch('b2_start_large_file', params, {
		bucketId: params.bucketId,
		fileName: params.fileName,
		contentType: params.contentType
	});
}

// --- 4. b2_get_upload_part_url ---
export interface GetUploadPartUrlParams extends B2BaseParams {
	fileId: string; // The ID returned from b2_start_large_file
}

/**
 * Gets an upload URL and token for uploading a specific part of a large file.
 */
export async function getUploadPartUrl(params: GetUploadPartUrlParams) {
	return b2Fetch('b2_get_upload_part_url', params, {
		fileId: params.fileId
	});
}

// --- 5. b2_finish_large_file ---
export interface CancelLargeFileParams extends B2BaseParams {
	fileId: string;
}

/**
 * Cancels a large file upload .
 */
export async function cancelLargeFile(params: CancelLargeFileParams) {
	return b2Fetch('b2_cancel_large_file', params, {
		fileId: params.fileId
	});
}

// --- 5. b2_finish_large_file ---
export interface FinishLargeFileParams extends B2BaseParams {
	fileId: string;
	partSha1Array: string[]; // Array of SHA1 hashes of the uploaded parts in order
}

/**
 * Finishes a large file upload by providing the ordered SHA1 hashes of all parts.
 */
export async function finishLargeFile(params: FinishLargeFileParams) {
	return b2Fetch('b2_finish_large_file', params, {
		fileId: params.fileId,
		partSha1Array: params.partSha1Array
	});
}

// --- 6. b2_delete_file_version ---
export interface DeleteFileVersionParams extends B2BaseParams {
	fileName: string;
	fileId: string;
}

/**
 * Deletes a specific version of a file. If it's the only version, the file is completely removed.
 */
export async function deleteFileVersion(params: DeleteFileVersionParams) {
	return b2Fetch('b2_delete_file_version', params, {
		fileName: params.fileName,
		fileId: params.fileId
	});
}
