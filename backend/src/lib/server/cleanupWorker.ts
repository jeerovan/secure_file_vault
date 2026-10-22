import type { Db } from './db';
import { recoveryWorkerState } from './db/schema';
import { drainManagedUploads } from './managedUploadCleanup';
import { ProviderManagedUploadStorage } from './managedUploadStorage';
import { drainRecoveryCleanup } from './recoveryCleanup';
import { ProviderRecoveryStorage } from './recoveryStorage';

/** Shared by Cloudflare Cron and the local scheduler; the caller owns the SQL client. */
export async function runCleanupTick(db: Db) {
	try {
		// Pending deletion continues even when new reset entry is disabled.
		await drainManagedUploads(db, new ProviderManagedUploadStorage(), { limit: 2 });
		await drainRecoveryCleanup(db, new ProviderRecoveryStorage(), { limit: 2 });
		const lastRunAt = Date.now();
		await db
			.insert(recoveryWorkerState)
			.values({ id: 'cleanup', lastRunAt })
			.onConflictDoUpdate({ target: recoveryWorkerState.id, set: { lastRunAt } });
	} catch {
		// Provider exceptions can contain credentials or signed request URLs.
		throw new Error('Recovery cleanup tick failed');
	}
}
