import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { authenticate } from './backblaze';
import { deleteBackblazeS3Version } from './backblazeS3';
import {
	getCredentialByStorageId,
	getUser,
	getUserFilePart,
	resetUserFileByHash,
	resetUserFilePart,
	updateStorageUsedSize
} from './db/api';
import { CredentialKeys, FileKeys, PartKeys, StorageProvider, UserKeys } from './db/keys';
import type { Db, Tx } from './db';
import { createGenericS3Client, type GenericS3Credentials } from './s3';
import { vaultState, vaultUpload } from './db/schema';
import { and, eq, ne, sql } from 'drizzle-orm';
import { vaultObjectPrefix } from './recoveryStorage';
import { storedPartObjectKey } from './partObject';

export async function deleteFileFromStorage(db: Db | Tx, fileRow: Record<string, unknown>) {
	const parts = fileRow[FileKeys.PARTS] as number;
	const partNumbers = Array.from({ length: parts }, (_, i) => i + 1);
	const userId = fileRow[FileKeys.USER_ID] as number;
	const fileId = fileRow[FileKeys.ID] as number;
	const providerId = fileRow[FileKeys.PROVIDER_ID] as number;
	const storageId = fileRow[FileKeys.STORAGE_ID] as number | null;
	const fileHash = fileRow[FileKeys.FILE_HASH] as string;
	const userRow = await getUser(db, userId);
	if (userRow == undefined) return;
	const supabaseId = userRow[UserKeys.REMOTE_AUTH_ID];
	const [state] = await db.select().from(vaultState).where(eq(vaultState.userId, userId)).limit(1);
	const generation = state?.generation ?? 'legacy';
	const prefix = vaultObjectPrefix(supabaseId, generation);
	// Also retire uploads that began before allocation/part-count metadata was
	// synchronized. Their durable manifests outlive the ordinary file rows.
	await db
		.update(vaultUpload)
		.set({ retired: 1, nextAttemptAt: Date.now() })
		.where(
			and(
				eq(vaultUpload.userId, userId),
				eq(vaultUpload.generation, generation),
				ne(vaultUpload.phase, 'deleted'),
				sql`left(${vaultUpload.partName}, ${fileHash.length + 1}) = ${fileHash + '_'}`
			)
		);
	if (storageId == null) return;
	const credential = await getCredentialByStorageId(db, userId, storageId);
	let allRemoved = true;
	for (const partNumber of partNumbers) {
		const filePart = await getUserFilePart(db, userId, fileId, partNumber);
		if (filePart && filePart[PartKeys.PART_SIZE] > 0) {
			const file_name = storedPartObjectKey(
				prefix,
				`${fileHash}_${partNumber}`,
				filePart[PartKeys.JSON]
			);
			if (providerId == StorageProvider.FIFE || providerId == StorageProvider.BACKBLAZE) {
				const partData = filePart[PartKeys.JSON];
				const parsedData = typeof partData === 'string' ? JSON.parse(partData) : partData;
				const b2_id = parsedData.fileId;
				const authData = await authenticate(db, userId, storageId);
				if (!authData) {
					return;
				}
				if (await deleteBackblazeS3Version(authData, file_name, b2_id)) {
					await updateStorageUsedSize(db, storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(db, userId, fileId, partNumber);
				} else {
					allRemoved = false;
				}
			} else if (providerId == StorageProvider.CLOUDFLARE && credential) {
				const credsData = credential[CredentialKeys.CREDENTIALS] as {
					appId: string;
					appKey: string;
					bucketName: string;
					accountId: string;
				};
				const accountId = credsData.accountId;
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
					await updateStorageUsedSize(db, storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(db, userId, fileId, partNumber);
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
					await updateStorageUsedSize(db, storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(db, userId, fileId, partNumber);
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
					await updateStorageUsedSize(db, storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(db, userId, fileId, partNumber);
				} catch (e) {
					allRemoved = false;
					console.error(e);
				}
			} else if (providerId == StorageProvider.S3 && credential) {
				const credentials = credential[CredentialKeys.CREDENTIALS] as GenericS3Credentials;
				const command = new DeleteObjectCommand({
					Bucket: credentials.bucketName,
					Key: file_name
				});
				try {
					await createGenericS3Client(credentials).send(command);
					await updateStorageUsedSize(db, storageId, userId, filePart[PartKeys.PART_SIZE], false);
					await resetUserFilePart(db, userId, fileId, partNumber);
				} catch (e) {
					allRemoved = false;
					console.error(e);
				}
			}
		}
	}
	if (allRemoved) {
		await resetUserFileByHash(db, userId, fileHash);
	}
}
