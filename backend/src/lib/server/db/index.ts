import { drizzle as drizzlePg } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

const localConnectionString = 'postgres://jeerovan@localhost:5432/fife';

export function getDb(platform: Readonly<App.Platform> | undefined) {
	const hyperdrive = platform?.env?.HYPERDRIVE;
	const connectionString = hyperdrive?.connectionString ?? localConnectionString;

	if (!hyperdrive) {
		console.info('HYPERDRIVE not found; using local PostgreSQL database');
	}

	// Connect using standard Postgres-js over TCP
	const client = postgres(connectionString);

	// Wrap with Drizzle
	return drizzlePg(client, { schema });
}

// 1. Extract the Database type based on the return type of your getDb function
export type Db = ReturnType<typeof getDb>;

// 2. Extract the Transaction type directly from the first parameter of the transaction callback
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
