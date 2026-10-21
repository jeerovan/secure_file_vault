import type { ExecutionContext, ScheduledController } from '@cloudflare/workers-types';
import app from './.svelte-kit/cloudflare/_worker.js';
import { getDb } from './src/lib/server/db';
import { recoveryWorkerState } from './src/lib/server/db/schema';
import { drainRecoveryCleanup } from './src/lib/server/recoveryCleanup';
import { ProviderRecoveryStorage } from './src/lib/server/recoveryStorage';
import { drainManagedUploads } from './src/lib/server/managedUploadCleanup';
import { ProviderManagedUploadStorage } from './src/lib/server/managedUploadStorage';

type Env = App.Platform['env'];

export default {
	fetch(request: Request, env: Env, context: ExecutionContext) {
		return app.fetch(request, env, context);
	},
	async scheduled(_controller: ScheduledController, env: Env) {
		const db = getDb({ env }, false);
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
		} finally {
			await db.$client.end({ timeout: 5 });
		}
	}
};
