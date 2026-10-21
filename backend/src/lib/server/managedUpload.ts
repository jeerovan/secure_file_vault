import { and, eq, ne } from 'drizzle-orm';
import type { AuthUser } from './auth';
import type { Db, Tx } from './db';
import { file, part, tempStorage, user, vaultUpload } from './db/schema';
import {
	CredentialKeys,
	FileKeys,
	PartKeys,
	TempStorageKeys,
	StorageProvider,
	UserKeys
} from './db/keys';
import { authorizeRegisteredDevice } from './deviceAccess';
import { getCredentialByStorageId, updateStorageUsedSize, updateTempStorageSize } from './db/api';
import { authenticate } from './backblaze';
import { recoveryHash } from './recoverySession';
import { isVaultPartName } from './recoveryStorage';
import { validBackblazeUploadIntegrity } from './backblazeS3';
import { UploadFault, type ManagedUploadStorage, type UploadRecord } from './managedUploadStorage';
import { referencesPartObject } from './partObject';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const receiptPattern = /^[A-Za-z0-9_-]{43}$/;
const leaseMs = 120_000;
// This is idle garbage collection, not a claim about maximum upload duration.
const idleMs = 24 * 60 * 60_000;
const credentialFields = [
	'appId',
	'appKey',
	'bucketName',
	'bucketId',
	'accountId',
	'namespace',
	'region',
	'endpoint',
	's3ApiUrl',
	'forcePathStyle'
];
export interface UploadInput {
	id: string;
	receipt: string;
	storage_id: number;
	file_id: string;
	content_length: number;
	content_sha1: string;
	content_md5: string;
	part_metadata: { cipher: string; nonce: string };
}
export type UploadView = {
	protocol: 'managed-v1';
	id: string;
	state: string;
	fileId?: string;
	uploadUrl?: string;
	headers?: Record<string, string>;
	method?: string;
	expiresIn?: number;
	file?: Record<string, unknown>;
	part?: Record<string, unknown>;
	cleanupRequired?: boolean;
};
const view = (row: UploadRecord): UploadView => ({
	protocol: 'managed-v1',
	id: row.id,
	state:
		row.phase === 'deleted'
			? 'deleted'
			: row.retired || row.phase === 'cleanup'
				? 'cleanup_pending'
				: ['complete', 'stored'].includes(row.phase)
					? 'complete'
					: 'pending',
	...(['complete', 'stored'].includes(row.phase) && !row.retired && row.versionId
		? { fileId: row.versionId }
		: {})
});

