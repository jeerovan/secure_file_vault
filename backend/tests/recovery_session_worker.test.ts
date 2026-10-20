import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { transform } from 'esbuild';
import { Miniflare, type Request as OutboundRequest, Response as OutboundResponse } from 'miniflare';

const now = Date.parse('2026-10-19T12:00:00Z');
const session = {
	session: {
		userId: 'fixture-user',
		createdAt: new Date(now - 60_000).toISOString(),
		expiresAt: new Date(now + 60_000).toISOString()
	},
	user: { id: 'fixture-user', email: 'fixture@example.test', emailVerified: true }
};

async function workerSession(status: number, body: string, headers: Record<string, string> = {}) {
	const source = await readFile(
		new URL('../src/lib/server/recoverySession.ts', import.meta.url),
		'utf8'
	);
	const { code } = await transform(source, { loader: 'ts', format: 'esm', target: 'es2022' });
	let trustedRequests = 0;
	let redirectedRequests = 0;
	const worker = new Miniflare({
		modules: true,
		compatibilityDate: '2024-04-22',
		compatibilityFlags: ['nodejs_compat'],
		// Return upstream responses directly so workerd owns redirect handling.
		// Miniflare's fetchMock bridge follows redirects in its Node fetch first.
		outboundService(request: OutboundRequest) {
			const url = new URL(request.url);
			if (url.origin !== 'https://auth.example.test') {
				redirectedRequests++;
				return OutboundResponse.json(session);
			}
			trustedRequests++;
			assert.equal(url.pathname + url.search, '/neondb/auth/get-session?disableCookieCache=true');
			assert.equal(request.method, 'GET');
			assert.equal(
				request.headers.get('cookie'),
				'__Secure-neon-auth.session_token=fixture-cookie'
			);
			return new OutboundResponse(body, { status, headers });
		},
		script: `${code}
export default {
  async fetch() {
    try {
      const session = await verifyRecoverySession({
        jwks: 'https://auth.example.test/neondb/auth/.well-known/jwks.json',
        cookie: 'fixture-cookie', userId: 'fixture-user',
        email: 'fixture@example.test', now: ${now}
      });
      return Response.json({ verified: true, userId: session.userId, hash: session.hash });
    } catch (error) {
      return Response.json({ verified: false, error: error.code ?? 'unexpected_error' });
    }
  }
};`
	});
	try {
		const response = await worker.dispatchFetch('http://fixture.test');
		const result = await response.json();
		assert.equal(trustedRequests, 1, 'The trusted endpoint must verify the session exactly once');
		assert.equal(redirectedRequests, 0, 'No request may reach the redirect destination');
		return result;
	} finally {
		await worker.dispose();
	}
}

test('Worker native fetch verifies an uncached Neon session', { timeout: 30_000 }, async () => {
	assert.deepEqual(await workerSession(200, JSON.stringify(session)), {
		verified: true,
		userId: 'fixture-user',
		hash: createHash('sha256').update('fixture-cookie').digest('hex')
	});
});

test(
	'Worker rejects redirects without forwarding the session cookie',
	{ timeout: 30_000 },
	async () => {
		assert.deepEqual(
			await workerSession(302, '', { location: 'https://untrusted.example.test/session' }),
			{ verified: false, error: 'session_unavailable' }
		);
	}
);

test('Worker preserves fail-closed session failure handling', { timeout: 30_000 }, async () => {
	for (const [status, body, error] of [
		[401, '', 'sign_in_again'],
		[503, '', 'session_unavailable'],
		[200, '<html>Unavailable</html>', 'session_unavailable'],
		[200, 'null', 'sign_in_again']
	] as const) {
		assert.deepEqual(await workerSession(status, body), { verified: false, error });
	}
});
