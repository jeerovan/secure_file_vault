import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Miniflare, Request as OutboundRequest, Response as OutboundResponse } from 'miniflare';

for (const status of [200, 403]) {
	test(`native Worker verifies discovered Backblaze S3 metadata with bucket HEAD ${status}`, async () => {
		const compiled = await build({
			stdin: {
				resolveDir: process.cwd(),
				contents: `
import { backblazeCredentialsFromAuthorization } from './src/lib/server/backblazeCredentials';
import { verifyGenericS3Credentials } from './src/lib/server/s3';
export default { async fetch() {
  const credentials = backblazeCredentialsFromAuthorization('fixture-id', 'fixture-secret', {
    accountId: 'fixture-account', authorizationToken: 'fixture-token',
    apiInfo: { storageApi: {
      apiUrl: 'https://api004.backblazeb2.com', downloadUrl: 'https://f004.backblazeb2.com',
      s3ApiUrl: 'https://s3.us-west-004.backblazeb2.com',
      allowed: { buckets: [{id: 'fixture-bucket-id', name: 'fixture-bucket'}], namePrefix: null,
        capabilities: ['deleteFiles','writeBuckets','readBuckets','readFiles','shareFiles','writeFiles','listFiles'] }
    }}
  });
  return Response.json({ verified: await verifyGenericS3Credentials(credentials) });
}};`
			},
			bundle: true,
			write: false,
			platform: 'browser',
			conditions: ['workerd', 'worker', 'browser'],
			format: 'esm',
			target: 'es2022'
		});
		let requests = 0;
		const worker = new Miniflare({
			modules: true,
			script: compiled.outputFiles[0].text,
			compatibilityDate: '2026-04-22',
			compatibilityFlags: ['nodejs_compat'],
			outboundService: async (request: OutboundRequest) => {
				requests++;
				const url = new URL(request.url);
				assert.equal(url.hostname, 's3.us-west-004.backblazeb2.com');
				assert.ok(url.pathname.startsWith('/fixture-bucket'));
				assert.equal(request.method, 'HEAD');
				assert.match(
					request.headers.get('authorization') ?? '',
					/^AWS4-HMAC-SHA256 Credential=fixture-id\//
				);
				return new OutboundResponse(null, { status });
			}
		});
		try {
			const result = await worker.dispatchFetch('https://worker.example.test');
			assert.deepEqual(await result.json(), { verified: status === 200 });
			assert.equal(requests, 1);
		} finally {
			await worker.dispose();
		}
	});
}
