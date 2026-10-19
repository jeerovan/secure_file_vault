import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizePublicS3Endpoint } from '../src/lib/server/s3';

test('normalizes a public HTTPS S3 endpoint', () => {
	assert.equal(
		normalizePublicS3Endpoint(' https://objects.example.com/s3/// '),
		'https://objects.example.com/s3'
	);
});

test('accepts public S3 hostnames containing exactly four labels', () => {
	assert.equal(
		normalizePublicS3Endpoint('https://s3.eu-central-2.idrivee2.com'),
		'https://s3.eu-central-2.idrivee2.com'
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

test('reserved IPv4 and IPv6 endpoints cannot receive signed bucket requests', () => {
	for (const host of [
		'0.0.0.0',
		'100.64.0.1',
		'100.127.255.254',
		'169.254.1.1',
		'172.16.0.1',
		'172.31.255.254',
		'198.18.0.1',
		'198.19.255.254',
		'224.0.0.1',
		'255.255.255.255',
		'[::]',
		'[::1]',
		'[fc00::1]',
		'[fd00::1]',
		'[fe80::1]',
		'[febf::1]',
		'vault.localhost'
	])
		assert.throws(() => normalizePublicS3Endpoint(`https://${host}`), host);
	assert.equal(normalizePublicS3Endpoint('https://8.8.8.8'), 'https://8.8.8.8');
});
