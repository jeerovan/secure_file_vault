import assert from 'node:assert/strict';
import test from 'node:test';

import { getDb } from '../src/lib/server/db';

test('reuses the local PostgreSQL client', () => {
	assert.equal(getDb(undefined), getDb(undefined));
});

test('creates a request-scoped PostgreSQL client for Hyperdrive', () => {
	const platform = {
		env: {
			HYPERDRIVE: { connectionString: 'postgres://hyperdrive.example/fife' },
			FIFE_AUTH_CACHE: {}
		}
	} as unknown as App.Platform;

	assert.notEqual(getDb(platform), getDb(platform));
});
