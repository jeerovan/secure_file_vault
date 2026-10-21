import assert from 'node:assert/strict';
import test from 'node:test';
import {
	ProviderManagedUploadStorage,
	UploadFault,
	type UploadRecord
} from '../src/lib/server/managedUploadStorage';

const row: UploadRecord = {
	id: crypto.randomUUID(),
	userId: 1,
	deviceUuid: 'fixture',
	generation: 'legacy',
	storageId: 7,
	providerId: 6,
	objectKey: `fixture/${'a'.repeat(43)}_1`,
	partName: `${'a'.repeat(43)}_1`,
	credentials: {
		endpoint: 'https://objects.example.test',
		region: 'us-east-1',
		bucketName: 'bucket',
		appId: 'fixture',
		appKey: 'fixture',
		forcePathStyle: true
	},
	receiptHash: 'a'.repeat(64),
	contentLength: 37,
	sha1: 'a'.repeat(40),
	md5: 'AAAAAAAAAAAAAAAAAAAAAA==',
	uploadId: 'specific-upload',
	versionId: null,
	phase: 'uploading',
	uncertain: null,
	cleanupCursor: {},
	operationId: null,
	retired: 0,
	createdAt: 1,
	updatedAt: 1,
	leaseOwner: null,
	leaseUntil: 0,
	nextAttemptAt: 1,
	attempts: 0,
	error: null
};
const absent = () =>
	Object.assign(new Error('missing'), { name: 'NoSuchUpload', $metadata: { httpStatusCode: 404 } });
const matching = {
	ContentLength: row.contentLength,
	Metadata: { sha1: row.sha1, 'fife-upload': row.id },
	VersionId: 'exact-version'
};
function fixture(handle: (name: string, input: any) => any) {
	const calls: { name: string; input: any }[] = [];
	const storage = new ProviderManagedUploadStorage(() => ({
		send: (async (command: any) => {
			calls.push({ name: command.constructor.name, input: command.input });
			return handle(command.constructor.name, command.input);
		}) as any,
		destroy() {}
	}));
	return { storage, calls };
}
async function terminal(storage: ProviderManagedUploadStorage, original: UploadRecord, steps = 1) {
	let cursor = original.cleanupCursor;
	for (let i = 0; i < steps; i++) {
		const result = await storage.cleanup({ ...original, cleanupCursor: cursor });
		if (result.done) return true;
		cursor = result.cursor;
	}
	return false;
}

test('managed signature grants exactly one UploadPart and no completion permission', async () => {
	const descriptor = await new ProviderManagedUploadStorage().sign(row);
	const url = new URL(descriptor.uploadUrl);
	assert.equal(url.searchParams.get('uploadId'), row.uploadId);
	assert.equal(url.searchParams.get('partNumber'), '1');
	assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
	assert.ok(url.searchParams.get('X-Amz-SignedHeaders')?.includes('content-md5'));
	assert.ok(url.searchParams.get('X-Amz-SignedHeaders')?.includes('content-length'));
	assert.equal(descriptor.headers['Content-MD5'], row.md5);
});
test('unique managed object cleanup removes its exact delete markers and preserves sibling markers', async () => {
	const unique = {
		...row,
		objectKey: `${row.objectKey}~${row.id}`,
		cleanupCursor: { settled: true }
	};
	let marker = true;
	const f = fixture((name, input) => {
		if (name === 'ListObjectVersionsCommand')
			return {
				IsTruncated: false,
				DeleteMarkers: [
					...(marker ? [{ Key: unique.objectKey, VersionId: 'own-marker' }] : []),
					{ Key: `${unique.objectKey}other`, VersionId: 'other-marker' }
				]
			};
		if (name === 'DeleteObjectCommand') {
			assert.equal(input.Key, unique.objectKey);
			assert.equal(input.VersionId, 'own-marker');
			marker = false;
			return {};
		}
		if (name === 'HeadObjectCommand') throw absent();
		assert.fail(name);
	});
	assert.equal(await terminal(f.storage, unique, 3), true);
	assert.equal(marker, false);
});
test('missing or incomplete uploaded bytes cannot be finalized', async () => {
	for (const Parts of [
		[],
		[{ PartNumber: 1, Size: 36, ETag: 'etag' }],
		[{ PartNumber: 2, Size: 37, ETag: 'etag' }]
	]) {
		const f = fixture((name) => {
			if (name === 'HeadObjectCommand') throw absent();
			if (name === 'ListPartsCommand') return { IsTruncated: false, Parts };
			assert.fail('Completion must not run');
		});
		await assert.rejects(
			f.storage.finalize(row),
			(e: unknown) => e instanceof UploadFault && e.code === 'upload_not_ready' && e.definite
		);
	}
});
test('a lost completion response recovers the exact object without completing it again', async () => {
	const f = fixture((name) => {
		assert.equal(name, 'HeadObjectCommand');
		return matching;
	});
	assert.deepEqual(await f.storage.finalize({ ...row, uncertain: 'complete' }), {
		versionId: 'exact-version'
	});
	assert.equal(f.calls.length, 1);
});
test('ambiguous completion with an empty prefix is retained without a false deletion', async () => {
	const f = fixture((name) => {
		if (['HeadObjectCommand', 'ListPartsCommand'].includes(name)) throw absent();
		assert.fail('An unknown consumed upload must not be recreated');
	});
	assert.equal(await terminal(f.storage, { ...row, uncertain: 'complete' }), false);
});

