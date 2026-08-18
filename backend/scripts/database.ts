import { neon } from '@neondatabase/serverless';
import { drizzle as drizzleNeon, type NeonHttpDatabase } from 'drizzle-orm/neon-http';
import { drizzle as drizzlePostgres, type PostgresJsDatabase } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from '../src/lib/server/db/schema';

export type DatabaseDriver = 'postgres' | 'neon';
export type ScriptDatabase = PostgresJsDatabase<typeof schema> | NeonHttpDatabase<typeof schema>;

const localDatabaseUrl = 'postgres://jeerovan@localhost:5432/fife';

export function isDatabaseDriver(value: string | undefined): value is DatabaseDriver {
	return value === 'postgres' || value === 'neon';
}

export function resolveDatabaseDriver(
	requestedDriver: string | undefined,
	databaseUrl: string | undefined = process.env.DATABASE_URL
): DatabaseDriver {
	if (requestedDriver) {
		if (!isDatabaseDriver(requestedDriver)) {
			throw new Error(
				`Unsupported database driver "${requestedDriver}". Use "postgres" or "neon".`
			);
		}
		return requestedDriver;
	}

	if (!databaseUrl) return 'postgres';
	try {
		return new URL(databaseUrl).hostname.endsWith('.neon.tech') ? 'neon' : 'postgres';
	} catch {
		throw new Error('DATABASE_URL is not a valid PostgreSQL URL');
	}
}

export async function withScriptDatabase<T>(
	driver: DatabaseDriver,
	callback: (db: ScriptDatabase) => Promise<T>
): Promise<T> {
	const configuredUrl = process.env.DATABASE_URL;
	if (driver === 'neon') {
		if (!configuredUrl) throw new Error('DATABASE_URL must be set when using the Neon driver');
		const db = drizzleNeon(neon(configuredUrl), { schema });
		return callback(db);
	}

	const client = postgres(configuredUrl ?? localDatabaseUrl);
	try {
		return await callback(drizzlePostgres(client, { schema }));
	} finally {
		await client.end();
	}
}
