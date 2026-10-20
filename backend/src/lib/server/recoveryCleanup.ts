import { and, asc, eq, inArray, lt, lte } from 'drizzle-orm';
import type { Db } from './db';
import { recoveryCleanupTarget as target, recoveryReset, vaultState, user } from './db/schema';
import { UserKeys } from './db/keys';
import { ensureDefaultFiFeStorage } from './defaultStorage';
import { RecoveryFault } from './recoverySession';
import type { RecoveryStorage } from './recoveryStorage';

async function refreshOperation(db: Db, operationId: string, now: number) {
	await db.transaction(async (tx) => {
		const [initial] = await tx
			.select()
			.from(recoveryReset)
			.where(eq(recoveryReset.id, operationId));
		if (!initial || initial.phase !== 'cleanup_pending') return;
		await tx
			.select({ id: user[UserKeys.ID] })
			.from(user)
			.where(eq(user[UserKeys.ID], initial.userId))
			.for('update');
		const [operation] = await tx
			.select()
			.from(recoveryReset)
			.where(eq(recoveryReset.id, operationId))
			.for('update');
		if (operation.phase !== 'cleanup_pending') return;
		const targets = await tx.select().from(target).where(eq(target.operationId, operationId));
		const error = targets.find((row) => row.error)?.error ?? null;
		if (!targets.length || targets.some((row) => row.phase !== 'done')) {
			await tx
				.update(recoveryReset)
				.set({ error: targets.length ? error : 'cleanup_manifest_missing' })
				.where(eq(recoveryReset.id, operationId));
			return;
		}
		if (operation.notBefore === null || now < operation.notBefore) return;
		const [state] = await tx
			.select()
			.from(vaultState)
			.where(eq(vaultState.userId, operation.userId));
		if (state?.generation !== operation.nextGeneration) throw new RecoveryFault('vault_changed');
		await ensureDefaultFiFeStorage(tx, operation.userId);
		await tx.update(vaultState).set({ ready: 1 }).where(eq(vaultState.userId, operation.userId));
		await tx
			.update(recoveryReset)
			.set({ phase: 'ready', error: null })
			.where(eq(recoveryReset.id, operationId));
		// Credentials/cursors are temporary private deletion material, not history.
		await tx.delete(target).where(eq(target.operationId, operationId));
	});
}

/** Called by Cron; no provider HTTP occurs while a SQL transaction is open. */
export async function drainRecoveryCleanup(
	db: Db,
	cloud: RecoveryStorage,
	options: { now?: () => number; limit?: number } = {}
) {
	const clock = options.now ?? Date.now;
	let processed = 0;
	for (let i = 0; i < (options.limit ?? 2); i++) {
		const now = clock();
		const owner = crypto.randomUUID();
		const claimed = await db.transaction(async (tx) => {
			const [candidate] = await tx
				.select({ target, notBefore: recoveryReset.notBefore })
				.from(target)
				.innerJoin(recoveryReset, eq(recoveryReset.id, target.operationId))
				.where(
					and(
						eq(recoveryReset.phase, 'cleanup_pending'),
						inArray(target.phase, ['pending', 'waiting']),
						lte(target.nextAttemptAt, now),
						lt(target.leaseUntil, now)
					)
				)
				.orderBy(asc(target.nextAttemptAt), asc(target.id))
				.limit(1)
				.for('update', { of: target, skipLocked: true });
			if (!candidate) return null;
			await tx
				.update(target)
				.set({ leaseOwner: owner, leaseUntil: now + 5 * 60_000 })
				.where(eq(target.id, candidate.target.id));
			return candidate;
		});
		if (!claimed) break;
		processed++;
		const row = claimed.target;
		try {
			// A pass started before capability expiry must never count as the
			// final sweep, even if its last page finishes after that deadline.
			const finalSweep =
				row.phase === 'waiting' ||
				row.cursor.finalSweep === true ||
				(Object.keys(row.cursor).length === 0 && now >= (claimed.notBefore ?? Infinity));
			const result = await cloud.step(row, row.cursor);
			await db
				.update(target)
				.set({
					cursor: result.done ? {} : { ...result.cursor, finalSweep },
					phase: result.done ? (finalSweep ? 'done' : 'waiting') : 'pending',
					nextAttemptAt: result.done && !finalSweep ? claimed.notBefore! : clock() + 1,
					leaseOwner: null,
					leaseUntil: 0,
					attempts: 0,
					error: null
				})
				.where(and(eq(target.id, row.id), eq(target.leaseOwner, owner)));
		} catch (error) {
			const attempts = row.attempts + 1;
			await db
				.update(target)
				.set({
					leaseOwner: null,
					leaseUntil: 0,
					attempts,
					error: error instanceof RecoveryFault ? error.code : 'storage_cleanup_blocked',
					nextAttemptAt: clock() + Math.min(60 * 60_000, 30_000 * 2 ** Math.min(attempts, 7))
				})
				.where(and(eq(target.id, row.id), eq(target.leaseOwner, owner)));
		}
		await refreshOperation(db, row.operationId, clock());
	}
	// Recover a crash after the last target checkpoint but before finalization.
	const unfinished = await db
		.select({ id: recoveryReset.id })
		.from(recoveryReset)
		.where(eq(recoveryReset.phase, 'cleanup_pending'))
		.limit(10);
	for (const operation of unfinished) await refreshOperation(db, operation.id, clock());
	return processed;
}
