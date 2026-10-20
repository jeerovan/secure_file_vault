import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Miniflare, Request as OutboundRequest, Response as OutboundResponse } from 'miniflare';

test('native Worker signs B2 S3 uploads and preserves version identity for recovery and deletion', async () => {
	const compiled = await build({
		stdin: {
			resolveDir: process.cwd(),
			contents: `
import {backblazeS3Upload,findBackblazeS3Upload,deleteBackblazeS3Version} from './src/lib/server/backblazeS3';
const credentials={appId:'fixture-access',appKey:'fixture-secret',bucketName:'fixture-bucket',s3ApiUrl:'https://s3.us-west-004.backblazeb2.com'};
const key='fixture-user/'+ 'A'.repeat(43)+'_1';
export default {async fetch(request) {
  const action=new URL(request.url).pathname;
  if(action==='/upload') return Response.json(await backblazeS3Upload(credentials,key,{content_length:37,content_sha1:'a'.repeat(40),content_md5:btoa('a'.repeat(16))}));
  if(action==='/recover') return Response.json(await findBackblazeS3Upload(credentials,key,'a'.repeat(40),37));
  return Response.json({deleted:await deleteBackblazeS3Version(credentials,key,'fixture-version')});
}};`
		},
		bundle: true,
		write: false,
		platform: 'browser',
		conditions: ['workerd', 'worker', 'browser'],
		format: 'esm',
		target: 'es2022'
	});
	const methods: string[] = [];
	const worker = new Miniflare({
		modules: true,
		script: compiled.outputFiles[0].text,
		compatibilityDate: '2026-04-22',
		compatibilityFlags: ['nodejs_compat'],
		outboundService: async (request: OutboundRequest) => {
			methods.push(request.method);
			const url = new URL(request.url);
			assert.equal(url.hostname, 's3.us-west-004.backblazeb2.com');
			assert.equal(url.pathname, `/fixture-bucket/fixture-user/${'A'.repeat(43)}_1`);
			assert.match(
				request.headers.get('authorization') ?? '',
				/^AWS4-HMAC-SHA256 Credential=fixture-access\//
			);
			if (request.method === 'HEAD')
				return new OutboundResponse(null, {
					headers: {
						'content-length': '37',
						'x-amz-meta-sha1': 'a'.repeat(40),
						'x-amz-version-id': 'fixture-version'
					}
				});
			assert.equal(request.method, 'DELETE');
			assert.equal(url.searchParams.get('versionId'), 'fixture-version');
			return new OutboundResponse(null, { status: 204 });
		}
	});
	try {
		const signed = (await (
			await worker.dispatchFetch('https://worker.example.test/upload')
		).json()) as { protocol: string; uploadUrl: string };
		assert.equal(signed.protocol, 's3');
		const url = new URL(signed.uploadUrl);
		assert.equal(url.searchParams.get('X-Amz-Expires'), '900');
		for (const header of ['content-md5', 'content-length', 'content-type', 'x-amz-meta-sha1'])
			assert.ok(url.searchParams.get('X-Amz-SignedHeaders')?.split(';').includes(header));
		assert.deepEqual(
			await (await worker.dispatchFetch('https://worker.example.test/recover')).json(),
			{ fileId: 'fixture-version' }
		);
		assert.deepEqual(
			await (await worker.dispatchFetch('https://worker.example.test/delete')).json(),
			{ deleted: true }
		);
		assert.deepEqual(methods, ['HEAD', 'DELETE']);
	} finally {
		await worker.dispose();
	}
});
