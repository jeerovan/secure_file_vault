import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { authenticate, deleteFileVersion } from './backblaze';
import {
	getCredentialsByStorageId,
	getFile,
	getFilePart,
	resetFile,
	resetFilePart,
	updateStorageUsedSize
} from './db/api';
import { CredentialsKeys, FileKeys, PartKeys, StorageProvider } from './db/keys';

export async function deleteFileFromStorage(userId: string, fileHash: string) {
	const fileRow = await getFile(userId, fileHash);
	if (!fileRow) return;
	const parts = fileRow[FileKeys.PARTS];
	const partIds = Array.from({ length: parts }, (_, i) => `${i + 1}`);
	const provider = fileRow[FileKeys.PROVIDER];
	const storageId = fileRow[FileKeys.STORAGE_ID];
	if (storageId == null) return;
	const credential = await getCredentialsByStorageId(userId, storageId);
	let allRemoved = true;
	for (const index in partIds) {
		const partId = partIds[index];
		const partKey = `${userId}_${fileHash}_${partId}`;
		const filePart = await getFilePart(partKey);
		const file_name = `${userId}/${fileHash}_${partId}`;
		if (filePart) {
			if (provider == StorageProvider.FIFE || provider == StorageProvider.BACKBLAZE) {
				const partData = filePart[PartKeys.JSON] as { fileId: string };
				const file_id = partData['fileId'];
				const authData = await authenticate(userId, storageId);
				if (!authData) {
					return;
				}
				const response = await deleteFileVersion({
					apiUrl: authData.apiUrl,
					authorizationToken: authData.authorizationToken,
					fileName: file_name,
					fileId: file_id
				});
				const result = await response.json();
				if (result['success'] == 1) {
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetFilePart(partKey);
				} else if (result['message'] == 'file_not_found') {
					await updateStorageUsedSize(storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetFilePart(partKey);
				} else {
					allRemoved = false;
				}
			} else if (provider == StorageProvider.CLOUDFLARE && credential) {
				const credsData = credential[CredentialsKeys.CREDENTIALS] as {
					appId: string;
					appKey: string;
					bucketName: string;
				};
				const accountId = credential[CredentialsKeys.ID];
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
					await resetFilePart(partKey);
				} catch (e) {
					allRemoved = false;
					console.error(e);
				}
			}
		}
	}
	if (allRemoved) {
		await resetFile(userId, fileHash);
	}
}
