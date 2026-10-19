import assert from 'node:assert/strict';
import test from 'node:test';
import { getLocalTestIdentity, tokensMatch } from '../src/lib/server/localTest';

test('local test identity is disabled unless explicitly enabled', () => {
	assert.equal(getLocalTestIdentity({}), null);
	assert.equal(
		getLocalTestIdentity({
			LOCAL_TEST_AUTH_ENABLED: 'false',
			LOCAL_TEST_AUTH_TOKEN: 'token',
			LOCAL_TEST_USER_ID: 'user',
			LOCAL_TEST_EMAIL: 'local@example.test'
		}),
		null
	);
});

test('local test identity requires fixed server-side values', () => {
	assert.deepEqual(
		getLocalTestIdentity({
			LOCAL_TEST_AUTH_ENABLED: 'true',
			LOCAL_TEST_AUTH_TOKEN: 'token',
			LOCAL_TEST_USER_ID: 'local-user',
			LOCAL_TEST_EMAIL: 'local@example.test'
		}),
		{
			token: 'token',
			remoteAuthId: 'local-user',
			email: 'local@example.test'
		}
	);
	assert.throws(
		() => getLocalTestIdentity({ LOCAL_TEST_AUTH_ENABLED: 'true' }),
		/LOCAL_TEST_AUTH_TOKEN/
	);
});

test('local authentication tokens are compared by digest', async () => {
	assert.equal(await tokensMatch('same-token', 'same-token'), true);
	assert.equal(await tokensMatch('wrong-token', 'same-token'), false);
});

test('each missing or blank identity value rejects the local configuration', () => {
	const complete = {
		LOCAL_TEST_AUTH_ENABLED: 'true',
		LOCAL_TEST_AUTH_TOKEN: 'release-token',
		LOCAL_TEST_USER_ID: 'release-user',
		LOCAL_TEST_EMAIL: 'local@example.test'
	};
	for (const key of ['LOCAL_TEST_AUTH_TOKEN', 'LOCAL_TEST_USER_ID', 'LOCAL_TEST_EMAIL']) {
		for (const value of [undefined, '', '  ']) {
			assert.throws(() => getLocalTestIdentity({ ...complete, [key]: value }), new RegExp(key));
		}
	}
});

test('configured identity is trimmed and activation requires the exact true flag', () => {
	const config = {
		LOCAL_TEST_AUTH_ENABLED: 'true',
		LOCAL_TEST_AUTH_TOKEN: ' token ',
		LOCAL_TEST_USER_ID: ' user ',
		LOCAL_TEST_EMAIL: ' local@example.test '
	};
	assert.deepEqual(getLocalTestIdentity(config), {
		token: 'token',
		remoteAuthId: 'user',
		email: 'local@example.test'
	});
	for (const flag of ['TRUE', '1', 'yes', '', ' true ']) {
		assert.equal(getLocalTestIdentity({ ...config, LOCAL_TEST_AUTH_ENABLED: flag }), null);
	}
});

test('missing, prefix, suffix, case, and unicode token differences are rejected', async () => {
	const expected = 'release-token-\u00e9';
	for (const candidate of [
		'',
		'release-token-',
		expected + 'x',
		expected.toUpperCase(),
		'release-token-e\u0301'
	]) {
		assert.equal(await tokensMatch(candidate, expected), false);
	}
	assert.equal(await tokensMatch(expected, expected), true);
});
