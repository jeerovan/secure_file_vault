import { and, asc, eq, inArray, lt, lte, ne, or, notExists, sql } from 'drizzle-orm';
import type { Db } from './db';
import { vaultUpload, file, part, user, storage } from './db/schema';
import { FileKeys, PartKeys, UserKeys, StorageKeys } from './db/keys';
import type { ManagedUploadStorage } from './managedUploadStorage';

const leaseMs = 120_000;

/** Durable garbage collection also runs without an account reset or client. */
export async function drainManagedUploads(
	db: Db,
	cloud: ManagedUploadStorage,
	options: { now?: () => number; limit?: number } = {}
) {
	const clock = options.now ?? Date.now;
	let processed = 0;
	for (let i = 0; i < (options.limit ?? 4); i++) {
		const owner = crypto.randomUUID(),
			now = clock();
		const row = await db.transaction(async (tx) => {
			const reference = tx
				.select({ id: part[PartKeys.ID] })
				.from(part)
				.innerJoin(file, eq(part[PartKeys.FILE_ID], file[FileKeys.ID]))
				.where(
					and(
						eq(part[PartKeys.USER_ID], vaultUpload.userId),
						eq(file[FileKeys.USER_ID], vaultUpload.userId),
						eq(file[FileKeys.STORAGE_ID], vaultUpload.storageId),
						eq(file[FileKeys.DELETED], 0),
						eq(part[PartKeys.UPLOADED], 1),
						eq(part[PartKeys.DELETED], 0),
						or(
							eq(sql<string>`${part[PartKeys.JSON]} ->> 'managedObjectKey'`, vaultUpload.objectKey),
							and(
								sql`${part[PartKeys.JSON]} ->> 'managedObjectKey' IS NULL`,
								eq(
									sql<string>`${file[FileKeys.FILE_HASH]} || '_' || ${part[PartKeys.PART_NUMBER]}::text`,
									vaultUpload.partName
								),
								sql`right(${vaultUpload.objectKey}, length(${vaultUpload.partName}) + 1) = '/' || ${vaultUpload.partName}`
							)
						)
					)
				);
			const orphaned = and(
				inArray(vaultUpload.phase, ['complete', 'stored']),
				notExists(reference)
			);
			const eligible = and(
				ne(vaultUpload.phase, 'deleted'),
				lte(vaultUpload.nextAttemptAt, now),
				lt(vaultUpload.leaseUntil, now),
				or(
					eq(vaultUpload.retired, 1),
					orphaned,
					inArray(vaultUpload.phase, [
						'creating',
						'uploading',
						'verifying',
						'finalizing',
						'cleanup'
					])
				)
			);
			const [candidate] = await tx
				.select()
				.from(vaultUpload)
				.where(eligible)
				.orderBy(asc(vaultUpload.nextAttemptAt), asc(vaultUpload.id))
				.limit(1);
			if (!candidate) return null;
			// Use the same account -> upload lock order as sync/reset. Recheck
			// references after taking the lock, so a concurrent metadata ACK or
			// finalization cannot become an orphan between selection and claim.
			await tx
				.select({ id: user[UserKeys.ID] })
				.from(user)
				.where(eq(user[UserKeys.ID], candidate.userId))
				.for('update');
			const [current] = await tx
				.select()
				.from(vaultUpload)
				.where(and(eq(vaultUpload.id, candidate.id), eligible))
				.for('update', { skipLocked: true });
			if (!current) return null;
			await tx
				.update(vaultUpload)
				.set({ retired: 1, phase: 'cleanup', leaseOwner: owner, leaseUntil: now + leaseMs })
				.where(eq(vaultUpload.id, candidate.id));
			return current;
		});
		if (!row) break;
		processed++;
		try {
			const result = await cloud.cleanup(row);
			const done = result.done;
			await db.transaction(async (tx) => {
				await tx
					.select({ id: user[UserKeys.ID] })
					.from(user)
					.where(eq(user[UserKeys.ID], row.userId))
					.for('update');
				const [owned] = await tx
					.select()
					.from(vaultUpload)
					.where(and(eq(vaultUpload.id, row.id), eq(vaultUpload.leaseOwner, owner)));
				if (!owned) return;
				if (done) {
					// A normal delete may have failed after tombstoning the file.
					// Release only this object's still-counted part, exactly once;
					// never debit a legacy/newer replacement of the same logical ID.
					const released = await tx
						.update(part)
						.set({
							[PartKeys.UPLOADED]: 0,
							[PartKeys.DELETED]: 1,
							[PartKeys.CIPHER]: null,
							[PartKeys.NONCE]: null,
							[PartKeys.JSON]: {},
							[PartKeys.DEVICE_UUID]: 'SERVER',
							[PartKeys.CLIENT_UPDATED_AT]: sql`GREATEST(${clock()}, ${part[PartKeys.CLIENT_UPDATED_AT]} + 1)`
						})
						.where(
							and(
								eq(part[PartKeys.USER_ID], row.userId),
								eq(part[PartKeys.UPLOADED], 1),
								eq(sql<string>`${part[PartKeys.JSON]} ->> 'managedUploadId'`, row.id)
							)
						)
						.returning({ size: part[PartKeys.PART_SIZE] });
					const bytes = released.reduce((sum, p) => sum + p.size, 0);
					if (bytes)
						await tx
							.update(storage)
							.set({
								[StorageKeys.USED_BYTES]: sql`GREATEST(0, ${storage[StorageKeys.USED_BYTES]} - ${bytes})`
							})
							.where(
								and(
									eq(storage[StorageKeys.USER_ID], row.userId),
									eq(storage[StorageKeys.ID], row.storageId)
								)
							);
				}
				await tx
					.update(vaultUpload)
					.set({
						phase: done ? 'deleted' : 'cleanup',
						cleanupCursor: done ? {} : result.cursor,
						uncertain: done || result.cursor.settled === true ? null : row.uncertain,
						leaseOwner: null,
						leaseUntil: 0,
						updatedAt: clock(),
						nextAttemptAt: clock() + 30_000,
						error:
							done || result.cursor.settled === true || !row.uncertain
								? null
								: row.uncertain === 'create'
									? 'upload_initiation_unknown'
									: 'upload_outcome_unknown',
						...(done
							? {
									credentials: {},
									uploadId: null,
									versionId: null,
									uncertain: null,
									deviceUuid: '',
									objectKey: '',
									partName: '',
									contentLength: 0,
									sha1: '',
									md5: ''
								}
							: {})
					})
					.where(and(eq(vaultUpload.id, row.id), eq(vaultUpload.leaseOwner, owner)));
			});
		} catch {
			await db
				.update(vaultUpload)
				.set({
					leaseOwner: null,
					leaseUntil: 0,
					phase: 'cleanup',
					attempts: row.attempts + 1,
					updatedAt: clock(),
					nextAttemptAt: clock() + Math.min(3_600_000, 30_000 * 2 ** Math.min(row.attempts, 7)),
					error: 'upload_cleanup_blocked'
				})
				.where(and(eq(vaultUpload.id, row.id), eq(vaultUpload.leaseOwner, owner)));
		}
	}
	return processed;
}
