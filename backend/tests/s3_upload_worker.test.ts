import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Miniflare } from 'miniflare';

test('native Worker signs provider upload URLs without an empty-body checksum', async () => {
	const compiled = await build({
		stdin: {
			resolveDir: process.cwd(),
			contents: `
import {presignS3UploadUrl} from './src/lib/server/s3';
const fixtures = [
 {endpoint:'https://s3.us-west-1.idrivee2.com',region:'us-west-1',forcePathStyle:true},
 {endpoint:'https://fixture.r2.cloudflarestorage.com',region:'auto',forcePathStyle:false},
 {endpoint:'https://fixture.compat.objectstorage.us-ashburn-1.oraclecloud.com',region:'us-ashburn-1',forcePathStyle:true},
 {endpoint:'https://s3.example.test',region:'fixture-region',forcePathStyle:true}
];
export default {async fetch() {
 return Response.json(await Promise.all(fixtures.map(credentials => presignS3UploadUrl({
  ...credentials,appId:'fixture-access',appKey:'fixture-secret',bucketName:'fixture-bucket'
 },'fixture-user/'+ 'A'.repeat(43)+'_1'))));
}};`
		},
		bundle: true,
		write: false,
		platform: 'browser',
		conditions: ['workerd', 'worker', 'browser'],
		format: 'esm',
		target: 'es2022'
	});
	const worker = new Miniflare({
		modules: true,
		script: compiled.outputFiles[0].text,
		compatibilityDate: '2026-04-22',
		compatibilityFlags: ['nodejs_compat'],
		outboundService: async () => {
			throw new Error('URL signing must not require provider traffic');
		}
	});
	try {
		const response = await worker.dispatchFetch('https://worker.example.test/upload');
		assert.equal(response.status, 200);
		const urls = (await response.json()) as string[];
		assert.equal(urls.length, 4);
		for (const signed of urls) {
			const url = new URL(signed);
			assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
			assert.ok(url.pathname.endsWith(`/fixture-user/${'A'.repeat(43)}_1`));
			assert.equal(url.searchParams.get('x-amz-checksum-crc32'), null);
			assert.equal(url.searchParams.get('x-amz-checksum-sha256'), null);
			assert.equal(url.searchParams.get('X-Amz-Content-Sha256'), 'UNSIGNED-PAYLOAD');
			assert.ok(url.searchParams.get('X-Amz-Signature'));
		}
		assert.equal(new URL(urls[1]).hostname, 'fixture-bucket.fixture.r2.cloudflarestorage.com');
	} finally {
		await worker.dispose();
	}
});
