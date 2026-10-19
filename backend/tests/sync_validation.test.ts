import assert from 'node:assert/strict';
import test from 'node:test';

import { assertSyncTable, parseSyncChangeData } from '../src/lib/server/syncValidation';

test('sync validation accepts supported tables and object payloads', () => {
	assert.doesNotThrow(() => assertSyncTable('parts'));
	assert.deepEqual(parseSyncChangeData('{"uploaded":1}'), { uploaded: 1 });
	assert.deepEqual(parseSyncChangeData({ uploaded: 1 }), { uploaded: 1 });
});

test('sync validation rejects unacknowledgeable changes', () => {
	assert.throws(() => assertSyncTable('unknown'));
	assert.throws(() => parseSyncChangeData('not-json'));
	assert.throws(() => parseSyncChangeData(null));
	assert.throws(() => parseSyncChangeData([]));
});

test('all sync entity types accept JSON objects without changing their data', () => {
	for (const table of ['files', 'items', 'parts'])
		assert.doesNotThrow(() => assertSyncTable(table));
	const row = { id: 'unicode-合同', uploaded: 0, deleted: 1, data: { sha1: 'hash' } };
	assert.deepEqual(parseSyncChangeData(JSON.stringify(row)), row);
});

test('unsupported table values and JSON scalar bodies cannot be acknowledged', () => {
	for (const table of ['', null, undefined, 42, {}, [], 'profiles', 'FILES']) {
		assert.throws(() => assertSyncTable(table));
	}
	for (const body of ['null', '[]', 'true', 'false', '42', '"text"', '', '{']) {
		assert.throws(() => parseSyncChangeData(body));
	}
});
