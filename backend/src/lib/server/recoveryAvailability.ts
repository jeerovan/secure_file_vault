import { eq } from 'drizzle-orm';
import type { Db, Tx } from './db';
import { recoveryWorkerState } from './db/schema';

export async function recoveryAvailable(
	db: Db | Tx,
	flags: Record<string, string | undefined>,
	email: string | undefined,
	now = Date.now()
) {
	if (flags.RECOVERY_RESET_ENABLED !== 'true' || flags.RECOVERY_WORKER_READY !== 'true')
		return false;
	const rollout = (flags.RECOVERY_RESET_EMAILS ?? '')
		.split(',')
		.map((value) => value.trim().toLowerCase())
		.filter(Boolean);
	if (!email || (!rollout.includes('*') && !rollout.includes(email.toLowerCase()))) return false;
	const [worker] = await db
		.select()
		.from(recoveryWorkerState)
		.where(eq(recoveryWorkerState.id, 'cleanup'))
		.limit(1);
	return !!worker && worker.lastRunAt <= now && now - worker.lastRunAt < 15 * 60_000;
}
