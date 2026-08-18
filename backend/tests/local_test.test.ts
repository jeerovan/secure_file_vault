import assert from 'node:assert/strict';
import test from 'node:test';
import {
	getLocalTestIdentity,
	getLocalTestS3Credentials,
	tokensMatch
} from '../src/lib/server/localTest';

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

test('local S3 credentials are parsed without exposing provider defaults', () => {
	assert.deepEqual(
		getLocalTestS3Credentials({
			LOCAL_S3_ENDPOINT: 'https://objects.example.test/',
			LOCAL_S3_REGION: 'us-east-1',
			LOCAL_S3_BUCKET: 'test-bucket',
			LOCAL_S3_ACCESS_KEY_ID: 'access',
			LOCAL_S3_SECRET_ACCESS_KEY: 'secret',
			LOCAL_S3_FORCE_PATH_STYLE: 'false'
		}),
		{
			endpoint: 'https://objects.example.test',
			region: 'us-east-1',
			bucketName: 'test-bucket',
			appId: 'access',
			appKey: 'secret',
			forcePathStyle: false
		}
	);
});

test('local S3 credentials accept development-only private HTTP endpoints', () => {
	assert.equal(
		getLocalTestS3Credentials({
			LOCAL_S3_ENDPOINT: 'http://127.0.0.1:9000/',
			LOCAL_S3_REGION: 'us-east-1',
			LOCAL_S3_BUCKET: 'test-bucket',
			LOCAL_S3_ACCESS_KEY_ID: 'access',
			LOCAL_S3_SECRET_ACCESS_KEY: 'secret'
		}).endpoint,
		'http://127.0.0.1:9000'
	);
});

test('local S3 credentials still reject unsafe endpoint syntax', () => {
	const environment = {
		LOCAL_S3_REGION: 'us-east-1',
		LOCAL_S3_BUCKET: 'test-bucket',
		LOCAL_S3_ACCESS_KEY_ID: 'access',
		LOCAL_S3_SECRET_ACCESS_KEY: 'secret'
	};
	for (const endpoint of [
		'file:///tmp/bucket',
		'http://user:secret@localhost:9000',
		'http://localhost:9000?bucket=test'
	]) {
		assert.throws(() => getLocalTestS3Credentials({ ...environment, LOCAL_S3_ENDPOINT: endpoint }));
	}
});