test('retirement after verification prevents the provider Complete request', async () => {
	const f = fixture((name) => {
		if (name === 'HeadObjectCommand') throw absent();
		if (name === 'ListPartsCommand')
			return { IsTruncated: false, Parts: [{ PartNumber: 1, Size: 37, ETag: 'etag' }] };
		assert.fail('Completion must not run after retirement wins its lock');
	});
	await assert.rejects(
		f.storage.finalize(row, async () => false),
		/upload_retired/
	);
});

test('completion intent is reconciled and its proof survives a lost deletion response', async () => {
	let published = false,
		consumed = false,
		loseDelete = true,
		completions = 0;
	const f = fixture((name, input) => {
		if (name === 'HeadObjectCommand') {
			if (published) return matching;
			throw absent();
		}
		if (name === 'ListPartsCommand') {
			if (consumed) throw absent();
			return { IsTruncated: false, Parts: [{ PartNumber: 1, Size: 37, ETag: 'etag' }] };
		}
		if (name === 'CompleteMultipartUploadCommand') {
			published = consumed = true;
			completions++;
			return { VersionId: 'exact-version' };
		}
		if (name === 'AbortMultipartUploadCommand') throw absent();
		if (name === 'ListObjectVersionsCommand')
			return {
				IsTruncated: false,
				Versions: published ? [{ Key: row.objectKey, VersionId: 'exact-version' }] : []
			};
		if (name === 'DeleteObjectCommand') {
			assert.equal(input.VersionId, 'exact-version');
			published = false;
			if (loseDelete) {
				loseDelete = false;
				throw new Error('lost delete response');
			}
			return {};
		}
		assert.fail(name);
	});
	const original = { ...row, uncertain: 'complete' };
	const checkpoint = await f.storage.cleanup(original);
	assert.equal(checkpoint.done, false);
	assert.equal(checkpoint.cursor.settled, true);
	assert.equal(published, true, 'completion evidence must survive until its checkpoint commits');
	assert.equal(completions, 1);
	const restarted = { ...original, cleanupCursor: checkpoint.cursor };
	await assert.rejects(f.storage.cleanup(restarted), /upload_cleanup_blocked/);
	assert.equal(published, false);
	assert.equal((await f.storage.cleanup(restarted)).done, true);
	assert.equal(completions, 1, 'deletion retry must not complete the upload again');
});

test('version cleanup checkpoints pages and never advances past a deleted marker', async () => {
	let owned = true;
	const untouched = new Set(['other-1', 'other-2', 'other-3', 'other-4', 'other-5']);
	const f = fixture((name, input) => {
		if (name === 'ListObjectVersionsCommand') {
			assert.ok(input.MaxKeys <= 5);
			if (!input.VersionIdMarker)
				return {
					IsTruncated: true,
					NextKeyMarker: row.objectKey,
					NextVersionIdMarker: 'other-5',
					Versions: [...untouched].map((VersionId) => ({ Key: row.objectKey, VersionId }))
				};
			assert.equal(input.VersionIdMarker, 'other-5');
			return {
				IsTruncated: false,
				Versions: owned ? [{ Key: row.objectKey, VersionId: 'owned' }] : []
			};
		}
		if (name === 'HeadObjectCommand') {
			if (input.VersionId === 'owned' && owned) return matching;
			if (untouched.has(input.VersionId))
				return { ...matching, Metadata: { 'fife-upload': 'another-operation' } };
			throw absent();
		}
		if (name === 'DeleteObjectCommand') {
			assert.equal(input.VersionId, 'owned');
			owned = false;
			return {};
		}
		assert.fail(name);
	});
	assert.equal(
		await terminal(
			f.storage,
			{ ...row, cleanupCursor: { settled: true, proofVersion: 'owned' } },
			5
		),
		true
	);
	assert.equal(untouched.size, 5);
	assert.equal(owned, false);
});

