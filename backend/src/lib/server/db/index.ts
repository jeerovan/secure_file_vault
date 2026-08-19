import { drizzle as drizzlePg } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

const localConnectionString = 'postgres://jeerovan@localhost:5432/fife';

function createDb(connectionString: string) {
	const client = postgres(connectionString);
	return drizzlePg(client, { schema });
}

export type Db = ReturnType<typeof createDb>;

let cachedConnectionString: string | undefined;
let cachedDb: Db | undefined;

export function getDb(platform: Readonly<App.Platform> | undefined) {
	const hyperdrive = platform?.env?.HYPERDRIVE;
	const connectionString = hyperdrive?.connectionString ?? localConnectionString;

	if (cachedDb && cachedConnectionString === connectionString) {
		return cachedDb;
	}

	if (!hyperdrive) {
		console.info('HYPERDRIVE not found; using local PostgreSQL database');
	}

	cachedConnectionString = connectionString;
	cachedDb = createDb(connectionString);
	return cachedDb;
}

export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