export class ManagedUploadService {
	constructor(
		private readonly db: Db,
		private readonly cloud: ManagedUploadStorage,
		private readonly clock = Date.now
	) {}
	private async lock(tx: Tx, userId: number) {
		await tx
			.select({ id: user[UserKeys.ID] })
			.from(user)
			.where(eq(user[UserKeys.ID], userId))
			.for('update');
	}
	private async row(tx: Db | Tx, id: string) {
		return (await tx.select().from(vaultUpload).where(eq(vaultUpload.id, id)).limit(1))[0];
	}
	private async access(tx: Tx, auth: AuthUser) {
		const current = await authorizeRegisteredDevice(tx, auth, true);
		if (!current.authorized) throw new UploadFault(current.reason ?? 'upload_unauthorized', true);
		return current;
	}
	private async validReceipt(row: UploadRecord | undefined, receipt: unknown) {
		if (
			!row ||
			typeof receipt !== 'string' ||
			!receiptPattern.test(receipt) ||
			(await recoveryHash(receipt)) !== row.receiptHash
		)
			throw new UploadFault('upload_not_found', true);
		return row;
	}
	private async liveFile(tx: Db | Tx, row: UploadRecord) {
		const hash = row.partName.slice(0, row.partName.lastIndexOf('_'));
		const [entry] = await tx
			.select()
			.from(file)
			.where(and(eq(file[FileKeys.USER_ID], row.userId), eq(file[FileKeys.FILE_HASH], hash)))
			.limit(1);
		if (!entry || entry[FileKeys.DELETED]) return false;
		if (entry[FileKeys.STORAGE_ID] === row.storageId) return true;
		if (entry[FileKeys.STORAGE_ID]) return false;
		// The allocation API reserves storage before the client can sync its
		// updated file row. The reservation is authoritative for that interval.
		const [reservation] = await tx
			.select()
			.from(tempStorage)
			.where(
				and(
					eq(tempStorage[TempStorageKeys.USER_ID], row.userId),
					eq(tempStorage[TempStorageKeys.FILE_ID], entry[FileKeys.ID]),
					eq(tempStorage[TempStorageKeys.STORAGE_ID], row.storageId),
					eq(tempStorage[TempStorageKeys.PROVIDER_ID], row.providerId)
				)
			)
			.limit(1);
		return !!reservation;
	}
	private async completedPart(tx: Db | Tx, userId: number, partName: string) {
		const separator = partName.lastIndexOf('_');
		const [existing] = await tx
			.select({ file, part })
			.from(part)
			.innerJoin(file, eq(part[PartKeys.FILE_ID], file[FileKeys.ID]))
			.where(
				and(
					eq(part[PartKeys.USER_ID], userId),
					eq(file[FileKeys.USER_ID], userId),
					eq(file[FileKeys.FILE_HASH], partName.slice(0, separator)),
					eq(part[PartKeys.PART_NUMBER], Number(partName.slice(separator + 1))),
					eq(part[PartKeys.UPLOADED], 1),
					eq(part[PartKeys.DELETED], 0),
					eq(file[FileKeys.DELETED], 0)
				)
			)
			.limit(1);
		return (
			existing && {
				file: existing.file,
				part: { ...existing.part, [PartKeys.FILE_ID]: existing.file[FileKeys.FILE_HASH] }
			}
		);
	}
	private async stagedPart(tx: Db | Tx, row: UploadRecord) {
		const separator = row.partName.lastIndexOf('_');
		const [entry] = await tx
			.select({ file, part })
			.from(part)
			.innerJoin(file, eq(part[PartKeys.FILE_ID], file[FileKeys.ID]))
			.where(
				and(
					eq(part[PartKeys.USER_ID], row.userId),
					eq(file[FileKeys.USER_ID], row.userId),
					eq(file[FileKeys.FILE_HASH], row.partName.slice(0, separator)),
					eq(part[PartKeys.PART_NUMBER], Number(row.partName.slice(separator + 1))),
					eq(part[PartKeys.DELETED], 0)
				)
			)
			.limit(1);
		return entry &&
			entry.part[PartKeys.PART_SIZE] === row.contentLength &&
			(entry.part[PartKeys.JSON] as Record<string, unknown> | null)?.sha1 === row.sha1 &&
			entry.part[PartKeys.CIPHER] &&
			entry.part[PartKeys.NONCE]
			? entry
			: undefined;
	}
	private async completedView(tx: Db | Tx, row: UploadRecord): Promise<UploadView> {
		const result = view(row);
		if (result.state !== 'complete') return result;
		const accepted = await this.completedPart(tx, row.userId, row.partName);
		return accepted &&
			accepted.file[FileKeys.STORAGE_ID] === row.storageId &&
			referencesPartObject(row.objectKey, row.partName, accepted.part[PartKeys.JSON])
			? { ...result, ...accepted }
			: result;
	}
	private async adoptAcceptedPart(tx: Tx, row: UploadRecord) {
		if (row.phase === 'deleted') return null;
		const accepted = await this.completedPart(tx, row.userId, row.partName);
		if (
			!accepted ||
			(['complete', 'stored'].includes(row.phase) &&
				referencesPartObject(row.objectKey, row.partName, accepted.part[PartKeys.JSON]))
		)
			return null;
		const [updated] = await tx
			.update(vaultUpload)
			.set({
				retired: 1,
				nextAttemptAt: this.clock(),
				phase: row.leaseUntil > this.clock() ? row.phase : 'cleanup'
			})
			.where(eq(vaultUpload.id, row.id))
			.returning();
		return { row: updated, existing: accepted };
	}
	private async stagePart(tx: Tx, row: UploadRecord, metadata: UploadInput['part_metadata']) {
		const separator = row.partName.lastIndexOf('_');
		const [entry] = await tx
			.select()
			.from(file)
			.where(
				and(
					eq(file[FileKeys.USER_ID], row.userId),
					eq(file[FileKeys.FILE_HASH], row.partName.slice(0, separator))
				)
			)
			.limit(1);
		const match = and(
			eq(part[PartKeys.USER_ID], row.userId),
			eq(part[PartKeys.FILE_ID], entry[FileKeys.ID]),
			eq(part[PartKeys.PART_NUMBER], Number(row.partName.slice(separator + 1)))
		);
		const [existing] = await tx.select().from(part).where(match).limit(1);
		const values = {
			[PartKeys.DEVICE_UUID]: row.deviceUuid,
			[PartKeys.PART_SIZE]: row.contentLength,
			[PartKeys.CIPHER]: metadata.cipher,
			[PartKeys.NONCE]: metadata.nonce,
			[PartKeys.JSON]: { sha1: row.sha1 },
			[PartKeys.UPLOADED]: 0,
			[PartKeys.DELETED]: 0,
			[PartKeys.CLIENT_UPDATED_AT]: Math.max(
				this.clock(),
				(existing?.[PartKeys.CLIENT_UPDATED_AT] ?? 0) + 1
			)
		};
		if (existing) await tx.update(part).set(values).where(match);
		else
			await tx.insert(part).values({
				...values,
				[PartKeys.USER_ID]: row.userId,
				[PartKeys.FILE_ID]: entry[FileKeys.ID],
				[PartKeys.PART_NUMBER]: Number(row.partName.slice(separator + 1))
			});
	}
	private async publishPart(tx: Tx, row: UploadRecord, versionId: string | null) {
		const entry = await this.stagedPart(tx, row);
		if (!entry) throw new UploadFault('upload_file_missing', true);
		if (entry.part[PartKeys.UPLOADED]) return;
		// Commit the encrypted recovery key and completion with the ledger. A
		// client crash before its next metadata sync cannot strand a valid object.
		await tx
			.update(part)
			.set({
				[PartKeys.UPLOADED]: 1,
				[PartKeys.JSON]: {
					sha1: row.sha1,
					managedUploadId: row.id,
					managedObjectKey: row.objectKey,
					...(versionId ? { fileId: versionId } : {})
				},
				[PartKeys.CLIENT_UPDATED_AT]: Math.max(
					this.clock(),
					entry.part[PartKeys.CLIENT_UPDATED_AT] + 1
				)
			})
			.where(eq(part[PartKeys.ID], entry.part[PartKeys.ID]));
		if (!entry.file[FileKeys.STORAGE_ID])
			await tx
				.update(file)
				.set({
					[FileKeys.STORAGE_ID]: row.storageId,
					[FileKeys.PROVIDER_ID]: row.providerId
				})
				.where(eq(file[FileKeys.ID], entry.file[FileKeys.ID]));
		await updateStorageUsedSize(tx, row.storageId, row.userId, row.contentLength, true);
		await updateTempStorageSize(tx, row.userId, entry.file[FileKeys.ID], row.contentLength);
	}
	async prepare(auth: AuthUser, input: UploadInput): Promise<UploadView> {
		if (
			!input ||
			typeof input.id !== 'string' ||
			!uuid.test(input.id) ||
			typeof input.receipt !== 'string' ||
			!receiptPattern.test(input.receipt) ||
			!isVaultPartName(input.file_id) ||
			input.file_id.length > 64 ||
			!Number.isSafeInteger(Number(input.file_id.slice(44))) ||
			!Number.isSafeInteger(input.storage_id) ||
			input.storage_id <= 0 ||
			!validBackblazeUploadIntegrity(input as unknown as Record<string, unknown>)
		)
			throw new UploadFault('invalid_upload_request', true);
		// Discover old Backblaze rows outside the upload/reset transaction. The
		// authoritative membership and credential snapshot are re-read below.
		const initial = await getCredentialByStorageId(this.db, auth.userId!, input.storage_id);
		if (
			initial &&
			[StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(
				initial[CredentialKeys.PROVIDER_ID]
			)
		)
			await authenticate(this.db, auth.userId!, input.storage_id);
		const receiptHash = await recoveryHash(input.receipt);
		const claimed = await this.db.transaction(async (tx) => {
			const current = await this.access(tx, auth);
			const existing = await this.row(tx, input.id);
			if (existing) {
				if (
					existing.phase === 'deleted' &&
					existing.userId === current.userId &&
					existing.receiptHash === receiptHash
				)
					return { row: existing, owner: null };
				if (
					existing.userId !== current.userId ||
					existing.deviceUuid !== current.deviceUuid ||
					existing.generation !== current.vaultGeneration ||
					existing.receiptHash !== receiptHash ||
					existing.storageId !== input.storage_id ||
					existing.partName !== input.file_id ||
					existing.contentLength !== input.content_length ||
					existing.sha1 !== input.content_sha1.toLowerCase() ||
					existing.md5 !== input.content_md5
				)
					throw new UploadFault('upload_conflict', true);
				const accepted = await this.adoptAcceptedPart(tx, existing);
				if (accepted) return { existing: accepted.existing, cleanupRequired: true };
				if (['complete', 'stored'].includes(existing.phase) && !existing.retired)
					return { result: await this.completedView(tx, existing) };
				if (existing.phase === 'uploading' && !existing.retired) {
					await tx
						.update(vaultUpload)
						.set({ nextAttemptAt: this.clock() + idleMs, updatedAt: this.clock() })
						.where(eq(vaultUpload.id, existing.id));
				}
				return { row: existing, owner: null };
			}
			const credentials = await getCredentialByStorageId(tx, current.userId!, input.storage_id);
			if (!credentials) throw new UploadFault('upload_storage_unavailable', true);
			const completed = await this.completedPart(tx, current.userId!, input.file_id);
			if (completed) return { existing: completed };
			if (
				typeof input.part_metadata?.cipher !== 'string' ||
				!input.part_metadata.cipher ||
				input.part_metadata.cipher.length > 4096 ||
				typeof input.part_metadata?.nonce !== 'string' ||
				!input.part_metadata.nonce ||
				input.part_metadata.nonce.length > 1024
			)
				throw new UploadFault('invalid_upload_request', true);
			const objectKey = `${current.objectPrefix}${input.file_id}~${input.id}`;
			const [busy] = await tx
				.select({ id: vaultUpload.id })
				.from(vaultUpload)
				.where(
					and(
						eq(vaultUpload.userId, current.userId!),
						eq(vaultUpload.storageId, input.storage_id),
						eq(vaultUpload.partName, input.file_id),
						eq(vaultUpload.generation, current.vaultGeneration!),
						ne(vaultUpload.phase, 'deleted')
					)
				)
				.limit(1);
			if (busy) throw new UploadFault('upload_object_busy', true);
			const now = this.clock(),
				owner = crypto.randomUUID();
			const [row] = await tx
				.insert(vaultUpload)
				.values({
					id: input.id,
					userId: current.userId!,
					deviceUuid: current.deviceUuid!,
					generation: current.vaultGeneration!,
					storageId: input.storage_id,
					providerId: credentials[CredentialKeys.PROVIDER_ID],
					objectKey,
					partName: input.file_id,
					credentials: Object.fromEntries(
						Object.entries(
							credentials[CredentialKeys.CREDENTIALS] as Record<string, unknown>
						).filter(([key]) => credentialFields.includes(key))
					),
					receiptHash,
					contentLength: input.content_length,
					sha1: input.content_sha1.toLowerCase(),
					md5: input.content_md5,
					createdAt: now,
					updatedAt: now,
					leaseOwner: owner,
					leaseUntil: now + leaseMs,
					nextAttemptAt: now + idleMs,
					uncertain: 'create'
				})
				.returning();
			if (!(await this.liveFile(tx, row))) throw new UploadFault('upload_file_missing', true);
			await this.stagePart(tx, row, input.part_metadata);
			return { row, owner };
		});
		if ('existing' in claimed)
			return {
				protocol: 'managed-v1',
				id: input.id,
				state: 'existing',
				...claimed.existing,
				...('cleanupRequired' in claimed ? { cleanupRequired: true } : {})
			} as UploadView;
		if ('result' in claimed) return claimed.result!;
		let row = claimed.row;
		if (claimed.owner) {
			try {
				const uploadId = await this.cloud.initiate(row);
				row = await this.db.transaction(async (tx) => {
					await this.lock(tx, row.userId);
					const latest = (await this.row(tx, row.id))!;
					const access = await authorizeRegisteredDevice(tx, auth);
					const retired =
						latest.retired || !access.authorized || !(await this.liveFile(tx, latest)) ? 1 : 0;
					const [updated] = await tx
						.update(vaultUpload)
						.set({
							uploadId,
							uncertain: null,
							retired,
							phase: retired ? 'cleanup' : 'uploading',
							leaseOwner: null,
							leaseUntil: 0,
							updatedAt: this.clock(),
							nextAttemptAt: retired ? this.clock() : this.clock() + idleMs
						})
						.where(and(eq(vaultUpload.id, row.id), eq(vaultUpload.leaseOwner, claimed.owner!)))
						.returning();
					if (!updated) throw new UploadFault('upload_outcome_unknown');
					return updated;
				});
			} catch (error) {
				const definite = error instanceof UploadFault && error.definite;
				await this.db
					.update(vaultUpload)
					.set({
						phase: definite ? 'deleted' : 'cleanup',
						uncertain: definite ? null : 'create',
						leaseOwner: null,
						leaseUntil: 0,
						updatedAt: this.clock(),
						nextAttemptAt: this.clock(),
						error: definite ? 'upload_initiation_rejected' : 'upload_initiation_unknown',
						...(definite
							? {
									credentials: {},
									uploadId: null,
									versionId: null,
									deviceUuid: '',
									objectKey: '',
									partName: '',
									contentLength: 0,
									sha1: '',
									md5: ''
								}
							: {})
					})
					.where(and(eq(vaultUpload.id, row.id), eq(vaultUpload.leaseOwner, claimed.owner)));
				throw new UploadFault(
					definite ? 'upload_initiation_rejected' : 'upload_initiation_unknown'
				);
			}
		}
		if (row.phase !== 'uploading' || row.retired) return view(row);
		const descriptor = await this.cloud.sign(row);
		// Signing must not expose a usable descriptor if reset/removal won meanwhile.
		return this.db.transaction(async (tx) => {
			await this.access(tx, auth);
			const latest = (await this.row(tx, row.id))!;
			return latest.retired || latest.phase !== 'uploading'
				? view(latest)
				: {
						...view(latest),
						state: 'upload',
						...descriptor,
						method: 'PUT',
						expiresIn: 900
					};
		});
	}
	async complete(auth: AuthUser, id: string, receipt: string): Promise<UploadView> {
		if (typeof id !== 'string' || !uuid.test(id)) throw new UploadFault('upload_not_found', true);
		const claimed = await this.db.transaction(async (tx) => {
			const current = await this.access(tx, auth);
			const row = await this.validReceipt(await this.row(tx, id), receipt);
			if (row.phase === 'deleted' && row.userId === current.userId) return { row, owner: null };
			if (
				row.userId !== current.userId ||
				row.deviceUuid !== current.deviceUuid ||
				row.generation !== current.vaultGeneration
			)
				throw new UploadFault('upload_not_found', true);
			const accepted = await this.adoptAcceptedPart(tx, row);
			if (accepted) return { ...accepted, owner: null };
			if (row.retired || row.phase === 'cleanup' || row.phase === 'deleted')
				return { row, owner: null };
			if (!(await this.liveFile(tx, row)) || !(await this.stagedPart(tx, row))) {
				const [updated] = await tx
					.update(vaultUpload)
					.set({ phase: 'cleanup', retired: 1, nextAttemptAt: this.clock() })
					.where(eq(vaultUpload.id, id))
					.returning();
				return { row: updated, owner: null };
			}
			if (['complete', 'stored'].includes(row.phase))
				return { row, owner: null, result: await this.completedView(tx, row) };
			if (row.leaseUntil > this.clock() || row.phase === 'creating') return { row, owner: null };
			const owner = crypto.randomUUID();
			await tx
				.update(vaultUpload)
				.set({
					phase: 'verifying',
					leaseOwner: owner,
					leaseUntil: this.clock() + leaseMs,
					updatedAt: this.clock()
				})
				.where(eq(vaultUpload.id, id));
			return { row, owner };
		});
		if ('existing' in claimed)
			return {
				protocol: 'managed-v1',
				id,
				state: 'existing',
				...claimed.existing,
				cleanupRequired: true
			} as UploadView;
		if (!claimed.owner)
			return 'result' in claimed && claimed.result ? claimed.result : view(claimed.row);
		try {
			const result = await this.cloud.finalize(claimed.row, async () =>
				this.db.transaction(async (tx) => {
					const access = await authorizeRegisteredDevice(tx, auth, true);
					const latest = await this.row(tx, id);
					if (!latest || latest.leaseOwner !== claimed.owner) return false;
					if (
						!access.authorized ||
						latest.retired ||
						!(await this.liveFile(tx, latest)) ||
						!(await this.stagedPart(tx, latest))
					) {
						await tx
							.update(vaultUpload)
							.set({ retired: 1, phase: 'cleanup', nextAttemptAt: this.clock() })
							.where(eq(vaultUpload.id, id));
						return false;
					}
					await tx
						.update(vaultUpload)
						.set({ phase: 'finalizing', uncertain: 'complete', updatedAt: this.clock() })
						.where(eq(vaultUpload.id, id));
					return true;
				})
			);
			return await this.db.transaction(async (tx) => {
				await this.lock(tx, claimed.row.userId);
				const latest = (await this.row(tx, id))!;
				const access = await authorizeRegisteredDevice(tx, auth);
				const retired =
					latest.retired ||
					!access.authorized ||
					!(await this.liveFile(tx, latest)) ||
					!(await this.stagedPart(tx, latest))
						? 1
						: 0;
				if (!retired && latest.leaseOwner === claimed.owner)
					await this.publishPart(tx, latest, result.versionId);
				const [updated] = await tx
					.update(vaultUpload)
					.set({
						retired,
						phase: retired ? 'cleanup' : 'stored',
						versionId: result.versionId,
						uncertain: null,
						leaseOwner: null,
						leaseUntil: 0,
						error: null,
						updatedAt: this.clock(),
						nextAttemptAt: retired ? this.clock() : this.clock() + idleMs
					})
					.where(and(eq(vaultUpload.id, id), eq(vaultUpload.leaseOwner, claimed.owner!)))
					.returning();
				return this.completedView(tx, updated ?? latest);
			});
		} catch (error) {
			const retiredBeforeIntent = error instanceof UploadFault && error.code === 'upload_retired';
			const notReady = error instanceof UploadFault && error.code === 'upload_not_ready';
			const verificationFailed =
				error instanceof UploadFault && error.code === 'upload_verification_unavailable';
			const rejected =
				error instanceof UploadFault &&
				['upload_missing', 'upload_finalization_rejected', 'upload_retired'].includes(error.code);
			const uncertain = retiredBeforeIntent
				? claimed.row.uncertain === 'complete'
				: !(notReady || verificationFailed || rejected);
			await this.db.transaction(async (tx) => {
				await this.lock(tx, claimed.row.userId);
				const row = (await this.row(tx, id))!;
				const retired = row.retired || rejected ? 1 : 0;
				await tx
					.update(vaultUpload)
					.set({
						retired,
						phase: retired ? 'cleanup' : uncertain ? 'finalizing' : 'uploading',
						uncertain: uncertain ? 'complete' : null,
						leaseOwner: null,
						leaseUntil: 0,
						nextAttemptAt: retired ? this.clock() : this.clock() + idleMs,
						updatedAt: this.clock(),
						error: notReady
							? null
							: uncertain
								? 'upload_outcome_unknown'
								: verificationFailed
									? 'upload_verification_unavailable'
									: 'upload_cleanup_pending'
					})
					.where(and(eq(vaultUpload.id, id), eq(vaultUpload.leaseOwner, claimed.owner!)));
			});
			if (retiredBeforeIntent) return view((await this.row(this.db, id))!);
			throw new UploadFault(
				notReady
					? 'upload_not_ready'
					: verificationFailed
						? 'upload_verification_unavailable'
						: rejected
							? 'upload_cleanup_pending'
							: 'upload_outcome_unknown'
			);
		}
	}
	/** Cleanup-only capability; deliberately does not require a surviving device. */
	async report(id: string, receipt: string) {
		if (typeof id !== 'string' || !uuid.test(id)) throw new UploadFault('upload_not_found', true);
		const initial = await this.validReceipt(await this.row(this.db, id), receipt);
		return this.db.transaction(async (tx) => {
			await this.lock(tx, initial.userId);
			const row = await this.validReceipt(await this.row(tx, id), receipt);
			if (row.phase === 'deleted') return view(row);
			if (['complete', 'stored'].includes(row.phase) && !row.retired) {
				const accepted = await this.completedPart(tx, row.userId, row.partName);
				if (
					accepted &&
					accepted.file[FileKeys.STORAGE_ID] === row.storageId &&
					referencesPartObject(row.objectKey, row.partName, accepted.part[PartKeys.JSON])
				)
					return { protocol: 'managed-v1', id, state: 'committed' } as UploadView;
			}
			const entry = await this.stagedPart(tx, row);
			if (
				entry &&
				(!entry.part[PartKeys.UPLOADED] ||
					referencesPartObject(row.objectKey, row.partName, entry.part[PartKeys.JSON]))
			) {
				if (entry.part[PartKeys.UPLOADED])
					await updateStorageUsedSize(tx, row.storageId, row.userId, row.contentLength, false);
				await tx
					.update(part)
					.set({
						[PartKeys.UPLOADED]: 0,
						[PartKeys.DELETED]: 1,
						[PartKeys.CIPHER]: null,
						[PartKeys.NONCE]: null,
						[PartKeys.JSON]: {},
						[PartKeys.DEVICE_UUID]: 'SERVER',
						[PartKeys.CLIENT_UPDATED_AT]: Math.max(
							this.clock(),
							entry.part[PartKeys.CLIENT_UPDATED_AT] + 1
						)
					})
					.where(eq(part[PartKeys.ID], entry.part[PartKeys.ID]));
				if (entry.file[FileKeys.UPLOADED_AT])
					await tx
						.update(file)
						.set({
							[FileKeys.UPLOADED_AT]: 0,
							[FileKeys.DEVICE_UUID]: 'SERVER',
							[FileKeys.CLIENT_UPDATED_AT]: Math.max(
								this.clock(),
								entry.file[FileKeys.CLIENT_UPDATED_AT] + 1
							)
						})
						.where(eq(file[FileKeys.ID], entry.file[FileKeys.ID]));
			}
			const [updated] = await tx
				.update(vaultUpload)
				.set({
					retired: 1,
					phase: row.leaseUntil > this.clock() ? row.phase : 'cleanup',
					nextAttemptAt: this.clock(),
					updatedAt: this.clock()
				})
				.where(eq(vaultUpload.id, id))
				.returning();
			return view(updated);
		});
	}
}

export { drainManagedUploads } from './managedUploadCleanup';
