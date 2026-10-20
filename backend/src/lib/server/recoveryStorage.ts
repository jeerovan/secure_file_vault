import {
	S3Client,
	ListObjectVersionsCommand,
	ListObjectsV2Command,
	ListMultipartUploadsCommand,
	DeleteObjectsCommand,
	AbortMultipartUploadCommand
} from '@aws-sdk/client-s3';
import type { ListObjectVersionsCommandOutput } from '@aws-sdk/client-s3';
import { StorageProvider } from './db/keys';
import { createGenericS3Client, type GenericS3Credentials } from './s3';
import { RecoveryFault } from './recoverySession';
import { createBackblazeS3Client } from './backblazeS3';

export interface RecoveryTarget {
	providerId: number;
	prefix: string;
	credentials: Record<string, unknown>;
}
export interface RecoveryStorage {
	probe(target: RecoveryTarget): Promise<void>;
	step(
		target: RecoveryTarget,
		cursor: Record<string, unknown>
	): Promise<{
		cursor: Record<string, unknown>;
		done: boolean;
	}>;
}

export function vaultObjectPrefix(remoteId: string, generation = 'legacy'): string {
	if (!remoteId || /[/\\\s]/.test(remoteId) || remoteId === '.' || remoteId === '..') {
		throw new RecoveryFault('invalid_identity');
	}
	return generation === 'legacy' ? `${remoteId}/` : `${remoteId}/vaults/${generation}/`;
}

export function isRetiredVaultObject(prefix: string, key: unknown): key is string {
	return (
		typeof key === 'string' && key.startsWith(prefix) && isVaultPartName(key.slice(prefix.length))
	);
}

export function isVaultPartName(value: unknown): value is string {
	return typeof value === 'string' && /^[A-Za-z0-9_-]{43}_[1-9][0-9]*$/.test(value);
}

function required(target: RecoveryTarget, key: string): string {
	const value = target.credentials[key];
	if (typeof value !== 'string' || !value) throw new RecoveryFault('storage_access_required');
	return value;
}

