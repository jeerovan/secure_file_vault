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
