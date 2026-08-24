import { drizzle as drizzlePg } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

const localConnectionString = 'postgres://jeerovan@localhost:5432/fife';

function createDb(connectionString: string, maxConnections?: number) {
	const client = postgres(connectionString, { max: maxConnections });
	return drizzlePg(client, { schema });
}

export type Db = ReturnType<typeof createDb>;

let localDb: Db | undefined;

export function getDb(platform: Readonly<App.Platform> | undefined) {
	const hyperdrive = platform?.env?.HYPERDRIVE;
	if (hyperdrive) {
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