export function createRecoveryS3Client(target: RecoveryTarget): S3Client {
	if ([StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(target.providerId))
		return createBackblazeS3Client(target.credentials);
	if (target.providerId === StorageProvider.S3)
		return createGenericS3Client(target.credentials as GenericS3Credentials);
	let region: string;
	let endpoint: string;
	if (target.providerId === StorageProvider.CLOUDFLARE) {
		region = 'auto';
		endpoint = `https://${required(target, 'accountId')}.r2.cloudflarestorage.com`;
	} else if (target.providerId === StorageProvider.OCI) {
		region = required(target, 'region');
		endpoint = `https://${required(target, 'namespace')}.compat.objectstorage.${region}.oraclecloud.com`;
	} else if (target.providerId === StorageProvider.IDRIVE) {
		region = required(target, 'region');
		endpoint = `https://s3.${region}.idrivee2.com`;
	} else throw new RecoveryFault('storage_unsupported');
	return new S3Client({
		endpoint,
		region,
		forcePathStyle: target.providerId !== StorageProvider.CLOUDFLARE,
		credentials: {
			accessKeyId: required(target, 'appId'),
			secretAccessKey: required(target, 'appKey')
		},
		maxAttempts: 2
	});
}

type S3Port = Pick<S3Client, 'send' | 'destroy'>;
const batchSize = 10;
// Already committed reset manifests predate S3 endpoint metadata. Keep their
// original native cleanup path and readiness deadline.
function usesNativeBackblaze(target: RecoveryTarget): boolean {
	return (
		[StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(target.providerId) &&
		!Object.hasOwn(target.credentials, 's3ApiUrl')
	);
}
const cursorString = (cursor: Record<string, unknown>, key: string) =>
	typeof cursor[key] === 'string' ? (cursor[key] as string) : undefined;

function record(value: unknown): Record<string, unknown> {
	if (!value || typeof value !== 'object' || Array.isArray(value))
		throw new RecoveryFault('storage_unavailable');
	return value as Record<string, unknown>;
}

function listingEntries<T extends { Key?: string }>(value: T[] | undefined): T[] {
	if (value === undefined) return [];
	if (
		!Array.isArray(value) ||
		value.some((entry) => !entry || typeof entry.Key !== 'string' || !entry.Key)
	) {
		throw new RecoveryFault('storage_unavailable');
	}
	return value;
}

/** Provider errors are deliberately reduced to nonsecret retry codes. */
export class ProviderRecoveryStorage implements RecoveryStorage {
	constructor(
		private readonly s3Factory: (target: RecoveryTarget) => S3Port = createRecoveryS3Client,
		private readonly fetcher: typeof fetch = (input, init) => fetch(input, init)
	) {}

	async probe(target: RecoveryTarget) {
		try {
			if (usesNativeBackblaze(target)) {
				const b2 = await this.b2(target);
				const versions = await b2('b2_list_file_versions', {
					bucketId: required(target, 'bucketId'),
					prefix: target.prefix,
					maxFileCount: 1
				});
				const uploads = await b2('b2_list_unfinished_large_files', {
					bucketId: required(target, 'bucketId'),
					namePrefix: target.prefix,
					maxFileCount: 1
				});
				if (!Array.isArray(versions.files) || !Array.isArray(uploads.files))
					throw new RecoveryFault('storage_unavailable');
			} else {
				const client = this.s3Factory(target);
				try {
					const input = {
						Bucket: required(target, 'bucketName'),
						Prefix: target.prefix,
						MaxKeys: 1
					};
					const listed = await client.send(
						target.providerId === StorageProvider.CLOUDFLARE
							? new ListObjectsV2Command(input)
							: new ListObjectVersionsCommand(input),
						{ abortSignal: AbortSignal.timeout(10_000) }
					);
					const uploads = await client.send(
						new ListMultipartUploadsCommand({
							Bucket: input.Bucket,
							Prefix: input.Prefix,
							MaxUploads: 1
						}),
						{ abortSignal: AbortSignal.timeout(10_000) }
					);
					if (typeof listed.IsTruncated !== 'boolean' || typeof uploads.IsTruncated !== 'boolean')
						throw new RecoveryFault('storage_unavailable');
					listingEntries(uploads.Uploads);
					if (target.providerId === StorageProvider.CLOUDFLARE) listingEntries(listed.Contents);
					else {
						const versions = listed as ListObjectVersionsCommandOutput;
						listingEntries(versions.Versions);
						listingEntries(versions.DeleteMarkers);
					}
				} finally {
					client.destroy();
				}
			}
		} catch (error) {
			if (error instanceof RecoveryFault) throw error;
			throw new RecoveryFault('storage_access_required');
		}
	}

	async step(target: RecoveryTarget, cursor: Record<string, unknown>) {
		try {
			return usesNativeBackblaze(target)
				? await this.b2Step(target, cursor)
				: await this.s3Step(target, cursor);
		} catch (error) {
			if (error instanceof RecoveryFault) throw error;
			throw new RecoveryFault('storage_cleanup_blocked');
		}
	}

	private async s3Step(target: RecoveryTarget, cursor: Record<string, unknown>) {
		const client = this.s3Factory(target);
		const Bucket = required(target, 'bucketName');
		const Prefix = target.prefix;
		const uploads = cursor.step === 'uploads';
		const sendOptions = { abortSignal: AbortSignal.timeout(10_000) };
		try {
			if (uploads) {
				const data = await client.send(
					new ListMultipartUploadsCommand({
						Bucket,
						Prefix,
						MaxUploads: batchSize,
						KeyMarker: cursorString(cursor, 'key'),
						UploadIdMarker: cursorString(cursor, 'version')
					}),
					sendOptions
				);
				if (typeof data.IsTruncated !== 'boolean') throw new RecoveryFault('storage_unavailable');
				const owned = listingEntries(data.Uploads).filter((upload) =>
					isRetiredVaultObject(Prefix, upload.Key)
				);
				for (const upload of owned) {
					if (!upload.UploadId) throw new RecoveryFault('storage_unavailable');
					await client.send(
						new AbortMultipartUploadCommand({ Bucket, Key: upload.Key, UploadId: upload.UploadId }),
						sendOptions
					);
				}
				if (owned.length) return { cursor, done: false };
				if (
					data.IsTruncated &&
					(!data.NextKeyMarker ||
						(data.NextKeyMarker === cursor.key && data.NextUploadIdMarker === cursor.version))
				)
					throw new RecoveryFault('storage_unavailable');
				return {
					cursor: { step: 'uploads', key: data.NextKeyMarker, version: data.NextUploadIdMarker },
					done: !data.IsTruncated
				};
			}
			if (target.providerId === StorageProvider.CLOUDFLARE) {
				const data = await client.send(
					new ListObjectsV2Command({
						Bucket,
						Prefix,
						MaxKeys: batchSize,
						ContinuationToken: cursorString(cursor, 'token')
					}),
					sendOptions
				);
				if (typeof data.IsTruncated !== 'boolean') throw new RecoveryFault('storage_unavailable');
				const owned = listingEntries(data.Contents).filter((object) =>
					isRetiredVaultObject(Prefix, object.Key)
				);
				if (owned.length) {
					const deleted = await client.send(
						new DeleteObjectsCommand({
							Bucket,
							Delete: { Objects: owned.map((object) => ({ Key: object.Key })), Quiet: true }
						}),
						sendOptions
					);
					if (deleted.Errors?.length) throw new RecoveryFault('storage_cleanup_blocked');
					return { cursor, done: false };
				}
				if (
					data.IsTruncated &&
					(!data.NextContinuationToken || data.NextContinuationToken === cursor.token)
				)
					throw new RecoveryFault('storage_unavailable');
				return {
					cursor: data.IsTruncated ? { token: data.NextContinuationToken } : { step: 'uploads' },
					done: false
				};
			}
			const data = await client.send(
				new ListObjectVersionsCommand({
					Bucket,
					Prefix,
					MaxKeys: batchSize,
					KeyMarker: cursorString(cursor, 'key'),
					VersionIdMarker: cursorString(cursor, 'version')
				}),
				sendOptions
			);
			if (typeof data.IsTruncated !== 'boolean') throw new RecoveryFault('storage_unavailable');
			const owned = [
				...listingEntries(data.Versions),
				...listingEntries(data.DeleteMarkers)
			].filter((object) => isRetiredVaultObject(Prefix, object.Key));
			if (owned.length) {
				if (owned.some((object) => !object.VersionId))
					throw new RecoveryFault('storage_unavailable');
				const deleted = await client.send(
					new DeleteObjectsCommand({
						Bucket,
						// OCI's bulk-delete endpoint rejects the SDK's default CRC32.
						...(target.providerId === StorageProvider.OCI
							? { ChecksumAlgorithm: 'SHA256' as const }
							: {}),
						Delete: {
							Objects: owned.map((object) => ({ Key: object.Key, VersionId: object.VersionId })),
							Quiet: true
						}
					}),
					sendOptions
				);
				if (deleted.Errors?.length) throw new RecoveryFault('storage_cleanup_blocked');
				return { cursor, done: false };
			}
			if (
				data.IsTruncated &&
				(!data.NextKeyMarker ||
					(data.NextKeyMarker === cursor.key && data.NextVersionIdMarker === cursor.version))
			)
				throw new RecoveryFault('storage_unavailable');
			return {
				cursor: data.IsTruncated
					? { key: data.NextKeyMarker, version: data.NextVersionIdMarker }
					: { step: 'uploads' },
				done: false
			};
		} finally {
			client.destroy();
		}
	}

	private async b2(target: RecoveryTarget) {
		const authResponse = await this.fetcher(
			'https://api.backblazeb2.com/b2api/v4/b2_authorize_account',
			{
				headers: {
					Authorization: `Basic ${btoa(`${required(target, 'appId')}:${required(target, 'appKey')}`)}`
				},
				signal: AbortSignal.timeout(10_000),
				redirect: 'manual'
			}
		);
		if (!authResponse.ok) throw new RecoveryFault('storage_access_required');
		const auth = record(await authResponse.json());
		const api = record(record(auth.apiInfo).storageApi);
		const allowed = record(api.allowed);
		if (
			!Array.isArray(allowed.capabilities) ||
			!allowed.capabilities.includes('listFiles') ||
			!allowed.capabilities.includes('deleteFiles')
		) {
			throw new RecoveryFault('storage_access_required');
		}
		if (typeof api.apiUrl !== 'string' || typeof auth.authorizationToken !== 'string')
			throw new RecoveryFault('storage_unavailable');
		const token = auth.authorizationToken;
		const base = new URL(api.apiUrl);
		if (
			base.protocol !== 'https:' ||
			!base.hostname.endsWith('.backblazeb2.com') ||
			base.username ||
			base.password
		) {
			throw new RecoveryFault('storage_unavailable');
		}
		return async (action: string, body: Record<string, unknown>) => {
			const response = await this.fetcher(new URL(`/b2api/v4/${action}`, base), {
				method: 'POST',
				headers: { Authorization: token, 'Content-Type': 'application/json' },
				body: JSON.stringify(body),
				signal: AbortSignal.timeout(10_000),
				redirect: 'manual'
			});
			const data = record(await response.json());
			if (!response.ok && !(action.startsWith('b2_delete_') && data.code === 'file_not_present')) {
				throw new RecoveryFault('storage_cleanup_blocked');
			}
			return data;
		};
	}

	private async b2Step(target: RecoveryTarget, cursor: Record<string, unknown>) {
		const b2 = await this.b2(target);
		const unfinished = cursor.step === 'unfinished';
		const data = await b2(unfinished ? 'b2_list_unfinished_large_files' : 'b2_list_file_versions', {
			bucketId: required(target, 'bucketId'),
			maxFileCount: batchSize,
			...(unfinished
				? { namePrefix: target.prefix, startFileId: cursor.version }
				: { prefix: target.prefix, startFileName: cursor.key, startFileId: cursor.version })
		});
		if (
			!Array.isArray(data.files) ||
			data.files.some((file: { fileName?: unknown }) => !file || typeof file.fileName !== 'string')
		)
			throw new RecoveryFault('storage_unavailable');
		const owned = data.files.filter((file: { fileName: unknown }) =>
			isRetiredVaultObject(target.prefix, file.fileName)
		);
		for (const file of owned) {
			if (typeof file.fileId !== 'string') throw new RecoveryFault('storage_unavailable');
			await b2(
				unfinished || file.action === 'start' ? 'b2_cancel_large_file' : 'b2_delete_file_version',
				{
					fileId: file.fileId,
					...(!unfinished && file.action !== 'start' ? { fileName: file.fileName } : {})
				}
			);
		}
		if (owned.length) return { cursor, done: false };
		if (
			(data.nextFileName != null && typeof data.nextFileName !== 'string') ||
			(data.nextFileId != null && typeof data.nextFileId !== 'string')
		)
			throw new RecoveryFault('storage_unavailable');
		if (
			(unfinished && data.nextFileId && data.nextFileId === cursor.version) ||
			(!unfinished &&
				data.nextFileName &&
				data.nextFileName === cursor.key &&
				data.nextFileId === cursor.version)
		) {
			throw new RecoveryFault('storage_unavailable');
		}
		if (unfinished)
			return { cursor: { step: 'unfinished', version: data.nextFileId }, done: !data.nextFileId };
		return {
			cursor: data.nextFileName
				? { key: data.nextFileName, version: data.nextFileId }
				: { step: 'unfinished' },
			done: false
		};
	}
}
