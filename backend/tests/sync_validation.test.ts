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
