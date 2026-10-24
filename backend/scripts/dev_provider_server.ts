// Explicit development harness: real provider I/O, disposable loopback SQL only.
import { writeFile, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { createServer } from 'vite';
import { createRecoveryDatabase } from '../tests/support/recoveryDatabase';
import { getLocalTestIdentity } from '../src/lib/server/localTest';
import { backblazeCredentialsFromAuthorization } from '../src/lib/server/backblazeCredentials';
import * as tables from '../src/lib/server/db/schema';
import {
	UserKeys as U,
	ProviderKeys as P,
	CredentialKeys as C,
	StorageProvider
} from '../src/lib/server/db/keys';

const identity = getLocalTestIdentity(process.env);
if (!identity) throw new Error('Explicit local-test authentication must be enabled');
const port = Number(process.env.FIFE_PROVIDER_TEST_PORT ?? '5173');
if (!Number.isInteger(port) || port < 1024 || port > 65535)
	throw new Error('FIFE_PROVIDER_TEST_PORT must be a non-privileged TCP port');
const controlFile = process.env.FIFE_PROVIDER_TEST_CONTROL_FILE ?? '/tmp/fife_b2_s3_server.json';
const managedUploads = process.env.FIFE_PROVIDER_TEST_MANAGED_UPLOADS_ENABLED ?? 'true';
if (!['true', 'false'].includes(managedUploads))
	throw new Error('FIFE_PROVIDER_TEST_MANAGED_UPLOADS_ENABLED must be true or false');
const database = await createRecoveryDatabase();
// Ignore the production migration DATABASE_URL loaded from backend/.env.
process.env.DATABASE_URL = database.url;
process.env.FIFE_LOCAL_DATABASE_URL = database.url;
// Default to the new protocol; explicitly opt out to verify rollout fallback.
process.env.MANAGED_UPLOADS_ENABLED = managedUploads;
// This database is created here, and every exposed issuer records its expiry.
// There are no capabilities from a deployment predating that accounting.
// Use the same rollout policy as production with a fully drained history.
process.env.RECOVERY_UPLOAD_ACCOUNTING_SINCE = '1970-01-01T00:00:00.000Z';
const remoteId = `fife-provider-local-${randomUUID()}`;
process.env.LOCAL_TEST_USER_ID = remoteId;
const vite = await createServer({
	root: process.cwd(),
	logLevel: 'warn',
	server: { host: '0.0.0.0', port, strictPort: true }
});
let closing = false;
let wroteControl = false;
const close = async () => {
	if (closing) return;
	closing = true;
	const module = await vite.ssrLoadModule('/src/lib/server/db/index.ts').catch(() => null);
	await module?.getDb(undefined, true).$client.end();
	await vite.close();
	await database.close();
	if (wroteControl) await unlink(controlFile);
};
for (const signal of ['SIGTERM', 'SIGINT'] as const)
	process.on(signal, () => {
		void close().finally(() => process.exit());
	});
try {
	for (const [title, id] of Object.entries(StorageProvider)) {
		await database.db
			.insert(tables.provider)
			.values({ [P.ID]: id, [P.TITLE]: title, [P.FREE_BYTES]: 10 * 1024 ** 3, [P.PRIORITY]: id });
	}
	const response = await fetch('https://api.backblazeb2.com/b2api/v4/b2_authorize_account', {
		headers: {
			authorization: `Basic ${btoa(`${process.env.B2_KEY_ID}:${process.env.B2_APPLICATION_KEY}`)}`
		},
		redirect: 'manual',
		signal: AbortSignal.timeout(15_000)
	});
	if (!response.ok) throw new Error('Backblaze fixture credential verification failed');
	const credentials = backblazeCredentialsFromAuthorization(
		process.env.B2_KEY_ID!,
		process.env.B2_APPLICATION_KEY!,
		await response.json()
	);
	const [service] = await database.db
		.insert(tables.user)
		.values({
			[U.REMOTE_AUTH_ID]: 'fife',
			[U.EMAIL]: 'service@example.test',
			[U.CIPHER]: 'local-fixture',
			[U.NONCE]: 'local-fixture'
		})
		.returning();
	await database.db.insert(tables.credential).values({
		[C.USER_ID]: service[U.ID],
		[C.PROVIDER_ID]: StorageProvider.FIFE,
		[C.CREDENTIALS]: credentials
	});
	await vite.listen();
	await writeFile(
		controlFile,
		JSON.stringify({ remoteId, databaseUrl: database.url, port, processId: process.pid }),
		{ mode: 0o600 }
	);
	wroteControl = true;
	console.info(
		`Local provider server ready on 0.0.0.0:${port}; disposable SQL and isolated test identity enabled`
	);
} catch {
	await close();
	throw new Error('Local provider server startup failed; credentials withheld');
}
