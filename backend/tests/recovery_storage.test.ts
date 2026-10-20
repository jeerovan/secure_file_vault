import assert from 'node:assert/strict';
import test from 'node:test';
import type { S3Client } from '@aws-sdk/client-s3';
import {
	ProviderRecoveryStorage,
	createRecoveryS3Client,
	isRetiredVaultObject,
	vaultObjectPrefix,
	type RecoveryTarget
} from '../src/lib/server/recoveryStorage';

const hash = 'a'.repeat(43);
const key = `fixture-user/${hash}_1`;
const target: RecoveryTarget = {
	providerId: 6,
	prefix: 'fixture-user/',
	credentials: {
		appId: 'fixture-id',
		appKey: 'fixture-key',
		bucketName: 'shared-bucket',
		region: 'auto',
		endpoint: 'https://s3.example.test',
		forcePathStyle: true
	}
};

test('retired ownership excludes other accounts, new generations and unrelated names', () => {
	assert.equal(isRetiredVaultObject(target.prefix, key), true);
	for (const value of [
		`other-user/${hash}_1`,
		`fixture-user/vaults/new/${hash}_1`,
		'fixture-user/original.txt',
		`fixture-user/../${hash}_1`,
		`fixture-user/${hash}_0`,
		null
	]) {
		assert.equal(isRetiredVaultObject(target.prefix, value), false);
	}
	assert.equal(
		vaultObjectPrefix('fixture-user', 'new-generation'),
		'fixture-user/vaults/new-generation/'
	);
	assert.throws(() => vaultObjectPrefix('../other'));
});

test('R2 cleanup builds the endpoint from credential accountId', async () => {
	const client = createRecoveryS3Client({
		...target,
		providerId: 3,
		credentials: { ...target.credentials, accountId: 'fixture-account' }
	});
	try {
		const endpoint = await client.config.endpoint!();
		assert.equal(endpoint.hostname, 'fixture-account.r2.cloudflarestorage.com');
	} finally {
		client.destroy();
	}
});

for (const providerId of [6, 1, 2]) {
	test(`provider ${providerId} S3 deletion removes all owned versions, delete markers and unfinished uploads`, async () => {
		const currentTarget =
			providerId === 6
				? target
				: {
						...target,
						providerId,
						credentials: {
							...target.credentials,
							s3ApiUrl: 'https://s3.us-west-004.backblazeb2.com'
						}
					};
		let versions = [
			{ Key: key, VersionId: 'old' },
			{ Key: key, VersionId: 'current' },
			{ Key: `other-user/${hash}_1`, VersionId: 'other' },
			{ Key: `fixture-user/vaults/new/${hash}_1`, VersionId: 'new' },
			{ Key: 'fixture-user/original.txt', VersionId: 'external' }
		];
		let markers = [{ Key: key, VersionId: 'marker' }];
		let uploads = [
			{ Key: key, UploadId: 'retired-upload' },
			{ Key: 'fixture-user/original.txt', UploadId: 'other-upload' }
		];
		const deleted: string[] = [];
		const client = {
			destroy() {},
			async send(command: any) {
				switch (command.constructor.name) {
					case 'ListObjectVersionsCommand':
						return { Versions: versions, DeleteMarkers: markers, IsTruncated: false };
					case 'ListMultipartUploadsCommand':
						return { Uploads: uploads, IsTruncated: false };
					case 'DeleteObjectsCommand':
						for (const object of command.input.Delete.Objects) {
							assert.equal(object.Key, key);
							deleted.push(object.VersionId);
							versions = versions.filter((version) => version.VersionId !== object.VersionId);
							markers = markers.filter((version) => version.VersionId !== object.VersionId);
						}
						return {};
					case 'AbortMultipartUploadCommand':
						assert.equal(command.input.Key, key);
						uploads = uploads.filter((upload) => upload.UploadId !== command.input.UploadId);
						return {};
					default:
						assert.fail(command.constructor.name);
				}
			}
		} as unknown as Pick<S3Client, 'send' | 'destroy'>;
		const adapter = new ProviderRecoveryStorage(() => client);
		await adapter.probe(currentTarget);
		let cursor = {};
		let done = false;
		for (let i = 0; i < 10 && !done; i++)
			({ cursor, done } = await adapter.step(currentTarget, cursor));
		assert.equal(done, true);
		assert.deepEqual(deleted.sort(), ['current', 'marker', 'old']);
		assert.deepEqual(versions.map((version) => version.VersionId).sort(), [
			'external',
			'new',
			'other'
		]);
		assert.deepEqual(
			uploads.map((upload) => upload.UploadId),
			['other-upload']
		);
	});
}

test('a partial or locked-object delete is not reported as completion', async () => {
	const adapter = new ProviderRecoveryStorage(
		() =>
			({
				destroy() {},
				async send(command: any) {
					if (command.constructor.name === 'ListObjectVersionsCommand')
						return {
							Versions: [{ Key: key, VersionId: 'locked' }],
							IsTruncated: false
						};
					if (command.constructor.name === 'DeleteObjectsCommand')
						return { Errors: [{ Code: 'AccessDenied' }] };
					assert.fail(command.constructor.name);
				}
			}) as unknown as Pick<S3Client, 'send' | 'destroy'>
	);
	await assert.rejects(adapter.step(target, {}), /storage_cleanup_blocked/);
});

