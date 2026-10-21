import assert from 'node:assert/strict';
import test from 'node:test';
import { storedPartObjectKey } from '../src/lib/server/partObject';
import { isRetiredVaultObject } from '../src/lib/server/recoveryStorage';

test('managed object locations preserve logical IDs and the authenticated account/generation', () => {
	const name = `${'a'.repeat(43)}_1`,
		prefix = 'account/vaults/generation/';
	const key = `${prefix}${name}~${crypto.randomUUID()}`;
	assert.equal(storedPartObjectKey(prefix, name, {}), `${prefix}${name}`);
	assert.equal(storedPartObjectKey(prefix, name, { managedObjectKey: key }), key);
	assert.equal(storedPartObjectKey(prefix, name, JSON.stringify({ managedObjectKey: key })), key);
	assert.equal(isRetiredVaultObject(prefix, key), true);
	for (const location of [
		key.replace('account/', 'other/'),
		key.replace('generation/', 'old/'),
		key.replace('_1~', '_2~'),
		`${prefix}${name}~not-a-uuid`,
		`${key}/extra`,
		7,
		null
	]) {
		assert.throws(
			() => storedPartObjectKey(prefix, name, { managedObjectKey: location }),
			/invalid_part_location/
		);
	}
	assert.equal(isRetiredVaultObject('account/vaults/other/', key), false);
});
