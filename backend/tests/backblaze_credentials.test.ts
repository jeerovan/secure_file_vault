import assert from 'node:assert/strict';
import test from 'node:test';
import {
	backblazeCredentialsFromAuthorization as discover,
	BackblazeCredentialError
} from '../src/lib/server/backblazeCredentials';
import { ErrorCode } from '../src/lib/server/db/keys';

const capabilities = [
	'deleteFiles',
	'writeBuckets',
	'readBuckets',
	'readFiles',
	'shareFiles',
	'writeFiles',
	'listFiles'
];
function authorization() {
	return {
		accountId: 'fixture-account',
		authorizationToken: 'fixture-token',
		applicationKeyExpirationTimestamp: null,
		apiInfo: {
			storageApi: {
				apiUrl: 'https://api004.backblazeb2.com',
				downloadUrl: 'https://f004.backblazeb2.com',
				s3ApiUrl: 'https://s3.us-west-004.backblazeb2.com',
				allowed: {
					buckets: [{ id: 'fixture-bucket-id', name: 'fixture-bucket' }],
					capabilities: [...capabilities],
					namePrefix: null
				}
			}
		}
	};
}
const fault = (code: number) => (error: unknown) =>
	error instanceof BackblazeCredentialError && error.code === code;

test('B2 discovers S3 settings using only the submitted app ID, key and authorization response', () => {
	const response = authorization();
	const data = discover('fixture-id', 'fixture-secret', response);
	assert.deepEqual(data, {
		appId: 'fixture-id',
		appKey: 'fixture-secret',
		accountId: 'fixture-account',
		authorizationToken: 'fixture-token',
		bucketId: 'fixture-bucket-id',
		bucketName: 'fixture-bucket',
		apiUrl: 'https://api004.backblazeb2.com',
		downloadUrl: 'https://f004.backblazeb2.com',
		s3ApiUrl: 'https://s3.us-west-004.backblazeb2.com',
		endpoint: 'https://s3.us-west-004.backblazeb2.com',
		region: 'us-west-004',
		forcePathStyle: true,
		capabilities,
		namePrefix: null,
		applicationKeyExpirationTimestamp: null
	});
	response.apiInfo.storageApi.allowed.capabilities.pop();
	assert.equal(data.capabilities.length, capabilities.length);
});

test('B2 derives another region and retains the application key expiry', () => {
	const response = authorization();
	response.apiInfo.storageApi.s3ApiUrl = 'https://s3.eu-central-003.backblazeb2.com/';
	const expiresAt = Date.now() + 60_000;
	const data = discover('fixture-id', 'fixture-key', {
		...response,
		applicationKeyExpirationTimestamp: expiresAt
	});
	assert.equal(data.region, 'eu-central-003');
	assert.equal(data.endpoint, 'https://s3.eu-central-003.backblazeb2.com');
	assert.equal(data.applicationKeyExpirationTimestamp, expiresAt);
});

for (const value of [null, [], {}, { apiInfo: null }, { apiInfo: { storageApi: {} } }]) {
	test(`B2 rejects malformed discovery shape ${JSON.stringify(value)}`, () => {
		assert.throws(
			() => discover('fixture-id', 'fixture-key', value),
			fault(ErrorCode.INVALID_CREDENTIALS)
		);
	});
}
for (const [buckets, code] of [
	[null, ErrorCode.NO_BUCKETS],
	[[], ErrorCode.NO_BUCKETS],
	[
		[
			{ id: 'a', name: 'a' },
			{ id: 'b', name: 'b' }
		],
		ErrorCode.MULTIPLE_BUCKETS
	],
	[[{ id: 'a', name: null }], ErrorCode.BUCKET_INFO]
] as const) {
	test(`B2 never guesses a bucket when discovery returns error ${code}`, () => {
		const response: any = authorization();
		response.apiInfo.storageApi.allowed.buckets = buckets;
		assert.throws(() => discover('fixture-id', 'fixture-key', response), fault(code));
	});
}
for (const missing of capabilities) {
	test(`B2 retains the ${missing} permission requirement during migration`, () => {
		const response = authorization();
		response.apiInfo.storageApi.allowed.capabilities = capabilities.filter(
			(cap) => cap !== missing
		);
		assert.throws(
			() => discover('fixture-id', 'fixture-key', response),
			fault(ErrorCode.CREDENTIALS_INCAPABLE)
		);
	});
}
test('B2 keeps prefix restrictions fail-closed until credential/object paths support them', () => {
	const response = authorization();
	assert.throws(
		() =>
			discover('fixture-id', 'fixture-key', {
				...response,
				apiInfo: {
					storageApi: {
						...response.apiInfo.storageApi,
						allowed: { ...response.apiInfo.storageApi.allowed, namePrefix: 'restricted/' }
					}
				}
			}),
		fault(ErrorCode.NAMEPREFIX_EXIST)
	);
});

for (const field of ['apiUrl', 'downloadUrl', 's3ApiUrl'] as const) {
	for (const endpoint of [
		'https://untrusted.example.test',
		'https://127.0.0.1',
		'http://s3.us-west-004.backblazeb2.com',
		'https://user:secret@s3.us-west-004.backblazeb2.com',
		'https://s3.us-west-004.backblazeb2.com/?token=untrusted'
	]) {
		test(`B2 rejects unsafe ${field} endpoint ${endpoint}`, () => {
			const response = authorization();
			response.apiInfo.storageApi[field] = endpoint;
			assert.throws(
				() => discover('fixture-id', 'fixture-key', response),
				fault(ErrorCode.INVALID_CREDENTIALS)
			);
		});
	}
}
test('B2 malformed expiry cannot be persisted as valid credential metadata', () => {
	assert.throws(
		() =>
			discover('fixture-id', 'fixture-key', {
				...authorization(),
				applicationKeyExpirationTimestamp: 'later'
			}),
		fault(ErrorCode.INVALID_CREDENTIALS)
	);
});
