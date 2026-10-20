import { drizzle as drizzlePg } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

const localConnectionString = 'postgres://jeerovan@localhost:5432/fife';

function createDb(connectionString: string, maxConnections?: number) {
	const client = postgres(connectionString, { max: maxConnections, idle_timeout: 20 });
	return drizzlePg(client, { schema });
}

export type Db = ReturnType<typeof createDb>;

let localDb: Db | undefined;
const developmentHyperdriveDbs = new Map<string, Db>();

export function getDb(
	platform: Readonly<App.Platform> | undefined,
	development = import.meta.env?.DEV ?? false
) {
	// An explicit local harness must also override Cloudflare's emulated binding.
	const developmentUrl = development
		? (globalThis as { process?: { env?: { FIFE_LOCAL_DATABASE_URL?: string } } }).process?.env
				?.FIFE_LOCAL_DATABASE_URL
		: undefined;
	if (developmentUrl) {
		let db = developmentHyperdriveDbs.get(developmentUrl);
		if (!db) {
			db = createDb(developmentUrl, 5);
			developmentHyperdriveDbs.set(developmentUrl, db);
		}
		return db;
	}
	const hyperdrive = platform?.env?.HYPERDRIVE;
	if (hyperdrive) {
		// Vite keeps serving requests in one process; a fresh pool per request
		// exhausts local PostgreSQL even though those connections are idle.
		if (development) {
			let db = developmentHyperdriveDbs.get(hyperdrive.connectionString);
			if (!db) {
				db = createDb(hyperdrive.connectionString, 5);
				developmentHyperdriveDbs.set(hyperdrive.connectionString, db);
			}
			return db;
		}
		// Workers cannot safely reuse driver I/O objects across request contexts.
		// Hyperdrive owns the underlying connection pool, so a request-scoped client is cheap.
		return createDb(hyperdrive.connectionString, 5);
	}

	if (!localDb) {
		console.info('HYPERDRIVE not found; using local PostgreSQL database');
		localDb = createDb(localConnectionString);
	}

	return localDb;
}

export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
