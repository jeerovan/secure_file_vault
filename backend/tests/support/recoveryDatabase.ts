import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { generateDrizzleJson, generateMigration } from 'drizzle-kit/api';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from '../../src/lib/server/db/schema';

export const recoveryTestUrl = process.env.FIFE_RECOVERY_TEST_DATABASE_URL;

export async function createRecoveryDatabase(options: { legacy?: boolean } = {}) {
	assert.ok(recoveryTestUrl, 'Set FIFE_RECOVERY_TEST_DATABASE_URL to an isolated test cluster');
	const url = new URL(recoveryTestUrl);
	assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname));
	assert.ok(url.port && url.port !== '5432', 'Use a dedicated temporary PostgreSQL server');
	assert.equal(url.pathname, '/postgres');
	const name = `fife_recovery_${randomUUID().replaceAll('-', '')}`;
	const admin = postgres(url.toString(), { max: 1 });
	await admin.unsafe(`CREATE DATABASE "${name}"`);
	url.pathname = `/${name}`;
	const client = postgres(url.toString(), { max: 4 });
	try {
		const models = { ...schema };
		if (options.legacy) {
			for (const key of [
				'vaultState',
				'vaultUploadCapability',
				'vaultUpload',
				'recoveryReset',
				'recoveryCleanupTarget',
				'recoveryWorkerState'
			] as const)
				delete (models as Partial<typeof schema>)[key];
		}
		const statements = await generateMigration(
			generateDrizzleJson({}),
			generateDrizzleJson(models)
		);
		for (const statement of statements) await client.unsafe(statement);
	} catch (error) {
		await client.end();
		await admin.unsafe(`DROP DATABASE "${name}" WITH (FORCE)`);
		await admin.end();
		throw error;
	}
	return {
		url: url.toString(),
		db: drizzle(client, { schema }),
		async close(options: { preserve?: boolean } = {}) {
			await client.end();
			if (!options.preserve) await admin.unsafe(`DROP DATABASE "${name}" WITH (FORCE)`);
			await admin.end();
		}
	};
}
