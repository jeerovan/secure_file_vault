import type { ExecutionContext, ScheduledController } from '@cloudflare/workers-types';
import app from './.svelte-kit/cloudflare/_worker.js';
import { getDb } from './src/lib/server/db';
import { runCleanupTick } from './src/lib/server/cleanupWorker';

type Env = App.Platform['env'];

export default {
	fetch(request: Request, env: Env, context: ExecutionContext) {
		return app.fetch(request, env, context);
	},
	async scheduled(_controller: ScheduledController, env: Env) {
		const db = getDb({ env }, false);
		try {
			await runCleanupTick(db);
		} finally {
			await db.$client.end({ timeout: 5 });
		}
	}
};
