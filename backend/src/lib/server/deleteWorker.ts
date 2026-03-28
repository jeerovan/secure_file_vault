import { authenticate, deleteFileVersion } from './backblaze';
import { getCredentialsByStorageId, getFile, getFilePart, removeFilePart } from './db/api';
import { FileKeys, PartKeys, StorageProvider } from './db/keys';

export async function triggerDeletionWorker(userId: string, fileHash: string) {
	const fileRow = await getFile(userId, fileHash);
	if (!fileRow) return;
	const parts = fileRow[FileKeys.PARTS];

	const partIds = Array.from({ length: parts }, (_, i) => `${i}`);
	const provider = fileRow[FileKeys.PROVIDER];
	const credential = await getCredentialsByStorageId(userId, fileRow[FileKeys.STORAGE_ID]!);
	for (const partId in partIds) {
		const partKey = `${userId}_${fileHash}_${partId}`;
		const filePart = await getFilePart(partKey);
		if (filePart) {
			const file_name = `${userId}/${fileHash}_${partId}`;
			const partData = filePart[PartKeys.JSON] as { fileId: string };
			const file_id = partData['fileId'];
			if (provider == StorageProvider.FIFE || provider == StorageProvider.BACKBLAZE) {
				const authData = await authenticate(userId, fileRow[FileKeys.STORAGE_ID]!);
				if (!authData) {
					return;
				}
				await deleteFileVersion({
					apiUrl: authData.apiUrl,
					authorizationToken: authData.authorizationToken,
					fileName: file_name,
					fileId: file_id
				});
			}
			removeFilePart(partKey);
		}
	}
}
