// No .env/DATABASE_URL fallback: attach only to an explicitly selected local database.
import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import * as schema from '../src/lib/server/db/schema';
import { runCleanupTick } from '../src/lib/server/cleanupWorker';
import {
	LocalCleanupTargetError,
	resolveLocalCleanupTarget,
	startLocalCleanupSchedule
} from './localCleanup';

async function main() {
	const args = process.argv.slice(2);
	let once = false,
		controlFile: string | undefined;
	for (let index = 0; index < args.length; index++) {
		if (args[index] === '--once') once = true;
		else if (
			args[index] === '--control-file' &&
			args[index + 1] &&
			!args[index + 1].startsWith('--')
		)
			controlFile = args[++index];
		else
			throw new LocalCleanupTargetError(
				'Usage: npm run cleanup:local -- [--once] [--control-file PATH]'
			);
	}
	const target = await resolveLocalCleanupTarget({
		databaseUrl: controlFile ? undefined : process.env.FIFE_LOCAL_DATABASE_URL,
		controlFile
	});
	const client = postgres(target.databaseUrl, { max: 2, idle_timeout: 20, connect_timeout: 10 });
	const db = drizzle(client, { schema });
	const tick = async () => {
		await target.verify();
		await runCleanupTick(db);
	};
	const success = () => console.info('Cleanup cycle completed; heartbeat updated.');
	if (once) {
		try {
			await tick();
			success();
		} finally {
			await client.end({ timeout: 5 });
		}
		return;
	}
	let closing: Promise<void> | undefined;
	const close = (code = 0) => {
		if (closing) return closing;
		closing = (async () => {
			await schedule.stop();
			await client.end({ timeout: 5 });
			process.exitCode = code;
			console.info('Local cleanup worker stopped.');
		})();
		return closing;
	};
	const schedule = startLocalCleanupSchedule(tick, {
		onSuccess: success,
		onFailure(error) {
			if (error instanceof LocalCleanupTargetError) {
				console.error(error.message);
				void close(1);
			} else console.error('Cleanup cycle failed; heartbeat unchanged. Retrying in five minutes.');
		}
	});
	for (const signal of ['SIGINT', 'SIGTERM'] as const)
		process.once(signal, () => {
			void close();
		});
	console.info('Local cleanup worker started; runs immediately and every five minutes.');
	await schedule.firstRun;
}

try {
	await main();
} catch (error) {
	console.error(
		error instanceof LocalCleanupTargetError
			? error.message
			: 'Local cleanup worker failed; credentials withheld.'
	);
	process.exitCode = 1;
}
