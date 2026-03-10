import { json } from '@sveltejs/kit';
import {
	addB2Account,
	getB2Account,
	markB2TokenUpdated,
	markB2TokenUpdating,
	updateB2Account
} from './db/api';

export async function authorize(appId: string, appKey: string) {
	let response;
	const B2_API_URL = 'https://api.backblazeb2.com/b2api/v3';
	try {
		const authResponse = await fetch(`${B2_API_URL}/b2_authorize_account`, {
			headers: { Authorization: `Basic ${btoa(`${appId}:${appKey}`)}` }
		});

		if (!authResponse.ok) {
			console.error('B2 Authentication failed:', authResponse.status, authResponse.statusText);
		}

		response = await authResponse.json();
	} catch (error) {
		console.error('Error fetching B2 token:', error);
	}
	return response;
}

export async function addAccount(UserId: string, AppId: string, KeyId: string, data: any) {
	// Create bucket with config and get bucket it
	const {
		accountId,
		authorizationToken,
		apiInfo: {
			storageApi: { apiUrl }
		}
	} = data;
	const endpoint = `${apiUrl}/b2api/v3/b2_create_bucket`;
	const bucketName = 'FiFe';
	const payload = {
		accountId,
		bucketName,
		bucketType: 'allPrivate',
		lifecycleRules: [
			{
				daysFromHidingToDeleting: 1,
				daysFromUploadingToHiding: null,
				fileNamePrefix: ''
			}
		]
	};

	try {
		const response = await fetch(endpoint, {
			method: 'POST',
			headers: {
				Authorization: authorizationToken,
				'Content-Type': 'application/json'
			},
			body: JSON.stringify(payload)
		});

		if (!response.ok) {
			// Backblaze returns detailed error objects
			const errorData = await response.json();
			return json({
				status: 0,
				error: `Error: ${errorData.message}`
			});
		}
		const { bucketId } = await response.json();
		await addB2Account(UserId, AppId, KeyId, bucketId, data);
		return json({ status: 1 });
	} catch (error) {
		console.error('Failed to create Backblaze bucket:', error);
		return json({ status: 0, error: error });
	}
}

export async function authenticate(UserId: string) {
	// 1. Find the row for this Id
	const row = await getB2Account(UserId);

	// Return undefined if the account does not exist
	if (!row) {
		return undefined;
	}

	const accountId = row['1'];
	const existingToken = row['6'] || undefined;
	const isUpdating = row['7'];
	const updatedAt = row['12'] || new Date(0); // Fallback to 1970 if null
	const appId = row['4'];
	const appKey = row['5'];
	const existingApiUrl = row['8'];
	const existingDownloadUrl = row['9'];
	const bucketId = row['10'];

	// Bundle the existing credentials to easily return them
	const existingData = {
		authorizationToken: existingToken,
		bucketId,
		apiUrl: existingApiUrl,
		downloadUrl: existingDownloadUrl
	};

	// 2. If another process is currently updating, return the old data immediately
	if (isUpdating === 1) {
		return existingData;
	}

	// 3. Check if we actually need to update
	// Token lasts 24 hours, but we refresh after 20 hours
	const now = new Date();
	const diffHours = (now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60);

	// If token exists and was updated less than 20 hours ago, return it
	if (existingToken && diffHours < 20) {
		return existingData;
	}

	// 4. Mark as updating (Atomic lock to prevent race conditions)
	const lockResult = await markB2TokenUpdating(accountId);

	// If no rows are returned, another process grabbed the lock right before us
	if (lockResult.length === 0) {
		return existingData;
	}

	// 5. Authenticate with B2
	const data = await authorize(appId, appKey);
	if (data) {
		const {
			authorizationToken,
			apiInfo: {
				storageApi: { apiUrl, downloadUrl }
			}
		} = data;

		await updateB2Account(accountId, data);

		// Return the newly fetched credentials alongside the existing bucketId
		return {
			authorizationToken,
			bucketId,
			apiUrl,
			downloadUrl
		};
	} else {
		await markB2TokenUpdated(UserId);
		return existingData;
	}
}

// --- Shared Types ---
export interface B2BaseParams {
	apiUrl: string;
	authorizationToken: string;
}

// Helper to handle the repetitive fetch boilerplate
async function b2Fetch(endpoint: string, params: B2BaseParams, payload: any) {
	const response = await fetch(`${params.apiUrl}/b2api/v3/${endpoint}`, {
		method: 'POST',
		headers: {
			Authorization: params.authorizationToken,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(payload)
	});

	if (!response.ok) {
		const error = await response.json();
		return json({ status: 0, error: error.message || error.code });
	}

	return json({ status: 1, data: response.json() });
}

// --- 1. b2_get_upload_url ---
export interface GetUploadUrlParams extends B2BaseParams {
	bucketId: string;
}

/**
 * Gets an upload URL and upload authorization token for uploading a standard file.
 */
export async function getUploadUrl(params: GetUploadUrlParams) {
	return b2Fetch('b2_get_upload_url', params, {
		bucketId: params.bucketId
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
