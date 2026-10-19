import assert from 'node:assert/strict';
import test from 'node:test';

import { findMatchingB2Upload } from '../src/lib/server/b2UploadRecovery';

test('finds only an exact completed B2 upload', () => {
	const match = findMatchingB2Upload(
		[
			{
				fileId: 'wrong-size',
				fileName: 'user/file_1',
				contentLength: 9,
				contentSha1: 'sha1',
				action: 'upload'
			},
			{
				fileId: 'expected',
				fileName: 'user/file_1',
				contentLength: 10,
				contentSha1: 'sha1',
				action: 'upload'
			}
		],
		'user/file_1',
		'sha1',
		10
	);

	assert.equal(match?.fileId, 'expected');
});

test('does not recover a mismatched or hidden B2 object', () => {
	assert.equal(
		findMatchingB2Upload(
			[
				{
					fileId: 'hidden',
					fileName: 'user/file_1',
					contentLength: 10,
					contentSha1: 'sha1',
					action: 'hide'
				}
			],
			'user/file_1',
			'sha1',
			10
		),
		undefined
	);
});

for (const [field, value] of [
	['fileName', 'other-user/file_1'],
	['fileName', 'user/file_10'],
	['contentSha1', 'different-content'],
	['contentLength', 9],
	['action', 'start'],
	['action', 'hide'],
	['fileId', ''],
	['fileId', undefined]
] as const) {
	test(`recovery rejects a candidate with mismatched ${field}=${String(value)}`, () => {
		const entry = {
			fileId: 'version-id',
			fileName: 'user/file_1',
			contentSha1: 'sha1',
			contentLength: 10,
			action: 'upload',
			[field]: value
		};
		assert.equal(findMatchingB2Upload([entry], 'user/file_1', 'sha1', 10), undefined);
	});
}

test('recovery scans past unrelated prefixes and chooses the exact completed version', () => {
	const matching = {
		fileId: 'correct-version',
		fileName: 'user/file_1',
		contentSha1: 'sha1',
		contentLength: 10,
		action: 'upload'
	};
	assert.equal(
		findMatchingB2Upload(
			[{ ...matching, fileName: 'user/file_10' }, { ...matching, action: 'start' }, matching],
			'user/file_1',
			'sha1',
			10
		),
		matching
	);
});
