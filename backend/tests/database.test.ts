import assert from 'node:assert/strict';
import test from 'node:test';
import { resolveDatabaseDriver } from '../scripts/database';

test('uses an explicitly requested database driver', () => {
	assert.equal(resolveDatabaseDriver('postgres', 'postgres://example.com/fife'), 'postgres');
	assert.equal(resolveDatabaseDriver('neon', 'postgres://localhost/fife'), 'neon');
});

test('infers the database driver from DATABASE_URL', () => {
	assert.equal(resolveDatabaseDriver(undefined, 'postgres://localhost/fife'), 'postgres');
	assert.equal(
		resolveDatabaseDriver(undefined, 'postgres://user@project.eu.neon.tech/fife'),
		'neon'
	);
	assert.equal(resolveDatabaseDriver(undefined, undefined), 'postgres');
});

test('rejects unsupported database drivers', () => {
	assert.throws(() => resolveDatabaseDriver('sqlite'), /Unsupported database driver/);
});
