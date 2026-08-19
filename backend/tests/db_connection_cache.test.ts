import assert from 'node:assert/strict';
import test from 'node:test';

import { getDb } from '../src/lib/server/db';

test('reuses the local PostgreSQL client across requests', () => {
	assert.equal(getDb(undefined), getDb(undefined));
});
