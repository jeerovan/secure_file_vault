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