test('NoSuchKey is not terminal proof for an upload ID', async () => {
	const f = fixture((name) => {
		if (name === 'HeadObjectCommand' || name === 'AbortMultipartUploadCommand') throw absent();
		if (name === 'ListPartsCommand') throw Object.assign(absent(), { name: 'NoSuchKey' });
		assert.fail(name);
	});
	await assert.rejects(f.storage.cleanup(row), /upload_cleanup_blocked/);
});
test('ambiguous initiation with no discovered upload ID remains pending', async () => {
	const f = fixture((name) => {
		assert.equal(name, 'ListMultipartUploadsCommand');
		return { IsTruncated: false, Uploads: [] };
	});
	assert.equal(await terminal(f.storage, { ...row, uploadId: null, uncertain: 'create' }), false);
});
test('abort is retried while a provider still reports uploaded parts', async () => {
	const f = fixture((name) => {
		if (name === 'HeadObjectCommand') throw absent();
		if (name === 'AbortMultipartUploadCommand') return {};
		if (name === 'ListPartsCommand')
			return { IsTruncated: false, Parts: [{ PartNumber: 1, Size: 37 }] };
		assert.fail('An unverified abort must not acknowledge cleanup');
	});
	assert.equal(await terminal(f.storage, row), false);
	assert.equal(await terminal(f.storage, row), false);
	assert.equal(f.calls.filter((c) => c.name === 'AbortMultipartUploadCommand').length, 2);
});

test('an empty but still addressable multipart upload is not a verified terminal abort', async () => {
	const f = fixture((name) => {
		if (name === 'HeadObjectCommand') throw absent();
		if (name === 'AbortMultipartUploadCommand') return {};
		if (name === 'ListPartsCommand') return { IsTruncated: false, Parts: [] };
		if (name === 'ListObjectVersionsCommand') return { IsTruncated: false, Versions: [] };
		assert.fail(name);
	});
	assert.equal(await terminal(f.storage, row), false);
});
test('exact-version cleanup preserves unrelated versions, sibling keys and credentials', async () => {
	const owned = new Set(['v1', 'v2']);
	const f = fixture((name, input) => {
		if (name === 'HeadObjectCommand') {
			if (owned.has(input.VersionId)) return matching;
			if (input.VersionId === 'other')
				return { ...matching, Metadata: { sha1: 'different', 'fife-upload': 'other-attempt' } };
			throw absent();
		}
		if (name === 'AbortMultipartUploadCommand' || name === 'ListPartsCommand') throw absent();
		if (name === 'ListObjectVersionsCommand')
			return {
				IsTruncated: false,
				Versions: [...owned, 'other']
					.map((VersionId) => ({ Key: row.objectKey, VersionId }))
					.concat([{ Key: `${row.objectKey}-sibling`, VersionId: 'outside' }])
			};
		if (name === 'DeleteObjectCommand') {
			assert.equal(input.Key, row.objectKey);
			assert.ok(owned.delete(input.VersionId));
			return {};
		}
		assert.fail(name);
	});
	assert.equal(await terminal(f.storage, row, 5), true);
	assert.equal(owned.size, 0);
	assert.equal(f.calls.filter((c) => c.name === 'DeleteObjectCommand').length, 2);
	assert.equal(row.credentials.appKey, 'fixture');
});
test('malformed provider listings cannot be interpreted as verified empty storage', async () => {
	const f = fixture((name) => {
		if (name === 'HeadObjectCommand') throw absent();
		if (name === 'AbortMultipartUploadCommand' || name === 'ListPartsCommand') throw absent();
		if (name === 'ListObjectVersionsCommand') return {};
		assert.fail(name);
	});
	await assert.rejects(terminal(f.storage, row, 5), /upload_cleanup_blocked/);
});
test('provider deletion failure remains retryable and does not expose raw errors', async () => {
	const f = fixture((name) => {
		if (name === 'HeadObjectCommand') return matching;
		if (name === 'AbortMultipartUploadCommand') throw new Error('private provider response');
		assert.fail(name);
	});
	await assert.rejects(
		terminal(f.storage, row, 5),
		(e: unknown) => e instanceof UploadFault && e.message === 'upload_cleanup_blocked'
	);
});
