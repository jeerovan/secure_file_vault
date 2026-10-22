import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { Miniflare } from 'miniflare';

test('production compilation rejects local sign-in before touching identity or SQL', async () => {
	const route = new URL('../src/routes/api/local-test/session/+server.ts', import.meta.url)
		.pathname;
	const result = await build({
		stdin: {
			contents: `import { POST } from ${JSON.stringify(route)};
export default { fetch(request) { return POST({ request, platform: undefined }); } };`,
			resolveDir: process.cwd(),
			sourcefile: 'local-session-production-test.ts',
			loader: 'ts'
		},
		bundle: true,
		write: false,
		format: 'esm',
		platform: 'browser',
		plugins: [
			{
				name: 'production-bindings',
				setup(build) {
					build.onResolve(
						{
							filter:
								/^(\$app\/environment|\$env\/dynamic\/private|\$lib\/server\/.*|@sveltejs\/kit)$/
						},
						(args) => ({ path: args.path, namespace: 'fixture' })
					);
					build.onLoad({ filter: /.*/, namespace: 'fixture' }, ({ path }) => {
						const modules: Record<string, string> = {
							'$app/environment': 'export const dev = false;',
							'$env/dynamic/private': 'export const env = { LOCAL_TEST_AUTH_ENABLED: "true" };',
							'@sveltejs/kit': 'export const json = (body, init) => Response.json(body, init);',
							'$lib/server/db/keys': 'export const ErrorCode = { UNAUTHORIZED: 14, NO_USER: 1 };',
							'$lib/server/auth':
								'export function requireAuth() { throw Error("Production must not enter local authentication"); }',
							'$lib/server/db':
								'export function getDb() { throw Error("Production must not open a local SQL session"); }',
							'$lib/server/localTest':
								'export function getLocalTestIdentity() { throw Error("Production must not resolve a local identity"); }',
							'$lib/server/localTestSession':
								'export function createLocalTestSession() { throw Error("Production must not issue local proof"); }'
						};
						assert.ok(modules[path]);
						return { contents: modules[path], loader: 'js' };
					});
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
		for (const service of ['local-test', 'neon']) {
			const response = await worker.dispatchFetch(
				'https://app.example.test/api/local-test/session',
				{
					method: 'POST',
					headers: { service, authorization: 'Bearer configured-local-token' },
					body: '{}'
				}
			);
			assert.deepEqual(await response.json(), { success: 0, message: 14 });
		}
	} finally {
		await worker.dispose();
	}
});
