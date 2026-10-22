import { readFile } from 'node:fs/promises';

export const CLEANUP_INTERVAL_MS = 5 * 60_000;
export const LOCAL_PROVIDER_CONTROL_FILE = '/tmp/fife_b2_s3_server.json';

export class LocalCleanupTargetError extends Error {}

export function validateLocalDatabaseUrl(value: string): string {
	try {
		const url = new URL(value);
		if (
			!['postgres:', 'postgresql:'].includes(url.protocol) ||
			!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
			Boolean(url.search || url.hash) ||
			!/^\/[a-zA-Z0-9_-]+$/.test(url.pathname) ||
			['/postgres', '/template0', '/template1'].includes(url.pathname)
		)
			throw new Error();
		return url.toString();
	} catch {
		throw new LocalCleanupTargetError(
			'Select a local PostgreSQL database with FIFE_LOCAL_DATABASE_URL.'
		);
	}
}

async function readControl(path: string) {
	try {
		const control = JSON.parse(await readFile(path, 'utf8'));
		const databaseUrl = validateLocalDatabaseUrl(control.databaseUrl);
		const url = new URL(databaseUrl);
		if (!url.port || url.port === '5432' || !/^\/fife_recovery_[a-f0-9]{32}$/.test(url.pathname))
			throw new LocalCleanupTargetError(
				'The local server control file must select a disposable database.'
			);
		if (
			!Number.isSafeInteger(control.processId) ||
			control.processId <= 1 ||
			!Number.isSafeInteger(control.port) ||
			control.port < 1 ||
			control.port > 65535 ||
			typeof control.remoteId !== 'string' ||
			!/^fife-provider-local-[a-f0-9-]{36}$/.test(control.remoteId)
		)
			throw new Error();
		process.kill(control.processId, 0);
		return {
			databaseUrl,
			processId: control.processId,
			port: control.port,
			remoteId: control.remoteId
		};
	} catch (error) {
		if (error instanceof LocalCleanupTargetError) throw error;
		throw new LocalCleanupTargetError(
			'Start the local server first; its control file is missing, invalid or stale.'
		);
	}
}

export async function resolveLocalCleanupTarget(
	options: { databaseUrl?: string; controlFile?: string } = {}
) {
	if (options.databaseUrl) {
		const databaseUrl = validateLocalDatabaseUrl(options.databaseUrl);
		return { databaseUrl, verify: async () => {} };
	}
	const path = options.controlFile ?? LOCAL_PROVIDER_CONTROL_FILE;
	const control = await readControl(path);
	return {
		databaseUrl: control.databaseUrl,
		async verify() {
			if (JSON.stringify(await readControl(path)) !== JSON.stringify(control))
				throw new LocalCleanupTargetError(
					'The local server changed; restart the cleanup worker to attach again.'
				);
		}
	};
}

/** Immediate first cycle, fixed production cadence, and one in-flight cycle at most. */
export function startLocalCleanupSchedule(
	tick: () => Promise<void>,
	options: { onSuccess?: () => void; onFailure?: (error: unknown) => void } = {}
) {
	let stopping = false;
	let inFlight: Promise<void> | undefined;
	const run = () => {
		if (stopping || inFlight) return Promise.resolve();
		inFlight = (async () => {
			try {
				await tick();
				options.onSuccess?.();
			} catch (error) {
				options.onFailure?.(error);
			}
		})();
		return inFlight.finally(() => {
			inFlight = undefined;
		});
	};
	const firstRun = run();
	const timer = setInterval(() => {
		void run();
	}, CLEANUP_INTERVAL_MS);
	return {
		firstRun,
		async stop() {
			stopping = true;
			clearInterval(timer);
			await inFlight;
		}
	};
}