test('pagination advances over unrelated keys without deleting them', async () => {
	let removed = false;
	const adapter = new ProviderRecoveryStorage(
		() =>
			({
				destroy() {},
				async send(command: any) {
					if (command.constructor.name === 'ListObjectVersionsCommand') {
						if (!command.input.KeyMarker)
							return {
								Versions: [{ Key: 'fixture-user/original.txt', VersionId: 'external' }],
								IsTruncated: true,
								NextKeyMarker: 'fixture-user/original.txt',
								NextVersionIdMarker: 'external'
							};
						return {
							Versions: removed ? [] : [{ Key: key, VersionId: 'owned' }],
							IsTruncated: false
						};
					}
					if (command.constructor.name === 'DeleteObjectsCommand') {
						removed = true;
						return {};
					}
					if (command.constructor.name === 'ListMultipartUploadsCommand')
						return { IsTruncated: false };
					assert.fail(command.constructor.name);
				}
			}) as unknown as Pick<S3Client, 'send' | 'destroy'>
	);
	let cursor = {};
	let done = false;
	for (let i = 0; i < 10 && !done; i++) ({ cursor, done } = await adapter.step(target, cursor));
	assert.equal(done, true);
	assert.equal(removed, true);
});

test('B2 enumerates versions and cancels owned unfinished uploads without bucket-wide deletion', async () => {
	let files = [
		{ fileName: key, fileId: 'old', action: 'upload' },
		{ fileName: key, fileId: 'start', action: 'start' },
		{ fileName: 'fixture-user/original.txt', fileId: 'external', action: 'upload' }
	];
	const actions: string[] = [];
	const adapter = new ProviderRecoveryStorage(undefined, async (url, options) => {
		assert.equal(options?.redirect, 'manual', 'Use the redirect mode supported by workerd');
		const action = String(url).split('/').pop()!;
		actions.push(action);
		if (action === 'b2_authorize_account')
			return Response.json({
				authorizationToken: 'fixture-token',
				apiInfo: {
					storageApi: {
						apiUrl: 'https://api001.backblazeb2.com',
						allowed: { capabilities: ['listFiles', 'deleteFiles'] }
					}
				}
			});
		const body = JSON.parse(options!.body as string);
		if (action === 'b2_list_file_versions') {
			assert.equal(body.prefix, target.prefix);
			return Response.json({ files, nextFileName: null, nextFileId: null });
		}
		if (action === 'b2_list_unfinished_large_files')
			return Response.json({ files: [], nextFileId: null });
		assert.ok(['b2_delete_file_version', 'b2_cancel_large_file'].includes(action));
		assert.notEqual(body.fileId, 'external');
		files = files.filter((file) => file.fileId !== body.fileId);
		return Response.json({ fileId: body.fileId });
	});
	const b2 = {
		...target,
		providerId: 2,
		credentials: { ...target.credentials, bucketId: 'fixture-bucket' }
	};
	await adapter.probe(b2);
	let cursor = {};
	let done = false;
	for (let i = 0; i < 10 && !done; i++) ({ cursor, done } = await adapter.step(b2, cursor));
	assert.equal(done, true);
	assert.ok(actions.includes('b2_cancel_large_file'));
	assert.deepEqual(
		files.map((file) => file.fileId),
		['external']
	);
});

test('B2 insufficient permissions prevent confirmation before deletion', async () => {
	const adapter = new ProviderRecoveryStorage(undefined, async () =>
		Response.json({
			apiInfo: {
				storageApi: {
					apiUrl: 'https://api001.backblazeb2.com',
					allowed: { capabilities: ['writeFiles'] }
				}
			}
		})
	);
	await assert.rejects(adapter.probe({ ...target, providerId: 2 }), /storage_access_required/);
});

test('B2 authorization and API redirects stop preflight without cleanup', async () => {
	for (const redirectAuthorization of [true, false]) {
		const actions: string[] = [];
		const adapter = new ProviderRecoveryStorage(undefined, async (url, options) => {
			assert.equal(options?.redirect, 'manual');
			assert.ok(new URL(String(url)).hostname.endsWith('.backblazeb2.com'));
			const action = String(url).split('/').pop()!;
			actions.push(action);
			if (action === 'b2_authorize_account' && !redirectAuthorization) {
				return Response.json({
					authorizationToken: 'fixture-token',
					apiInfo: {
						storageApi: {
							apiUrl: 'https://api001.backblazeb2.com',
							allowed: { capabilities: ['listFiles', 'deleteFiles'] }
						}
					}
				});
			}
			return Response.json(
				{ code: 'redirected' },
				{ status: 302, headers: { location: 'https://untrusted.example.test/provider' } }
			);
		});
		await assert.rejects(
			adapter.probe({
				...target,
				providerId: 2,
				credentials: { ...target.credentials, bucketId: 'fixture-bucket' }
			}),
			/storage_access_required|storage_cleanup_blocked/
		);
		assert.deepEqual(
			actions,
			redirectAuthorization
				? ['b2_authorize_account']
				: ['b2_authorize_account', 'b2_list_file_versions']
		);
	}
});

test('malformed S3/R2 listing entries cannot be acknowledged as deleted', async () => {
	for (const [providerId, cursor, listing] of [
		[6, {}, { Versions: [{ VersionId: 'missing-key' }], IsTruncated: false }],
		[3, {}, { Contents: [{}], IsTruncated: false }],
		[6, { step: 'uploads' }, { Uploads: [{ UploadId: 'missing-key' }], IsTruncated: false }]
	] as const) {
		const adapter = new ProviderRecoveryStorage(
			() =>
				({
					destroy() {},
					async send() {
						return listing;
					}
				}) as unknown as S3Client
		);
		await assert.rejects(adapter.step({ ...target, providerId }, cursor), /storage_unavailable/);
	}
});
