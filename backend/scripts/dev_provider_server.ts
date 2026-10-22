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
const database = await createRecoveryDatabase();
// Ignore the production migration DATABASE_URL loaded from backend/.env.
process.env.DATABASE_URL = database.url;
process.env.FIFE_LOCAL_DATABASE_URL = database.url;
// This database is created here, and every exposed issuer records its expiry.
// There are no capabilities from a deployment predating that accounting.
// Use the same rollout policy as production with a fully drained history.
process.env.RECOVERY_UPLOAD_ACCOUNTING_SINCE = '1970-01-01T00:00:00.000Z';
const remoteId = `fife-provider-local-${randomUUID()}`;
process.env.LOCAL_TEST_USER_ID = remoteId;
const vite = await createServer({
	root: process.cwd(),
	logLevel: 'warn',
	server: { host: '0.0.0.0', port: 5173, strictPort: true }
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
	if (wroteControl) await unlink('/tmp/fife_b2_s3_server.json');
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
		'/tmp/fife_b2_s3_server.json',
		JSON.stringify({ remoteId, databaseUrl: database.url, port: 5173, processId: process.pid }),
		{ mode: 0o600 }
	);
	wroteControl = true;
	console.info(
		'Local provider server ready on 0.0.0.0:5173; disposable SQL and isolated test identity enabled'
	);
} catch {
	await close();
	throw new Error('Local provider server startup failed; credentials withheld');
}
