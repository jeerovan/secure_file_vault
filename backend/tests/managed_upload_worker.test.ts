import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import {
	Miniflare,
	type Request as OutboundRequest,
	Response as OutboundResponse
} from 'miniflare';
import { awsWorkerAliases } from '../aws-worker-aliases';

test('Worker multipart transport parses provider XML and never treats an embedded error as completion', async (t) => {
	const compiled = await build({
		alias: awsWorkerAliases,
		stdin: {
			resolveDir: process.cwd(),
			contents: `
import {ProviderManagedUploadStorage} from './src/lib/server/managedUploadStorage';
const adapter=new ProviderManagedUploadStorage();
const row={id:'fixture-upload',cleanupCursor:{},providerId:6,objectKey:'fixture-user/'+ 'A'.repeat(43)+'_1',uploadId:'provider-upload',contentLength:37,sha1:'a'.repeat(40),md5:btoa('a'.repeat(16)),credentials:{endpoint:'https://objects.example.test',region:'fixture-region',bucketName:'fixture-bucket',appId:'fixture-access',appKey:'fixture-secret',forcePathStyle:true}};
export default {async fetch(request){
 const action=new URL(request.url).pathname;
 try {
  if(action==='/initiate')return Response.json({id:await adapter.initiate(row)});
  if(action==='/sign')return Response.json(await adapter.sign(row));
  if(action==='/complete')return Response.json(await adapter.finalize(row));
  let result;
  for(let i=0;i<10;i++){result=await adapter.cleanup(row);row.cleanupCursor=result.cursor;if(result.done)break;}
  return Response.json({deleted:result.done});
 }catch(error){return Response.json({error:error.code??'unexpected'});}
}};`
		},
		bundle: true,
		write: false,
		platform: 'browser',
		conditions: ['workerd', 'worker', 'browser'],
		format: 'esm',
		target: 'es2022'
	});
	for (const embeddedError of [false, true])
		await t.test(
			embeddedError
				? 'embedded completion error stays unresolved'
				: 'initiate, complete and verify exact deletion',
			async () => {
				let published = false,
					finished = false;
				const actions: string[] = [];
				const key = `fixture-user/${'A'.repeat(43)}_1`;
				const worker = new Miniflare({
					modules: true,
					script: compiled.outputFiles[0].text,
					compatibilityDate: '2026-04-22',
					compatibilityFlags: ['nodejs_compat'],
					outboundService: async (request: OutboundRequest) => {
						const url = new URL(request.url);
						assert.equal(url.hostname, 'objects.example.test');
						assert.match(
							request.headers.get('authorization') ?? '',
							/^AWS4-HMAC-SHA256 Credential=fixture-access\//
						);
						const xml = (body: string, status = 200) =>
							new OutboundResponse(body, {
								status,
								headers: { 'content-type': 'application/xml' }
							});
						const absent = () => xml('<Error><Code>NoSuchUpload</Code></Error>', 404);
						if (request.method === 'HEAD') {
							if (!published) return new OutboundResponse(null, { status: 404 });
							return new OutboundResponse(null, {
								headers: {
									'content-length': '37',
									'x-amz-meta-sha1': 'a'.repeat(40),
									'x-amz-meta-fife-upload': 'fixture-upload',
									'x-amz-version-id': 'exact-version'
								}
							});
						}
						if (request.method === 'POST' && url.searchParams.has('uploads')) {
							actions.push('initiate');
							assert.equal(request.headers.get('x-amz-meta-fife-upload'), 'fixture-upload');
							return xml(
								'<InitiateMultipartUploadResult><UploadId>provider-upload</UploadId></InitiateMultipartUploadResult>'
							);
						}
						if (url.searchParams.has('uploadId')) {
							assert.equal(url.searchParams.get('uploadId'), 'provider-upload');
							if (request.method === 'GET') {
								if (finished) return absent();
								return xml(
									'<ListPartsResult><IsTruncated>false</IsTruncated><Part><PartNumber>1</PartNumber><Size>37</Size><ETag>fixture-etag</ETag></Part></ListPartsResult>'
								);
							}
							if (request.method === 'DELETE') {
								actions.push('abort');
								return absent();
							}
							assert.equal(request.method, 'POST');
							actions.push('complete');
							assert.ok((await request.text()).includes('<ETag>fixture-etag</ETag>'));
							if (embeddedError)
								return xml(
									'<Error><Code>InternalError</Code><Message>fixture failure</Message></Error>'
								);
							published = finished = true;
							return xml(
								'<CompleteMultipartUploadResult><ETag>fixture-etag</ETag></CompleteMultipartUploadResult>'
							);
						}
						if (request.method === 'GET' && url.searchParams.has('versions'))
							return xml(
								`<ListVersionsResult><IsTruncated>false</IsTruncated>${published ? `<Version><Key>${key}</Key><VersionId>exact-version</VersionId></Version>` : ''}</ListVersionsResult>`
							);
						assert.equal(request.method, 'DELETE');
						assert.equal(url.searchParams.get('versionId'), 'exact-version');
						published = false;
						actions.push('delete-version');
						return new OutboundResponse(null, { status: 204 });
					}
				});
				try {
					assert.deepEqual(
						await (await worker.dispatchFetch('https://worker.example.test/initiate')).json(),
						{ id: 'provider-upload' }
					);
					const signed = (await (
						await worker.dispatchFetch('https://worker.example.test/sign')
					).json()) as any;
					assert.equal(new URL(signed.uploadUrl).searchParams.get('uploadId'), 'provider-upload');
					assert.deepEqual(actions, ['initiate']);
					const completed = await (
						await worker.dispatchFetch('https://worker.example.test/complete')
					).json();
					if (embeddedError) {
						assert.deepEqual(completed, { error: 'upload_outcome_unknown' });
						assert.equal(published, false);
					} else {
						assert.deepEqual(completed, { versionId: 'exact-version' });
						assert.equal(published, true);
						assert.deepEqual(
							await (await worker.dispatchFetch('https://worker.example.test/cleanup')).json(),
							{ deleted: true }
						);
						assert.equal(published, false);
						assert.ok(actions.includes('delete-version'));
					}
				} finally {
					await worker.dispose();
				}
			}
		);
});
