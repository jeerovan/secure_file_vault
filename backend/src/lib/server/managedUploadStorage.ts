import {
	S3Client,
	CreateMultipartUploadCommand,
	UploadPartCommand,
	ListPartsCommand,
	CompleteMultipartUploadCommand,
	AbortMultipartUploadCommand,
	HeadObjectCommand,
	ListMultipartUploadsCommand,
	ListObjectVersionsCommand,
	DeleteObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { vaultUpload } from './db/schema';
import { StorageProvider } from './db/keys';
import { createRecoveryS3Client } from './recoveryStorage';
import { PRESIGNED_UPLOAD_EXPIRY_SECONDS } from './s3';
import { isManagedPartName } from './partObject';

export type UploadRecord = typeof vaultUpload.$inferSelect;
export interface UploadCleanupStep {
	done: boolean;
	cursor: Record<string, unknown>;
}
export class UploadFault extends Error {
	constructor(
		readonly code: string,
		readonly definite = false
	) {
		super(code);
	}
}
export interface ManagedUploadStorage {
	initiate(row: UploadRecord): Promise<string>;
	sign(row: UploadRecord): Promise<{ uploadUrl: string; headers: Record<string, string> }>;
	finalize(
		row: UploadRecord,
		beforeComplete?: () => Promise<boolean>
	): Promise<{ versionId: string | null }>;
	cleanup(row: UploadRecord): Promise<UploadCleanupStep>;
}
const options = () => ({ abortSignal: AbortSignal.timeout(20_000) });
const missing = (error: unknown) => {
	const e = error as { name?: string; $metadata?: { httpStatusCode?: number } };
	return (
		e.$metadata?.httpStatusCode === 404 &&
		['NoSuchKey', 'NoSuchUpload', 'NoSuchVersion', 'NotFound'].includes(e.name ?? '')
	);
};
const failure = (error: unknown, code: string) => {
	if (error instanceof UploadFault) return error;
	const status =
		(error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode ?? 0;
	return new UploadFault(code, status >= 400 && status < 500 && ![408, 409, 429].includes(status));
};

/** One provider multipart upload per encrypted FiFe part; never proxy its bytes. */
export class ProviderManagedUploadStorage implements ManagedUploadStorage {
	constructor(
		private readonly factory: (row: UploadRecord) => Pick<S3Client, 'send' | 'destroy'> = (row) =>
			createRecoveryS3Client(
				{ providerId: row.providerId, prefix: '', credentials: row.credentials },
				1
			)
	) {}
	private input(row: UploadRecord) {
		const Bucket = row.credentials.bucketName;
		if (typeof Bucket !== 'string' || !Bucket)
			throw new UploadFault('upload_storage_unavailable', true);
		return { Bucket, Key: row.objectKey };
	}
	async initiate(row: UploadRecord) {
		let client: Pick<S3Client, 'send' | 'destroy'>;
		try {
			client = this.factory(row);
		} catch {
			throw new UploadFault('upload_storage_unavailable', true);
		}
		try {
			const result = await client.send(
				new CreateMultipartUploadCommand({
					...this.input(row),
					ContentType: 'application/octet-stream',
					Metadata: { sha1: row.sha1, 'fife-upload': row.id }
				}),
				options()
			);
			if (!result.UploadId) throw new UploadFault('upload_initiation_unknown');
			return result.UploadId;
		} catch (error) {
			throw failure(error, 'upload_initiation_failed');
		} finally {
			client.destroy();
		}
	}
	async sign(row: UploadRecord) {
		if (!row.uploadId) throw new UploadFault('upload_not_ready', true);
		const client = this.factory(row) as S3Client;
		const headers = { 'Content-Length': String(row.contentLength), 'Content-MD5': row.md5 };
		try {
			const uploadUrl = await getSignedUrl(
				client,
				new UploadPartCommand({
					...this.input(row),
					UploadId: row.uploadId,
					PartNumber: 1,
					ContentLength: row.contentLength,
					ContentMD5: row.md5
				}),
				{
					expiresIn: PRESIGNED_UPLOAD_EXPIRY_SECONDS,
					signableHeaders: new Set(['content-md5', 'content-length'])
				}
			);
			return { uploadUrl, headers };
		} finally {
			client.destroy();
		}
	}
	private async head(client: Pick<S3Client, 'send'>, row: UploadRecord, VersionId?: string) {
		try {
			const result = await client.send(
				new HeadObjectCommand({ ...this.input(row), VersionId }),
				options()
			);
			if (!Number.isSafeInteger(result.ContentLength) || result.ContentLength! < 0)
				throw new UploadFault('upload_storage_unavailable');
			return result;
		} catch (error) {
			if (missing(error)) return null;
			throw error;
		}
	}
	private matches(
		row: UploadRecord,
		head: { ContentLength?: number; Metadata?: Record<string, string> } | null
	) {
		return (
			head?.ContentLength === row.contentLength &&
			head.Metadata?.sha1 === row.sha1 &&
			head.Metadata?.['fife-upload'] === row.id
		);
	}
	async finalize(row: UploadRecord, beforeComplete?: () => Promise<boolean>) {
		const client = this.factory(row);
		let completing = false;
		try {
			const existing = await this.head(client, row);
			if (this.matches(row, existing)) {
				if (
					[StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(row.providerId) &&
					!existing!.VersionId
				)
					throw new UploadFault('upload_outcome_unknown');
				return { versionId: existing!.VersionId ?? null };
			}
			const listed = await client.send(
				new ListPartsCommand({ ...this.input(row), UploadId: row.uploadId! }),
				options()
			);
			if (
				listed.IsTruncated !== false ||
				listed.Parts?.length !== 1 ||
				listed.Parts[0].PartNumber !== 1 ||
				listed.Parts[0].Size !== row.contentLength ||
				!listed.Parts[0].ETag
			)
				throw new UploadFault('upload_not_ready', true);
			if (beforeComplete && !(await beforeComplete()))
				throw new UploadFault('upload_retired', true);
			completing = true;
			const result = await client.send(
				new CompleteMultipartUploadCommand({
					...this.input(row),
					UploadId: row.uploadId!,
					MultipartUpload: { Parts: [{ PartNumber: 1, ETag: listed.Parts[0].ETag }] }
				}),
				options()
			);
			const verified = await this.head(client, row);
			if (!this.matches(row, verified)) throw new UploadFault('upload_outcome_unknown');
			const versionId = verified?.VersionId ?? result.VersionId ?? null;
			if ([StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(row.providerId) && !versionId)
				throw new UploadFault('upload_outcome_unknown');
			return { versionId };
		} catch (error) {
			if (!completing && error instanceof UploadFault) throw error;
			if (!completing && row.uncertain !== 'complete')
				throw new UploadFault(
					missing(error) ? 'upload_missing' : 'upload_verification_unavailable',
					true
				);
			const result = failure(error, 'upload_outcome_unknown');
			if (completing && result.definite && row.uncertain !== 'complete')
				throw new UploadFault('upload_finalization_rejected', true);
			// NoSuchUpload after an earlier lost completion is not proof of failure.
			throw result;
		} finally {
			client.destroy();
		}
	}
	async cleanup(row: UploadRecord) {
		const client = this.factory(row);
		const cursor = row.cleanupCursor;
		const pending = (next = cursor): UploadCleanupStep => ({ done: false, cursor: next });
		try {
			const input = this.input(row);
			if (cursor.settled !== true) {
				let uploadId = row.uploadId;
				if (!uploadId) {
					const listed = await client.send(
						new ListMultipartUploadsCommand({
							Bucket: input.Bucket,
							Prefix: input.Key,
							MaxUploads: 1000
						}),
						options()
					);
					const exact = listed.Uploads?.filter((u) => u.Key === row.objectKey) ?? [];
					// A timed-out initiation with no visible ID remains indeterminate.
					if (listed.IsTruncated !== false || exact.length !== 1 || !exact[0].UploadId)
						return pending();
					uploadId = exact[0].UploadId;
				}
				let before = await this.head(client, row);
				let proofVersion =
					row.versionId ?? (this.matches(row, before) ? before?.VersionId : undefined);
				// A completion sent before reset may still be executing remotely. Wait
				// for its matching object instead of interpreting an empty sweep as done.
				if (row.uncertain === 'complete' && !this.matches(row, before)) {
					// Recover a server crash between its durable completion intent and
					// the provider request. Reconcile only this already-claimed upload;
					// it remains retired and is deleted before readiness can advance.
					try {
						proofVersion = (await this.finalize(row)).versionId ?? proofVersion;
					} catch {
						return pending();
					}
					before = await this.head(client, row);
					if (!this.matches(row, before)) return pending();
					proofVersion ??= before?.VersionId;
				}
				try {
					await client.send(
						new AbortMultipartUploadCommand({ ...input, UploadId: uploadId }),
						options()
					);
				} catch (error) {
					if (!missing(error)) throw error;
				}
				try {
					const parts = await client.send(
						new ListPartsCommand({ ...input, UploadId: uploadId }),
						options()
					);
					if (parts.Parts !== undefined && !Array.isArray(parts.Parts))
						throw new UploadFault('upload_storage_unavailable');
					if (parts.IsTruncated !== false || parts.Parts?.length) return pending();
					// An empty list is still an addressable upload ID. Require the
					// provider's terminal NoSuchUpload result before acknowledging abort.
					return pending();
				} catch (error) {
					if (!missing(error) || (error as { name?: string }).name !== 'NoSuchUpload') throw error;
				}
				// Checkpoint before any deletion can remove completion evidence.
				return pending({ settled: true, ...(proofVersion ? { proofVersion } : {}) });
			}
			if (row.providerId === StorageProvider.CLOUDFLARE) {
				if (this.matches(row, await this.head(client, row))) {
					await client.send(new DeleteObjectCommand(input), options());
					return pending();
				}
				return { done: true, cursor: {} };
			}
			const listed = await client.send(
				new ListObjectVersionsCommand({
					Bucket: input.Bucket,
					Prefix: input.Key,
					MaxKeys: 5,
					KeyMarker: typeof cursor.key === 'string' ? cursor.key : undefined,
					VersionIdMarker: typeof cursor.version === 'string' ? cursor.version : undefined
				}),
				options()
			);
			if (
				typeof listed.IsTruncated !== 'boolean' ||
				(listed.Versions !== undefined && !Array.isArray(listed.Versions)) ||
				(listed.DeleteMarkers !== undefined && !Array.isArray(listed.DeleteMarkers))
			)
				throw new UploadFault('upload_storage_unavailable');
			let removed = false;
			for (const version of listed.Versions ?? []) {
				if (
					!version ||
					typeof version.Key !== 'string' ||
					(version.Key === row.objectKey && !version.VersionId)
				)
					throw new UploadFault('upload_storage_unavailable');
				if (version.Key !== row.objectKey || !version.VersionId) continue;
				const head = await this.head(client, row, version.VersionId);
				if (this.matches(row, head)) {
					await client.send(
						new DeleteObjectCommand({ ...input, VersionId: version.VersionId }),
						options()
					);
					removed = true;
				}
			}
			// Unique managed keys cannot contain another upload's marker. Legacy
			// canonical keys remain shared, so leave their unrelated markers alone.
			if (isManagedPartName(row.objectKey.slice(row.objectKey.lastIndexOf('/') + 1))) {
				for (const marker of listed.DeleteMarkers ?? []) {
					if (marker.Key !== row.objectKey) continue;
					if (!marker.VersionId) throw new UploadFault('upload_storage_unavailable');
					await client.send(
						new DeleteObjectCommand({ ...input, VersionId: marker.VersionId }),
						options()
					);
					removed = true;
				}
			}
			// Relist after deletions: never resume from a marker just deleted.
			if (removed) return pending();
			if (listed.IsTruncated) {
				if (
					!listed.NextKeyMarker ||
					(listed.NextKeyMarker === cursor.key && listed.NextVersionIdMarker === cursor.version)
				)
					throw new UploadFault('upload_storage_unavailable');
				return pending({
					...cursor,
					key: listed.NextKeyMarker,
					version: listed.NextVersionIdMarker
				});
			}
			const restart = {
				settled: true,
				...(cursor.proofVersion ? { proofVersion: cursor.proofVersion } : {})
			};
			if (this.matches(row, await this.head(client, row))) return pending(restart);
			if (
				typeof cursor.proofVersion === 'string' &&
				this.matches(row, await this.head(client, row, cursor.proofVersion))
			)
				return pending(restart);
			return { done: true, cursor: {} };
		} catch {
			throw new UploadFault('upload_cleanup_blocked');
		} finally {
			client.destroy();
		}
	}
}
