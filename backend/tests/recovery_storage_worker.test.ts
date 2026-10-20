import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { awsWorkerAliases } from '../aws-worker-aliases';
import { build } from 'esbuild';
import {
	Miniflare,
	type Request as OutboundRequest,
	Response as OutboundResponse
} from 'miniflare';

const key = `fixture-user/${'A'.repeat(43)}_1`;
const initialFiles = [
	{ fileName: key, fileId: 'owned-version', action: 'upload' },
	{ fileName: key, fileId: 'owned-unfinished', action: 'start' },
	{ fileName: 'fixture-user/original.txt', fileId: 'external', action: 'upload' }
];

async function providerWorker(redirectAction?: string) {
	const compiled = await build({
		alias: awsWorkerAliases,
		stdin: {
			resolveDir: process.cwd(),
			contents: `
import { ProviderRecoveryStorage } from './src/lib/server/recoveryStorage';
export default {
  async fetch() {
    const adapter = new ProviderRecoveryStorage();
    const target = { providerId: 1, prefix: 'fixture-user/', credentials: {
      appId: 'fixture-id', appKey: 'fixture-key', bucketId: 'fixture-bucket'
    }};
    try {
      await adapter.probe(target);
      let result = { cursor: {}, done: false };
      for (let i = 0; i < 10 && !result.done; i++) {
        result = await adapter.step(target, result.cursor);
      }
      return Response.json({ done: result.done });
    } catch (error) {
      return Response.json({ done: false, error: error.code ?? 'unexpected_error' });
    }
  }
}`
		},
		bundle: true,
		write: false,
		platform: 'browser',
		conditions: ['workerd', 'worker', 'browser'],
		format: 'esm',
		target: 'es2022'
	});
	let files = [...initialFiles];
	const actions: string[] = [];
	let redirectedRequests = 0;
	const worker = new Miniflare({
		modules: true,
		compatibilityDate: '2024-04-22',
		compatibilityFlags: ['nodejs_compat'],
		script: compiled.outputFiles[0].text,
		async outboundService(request: OutboundRequest) {
			const url = new URL(request.url);
			if (!url.hostname.endsWith('.backblazeb2.com')) {
				redirectedRequests++;
				return OutboundResponse.json({});
			}
			const action = url.pathname.split('/').pop()!;
			actions.push(action);
			if (action === redirectAction) {
				return OutboundResponse.json(
					{ code: 'redirected' },
					{ status: 302, headers: { location: 'https://untrusted.example.test/provider' } }
				);
			}
			if (action === 'b2_authorize_account') {
				assert.equal(
					request.headers.get('authorization'),
					`Basic ${Buffer.from('fixture-id:fixture-key').toString('base64')}`
				);
				return OutboundResponse.json({
					authorizationToken: 'fixture-token',
					apiInfo: {
						storageApi: {
							apiUrl: 'https://api001.backblazeb2.com',
							allowed: { capabilities: ['listFiles', 'deleteFiles'] }
						}
					}
				});
			}
			assert.equal(request.headers.get('authorization'), 'fixture-token');
			const body = (await request.json()) as Record<string, unknown>;
			if (action === 'b2_list_file_versions') {
				assert.equal(body.prefix, 'fixture-user/');
				assert.equal(body.bucketId, 'fixture-bucket');
				return OutboundResponse.json({ files, nextFileName: null, nextFileId: null });
			}
			if (action === 'b2_list_unfinished_large_files') {
				assert.equal(body.namePrefix, 'fixture-user/');
				return OutboundResponse.json({ files: [], nextFileId: null });
			}
			assert.ok(['b2_delete_file_version', 'b2_cancel_large_file'].includes(action));
			assert.notEqual(body.fileId, 'external');
			files = files.filter((file) => file.fileId !== body.fileId);
			return OutboundResponse.json({ fileId: body.fileId });
		}
	});
	try {
		const result = await (await worker.dispatchFetch('http://fixture.test')).json();
		return { result, files, actions, redirectedRequests };
	} finally {
		await worker.dispose();
	}
}

test('Worker default B2 transport cleans owned versions and preserves unrelated files', async () => {
	const result = await providerWorker();
	assert.deepEqual(result.result, { done: true });
	assert.deepEqual(
		result.files.map((file) => file.fileId),
		['external']
	);
	assert.ok(result.actions.includes('b2_cancel_large_file'));
	assert.equal(result.redirectedRequests, 0);
});

