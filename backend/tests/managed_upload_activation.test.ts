import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Miniflare } from 'miniflare';

test('managed-upload negotiation requires explicit activation and is never cached', async () => {
	const route = new URL('../src/routes/api/uploads/protocol/+server.ts', import.meta.url).pathname;
	const result = await build({
		stdin: {
			contents: `import { POST } from ${JSON.stringify(route)};
import { env } from '$env/dynamic/private';
export default {fetch(request) {
 env.MANAGED_UPLOADS_ENABLED = request.headers.get('fixture-activation') ?? undefined;
 return POST({request, platform: undefined});
}};`,
			resolveDir: process.cwd(),
			loader: 'ts'
		},
		bundle: true,
		write: false,
		format: 'esm',
		platform: 'browser',
		plugins: [
			{
				name: 'runtime-bindings',
				setup(build) {
					build.onResolve({ filter: /^(\$env\/dynamic\/private|@sveltejs\/kit)$/ }, (args) => ({
						path: args.path,
						namespace: 'fixture'
					}));
					build.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => ({
						contents:
							path === '$env/dynamic/private'
								? 'export const env = {};'
								: 'export const json = (body, init) => Response.json(body, init);',
						loader: 'js'
					}));
				}
			}
		]
	});
	const worker = new Miniflare({
		modules: true,
		compatibilityDate: '2026-04-22',
		script: result.outputFiles[0].text
	});
	try {
		for (const flag of [undefined, 'false', 'TRUE', 'true', 'false']) {
			const response = await worker.dispatchFetch('https://app.example.test/api/uploads/protocol', {
				method: 'POST',
				headers: flag === undefined ? {} : { 'fixture-activation': flag }
			});
			assert.equal(response.status, flag === 'true' ? 200 : 404);
			assert.equal(response.headers.get('cache-control'), 'no-store');
			assert.deepEqual(
				await response.json(),
				flag === 'true'
					? { success: 1, data: { protocol: 'managed-v1' } }
					: { success: 0, message: 'managed_uploads_disabled' }
			);
		}
	} finally {
		await worker.dispose();
	}
});
