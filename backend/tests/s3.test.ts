import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizePublicS3Endpoint } from '../src/lib/server/s3';

test('normalizes a public HTTPS S3 endpoint', () => {
	assert.equal(
		normalizePublicS3Endpoint(' https://objects.example.com/s3/// '),
		'https://objects.example.com/s3'
	);
});

test('rejects unsafe or malformed S3 endpoints', () => {
	const rejected = [
		'http://objects.example.com',
		'https://localhost:9000',
		'https://minio.local',
		'https://127.0.0.1',
		'https://10.0.0.1',
		'https://192.168.1.2',
		'https://[::ffff:127.0.0.1]',
		'https://user:secret@objects.example.com',
		'https://objects.example.com?bucket=test',
		'https://objects.example.com/#fragment',
		'not a URL'
	];
	for (const endpoint of rejected) {
		assert.throws(() => normalizePublicS3Endpoint(endpoint), endpoint);
	}
});