test('Worker B2 transport rejects authorization and API redirects before deleting files', async () => {
	for (const action of ['b2_authorize_account', 'b2_list_file_versions']) {
		const result = await providerWorker(action);
		assert.deepEqual(result.result, {
			done: false,
			error:
				action === 'b2_authorize_account' ? 'storage_access_required' : 'storage_cleanup_blocked'
		});
		assert.deepEqual(result.files, initialFiles);
		assert.equal(result.redirectedRequests, 0);
		assert.deepEqual(
			result.actions,
			action === 'b2_authorize_account'
				? ['b2_authorize_account']
				: ['b2_authorize_account', 'b2_list_file_versions']
		);
	}
});

test('Worker OCI cleanup uses a supported body checksum for exact-version bulk deletion', async () => {
	const compiled = await build({
		alias: awsWorkerAliases,
		stdin: {
			resolveDir: process.cwd(),
			contents: `
import {ProviderRecoveryStorage} from './src/lib/server/recoveryStorage';
export default {async fetch() {
 const adapter = new ProviderRecoveryStorage();
 const target = {providerId:4,prefix:'fixture-user/',credentials:{
  namespace:'fixture',region:'us-ashburn-1',appId:'fixture-id',appKey:'fixture-key',bucketName:'fixture-bucket'
 }};
 try {
  let result={cursor:{},done:false};
  for(let i=0;i<8&&!result.done;i++)result=await adapter.step(target,result.cursor);
  return Response.json({done:result.done});
 }catch(error){return Response.json({done:false,error:error.code});}
}};`
		},
		bundle: true,
		write: false,
		platform: 'browser',
		conditions: ['workerd', 'worker', 'browser'],
		format: 'esm',
		target: 'es2022'
	});
	let deleted = false;
	let validChecksum = false;
	const wire: { method: string; path: string; sha256: boolean; crc32: boolean; kind: string[] }[] =
		[];
	const worker = new Miniflare({
		modules: true,
		script: compiled.outputFiles[0].text,
		compatibilityDate: '2026-04-22',
		compatibilityFlags: ['nodejs_compat'],
		outboundService: async (request: OutboundRequest) => {
			const url = new URL(request.url);
			wire.push({
				method: request.method,
				path: url.pathname,
				sha256: request.headers.has('x-amz-checksum-sha256'),
				crc32: request.headers.has('x-amz-checksum-crc32'),
				kind: [...url.searchParams.keys()].filter((x) => !x.toLowerCase().startsWith('x-amz-'))
			});
			assert.equal(url.hostname, 'fixture.compat.objectstorage.us-ashburn-1.oraclecloud.com');
			assert.equal(url.pathname, '/fixture-bucket/');
			const xml = (value: string, status = 200) =>
				new OutboundResponse(value, { status, headers: { 'content-type': 'application/xml' } });
			if (url.searchParams.has('versions')) {
				assert.equal(url.searchParams.get('prefix'), 'fixture-user/');
				return xml(
					`<ListVersionsResult><IsTruncated>false</IsTruncated>${
						deleted
							? ''
							: `<Version><Key>${key}</Key><VersionId>fixture-version</VersionId></Version>`
					}</ListVersionsResult>`
				);
			}
			if (url.searchParams.has('uploads'))
				return xml(
					'<ListMultipartUploadsResult><IsTruncated>false</IsTruncated></ListMultipartUploadsResult>'
				);
			assert.equal(request.method, 'POST');
			assert.ok(url.searchParams.has('delete'));
			const body = await request.text();
			assert.ok(body.includes(`<Key>${key}</Key>`));
			assert.ok(body.includes('<VersionId>fixture-version</VersionId>'));
			validChecksum =
				request.headers.get('x-amz-checksum-sha256') ===
					createHash('sha256').update(body).digest('base64') &&
				!request.headers.has('x-amz-checksum-crc32');
			if (!validChecksum) return xml('<Error><Code>InvalidRequest</Code></Error>', 400);
			deleted = true;
			return xml('<DeleteResult/>');
		}
	});
	try {
		const result = await (await worker.dispatchFetch('https://worker.example.test/cleanup')).json();
		assert.equal(
			validChecksum,
			true,
			`OCI requires SHA256, CRC32C or Content-MD5 for bulk deletion: ${JSON.stringify({ wire, result })}`
		);
		assert.deepEqual(result, { done: true });
		assert.equal(deleted, true);
	} finally {
		await worker.dispose();
	}
});
