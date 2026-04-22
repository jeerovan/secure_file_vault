import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

export function getDb(platform: Readonly<App.Platform> | undefined) {
	// 1. Fallback for local development if running outside Wrangler
	if (!platform?.env?.HYPERDRIVE) {
		throw new Error('Hyperdrive binding not found. Are you running via Wrangler?');
	}

	// 2. Hyperdrive provides a localized connection string to the Cloudflare proxy
	const connectionString = platform.env.HYPERDRIVE.connectionString;

	// 3. Connect using standard Postgres-js over TCP
	const client = postgres(connectionString);

	// 4. Wrap with Drizzle
	return drizzle(client, { schema });
}

// 1. Extract the Database type based on the return type of your getDb function
export type Db = ReturnType<typeof getDb>;

// 2. Extract the Transaction type directly from the first parameter of the transaction callback
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
