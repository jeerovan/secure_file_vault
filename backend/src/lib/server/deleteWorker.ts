import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { authenticate, deleteFileVersion } from './backblaze';
import {
	getCredentialByStorageId,
	getUser,
	getUserFile,
	getUserFilePart,
	resetUserFileByHash,
	resetUserFilePart,
	updateStorageUsedSize
} from './db/api';
import { CredentialKeys, FileKeys, PartKeys, StorageProvider, UserKeys } from './db/keys';

export async function deleteFileFromStorage(fileRow: any) {
	const parts = fileRow[FileKeys.PARTS];
	const partNumbers = Array.from({ length: parts }, (_, i) => i + 1);
	const userId = fileRow[FileKeys.USER_ID];
	const fileId = fileRow[FileKeys.ID];
	const providerId = fileRow[FileKeys.PROVIDER_ID];
	const storageId = fileRow[FileKeys.STORAGE_ID];
	const fileHash = fileRow[FileKeys.FILE_HASH];
	const userRow = await getUser(userId);
	if (storageId == null || userRow == undefined) return;
	const credential = await getCredentialByStorageId(userId, storageId);
	const supabaseId = userRow[UserKeys.SUPABASE_ID];
	let allRemoved = true;
	for (const index in partNumbers) {
		const partNumber = partNumbers[index];
		const partKey = `${supabaseId}_${fileHash}_${partNumber}`;
		const file_name = `${supabaseId}/${fileHash}_${partNumber}`;
		const filePart = await getUserFilePart(userId, fileRow[FileKeys.ID], partNumber);
		if (filePart && filePart[PartKeys.PART_SIZE] > 0) {
			if (providerId == StorageProvider.FIFE || providerId == StorageProvider.BACKBLAZE) {
				const partData = filePart[PartKeys.JSON];
				const parsedData = typeof partData === 'string' ? JSON.parse(partData) : partData;
				const b2_id = parsedData.fileId;
				const authData = await authenticate(userId, storageId);
				if (!authData) {
					return;
				}
				const response = await deleteFileVersion({
					apiUrl: authData.apiUrl,
					authorizationToken: authData.authorizationToken,
					fileName: file_name,
					fileId: b2_id
				});
				const result = await response.json();
				if (result['success'] == 1) {
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(userId, fileId, partNumber);
				} else if (result['message'] == 'file_not_found') {
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(userId, fileId, partNumber);
				} else {
					allRemoved = false;
				}
			} else if (providerId == StorageProvider.CLOUDFLARE && credential) {
				const credsData = credential[CredentialKeys.CREDENTIALS] as {
					appId: string;
					appKey: string;
					bucketName: string;
				};
				const accountId = credential[CredentialKeys.ID];
				const s3Endpoint = `https://${accountId}.r2.cloudflarestorage.com`;
				const region = 'auto';
				const s3Client = new S3Client({
					endpoint: s3Endpoint,
					region: region,
					credentials: {
						accessKeyId: credsData.appId,
						secretAccessKey: credsData.appKey
					}
				});
				const command = new DeleteObjectCommand({
					Bucket: credsData.bucketName,
					Key: file_name
				});
				try {
					await s3Client.send(command);
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(userId, fileId, partNumber);
				} catch (e) {
					allRemoved = false;
					console.error(e);
				}
			} else if (providerId == StorageProvider.OCI && credential) {
				const credsData = credential[CredentialKeys.CREDENTIALS] as {
					appId: string;
					appKey: string;
					bucketName: string;
					namespace: string;
					region: string;
				};
				const s3Endpoint = `https://${credsData.namespace}.compat.objectstorage.${credsData.region}.oraclecloud.com`;
				const s3Client = new S3Client({
					region: credsData.region,
					endpoint: s3Endpoint,
					credentials: {
						accessKeyId: credsData.appId,
						secretAccessKey: credsData.appKey
					},
					forcePathStyle: true
				});
				const command = new DeleteObjectCommand({
					Bucket: credsData.bucketName,
					Key: file_name
				});
				try {
					await s3Client.send(command);
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(userId, fileId, partNumber);
				} catch (e) {
					allRemoved = false;
					console.error(e);
				}
			} else if (providerId == StorageProvider.IDRIVE && credential) {
				const credsData = credential[CredentialKeys.CREDENTIALS] as {
					appId: string;
					appKey: string;
					bucketName: string;
					region: string;
				};
				const s3Endpoint = `https://s3.${credsData.region}.idrivee2.com`;
				const s3Client = new S3Client({
					region: credsData.region,
					endpoint: s3Endpoint,
					credentials: {
						accessKeyId: credsData.appId,
						secretAccessKey: credsData.appKey
					},
					forcePathStyle: true
				});
				const command = new DeleteObjectCommand({
					Bucket: credsData.bucketName,
					Key: file_name
				});
				try {
					await s3Client.send(command);
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(userId, fileId, partNumber);
				} catch (e) {
					allRemoved = false;
					console.error(e);
				}
			}
		}
	}
	if (allRemoved) {
		await resetUserFileByHash(userId, fileHash);
	}
}
