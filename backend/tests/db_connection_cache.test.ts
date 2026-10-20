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

test('explicit development database overrides emulated Hyperdrive only in development', () => {
	const previous = process.env.FIFE_LOCAL_DATABASE_URL;
	process.env.FIFE_LOCAL_DATABASE_URL = 'postgres://localhost:55432/isolated-provider-test';
	try {
		const platform = localHyperdrive();
		const development = getDb(platform, true);
		assert.equal(development.$client.options.database, 'isolated-provider-test');
		assert.equal(development, getDb(undefined, true));
		assert.equal(getDb(platform, false).$client.options.database, 'fife-release-test');
	} finally {
		if (previous === undefined) delete process.env.FIFE_LOCAL_DATABASE_URL;
		else process.env.FIFE_LOCAL_DATABASE_URL = previous;
	}
});
