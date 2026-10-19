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

function localHyperdrive(connectionString = 'postgres://localhost/fife-release-test') {
	return {
		env: { HYPERDRIVE: { connectionString }, FIFE_AUTH_CACHE: {} }
	} as unknown as App.Platform;
}

test('development Hyperdrive requests reuse a bounded connection pool', () => {
	assert.equal(getDb(localHyperdrive(), true), getDb(localHyperdrive(), true));
});

test('development databases with different connection strings stay isolated', () => {
	assert.notEqual(
		getDb(localHyperdrive('postgres://localhost/first-release-test'), true),
		getDb(localHyperdrive('postgres://localhost/second-release-test'), true)
	);
});

test('production Hyperdrive clients stay request scoped', () => {
	const platform = localHyperdrive();
	assert.notEqual(getDb(platform, false), getDb(platform, false));
});
