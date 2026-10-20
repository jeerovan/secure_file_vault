import assert from 'node:assert/strict';
import test from 'node:test';
import {
	neonSessionUrl,
	verifyRecoverySession,
	requireFreshRecoverySession
} from '../src/lib/server/recoverySession';

const now = Date.parse('2026-10-19T12:00:00Z');
const session = {
	session: {
		userId: 'fixture-user',
		createdAt: new Date(now - 60_000).toISOString(),
		expiresAt: new Date(now + 60_000).toISOString()
	},
	user: { id: 'fixture-user', email: 'fixture@example.test', emailVerified: true }
};
const options = {
	jwks: 'https://auth.example.test/neondb/auth/.well-known/jwks.json',
	cookie: 'fixture-cookie',
	userId: 'fixture-user',
	email: 'fixture@example.test',
	now
};

test('recovery verifies the actual uncached Neon session and hashes its opaque cookie', async () => {
	const verified = await verifyRecoverySession({
		...options,
		fetcher: async (url, init) => {
			assert.equal(
				String(url),
				'https://auth.example.test/neondb/auth/get-session?disableCookieCache=true'
			);
			assert.equal(
				new Headers(init?.headers).get('Cookie'),
				'__Secure-neon-auth.session_token=fixture-cookie'
			);
			assert.equal(init?.redirect, 'manual');
			return Response.json(session);
		}
	});
	assert.equal(verified.userId, 'fixture-user');
	assert.match(verified.hash, /^[a-f0-9]{64}$/);
	assert.doesNotThrow(() => requireFreshRecoverySession(verified, now));
	assert.throws(
		() => requireFreshRecoverySession({ ...verified, createdAt: now - 600_001 }, now),
		/sign_in_again/
	);
});

for (const [label, value] of Object.entries({
	missing: null,
	wrongUser: { ...session, user: { ...session.user, id: 'someone-else' } },
	wrongSessionUser: { ...session, session: { ...session.session, userId: 'someone-else' } },
	unverified: { ...session, user: { ...session.user, emailVerified: false } },
	wrongEmail: { ...session, user: { ...session.user, email: 'someone@example.test' } },
	expired: { ...session, session: { ...session.session, expiresAt: new Date(now).toISOString() } },
	future: {
		...session,
		session: { ...session.session, createdAt: new Date(now + 1).toISOString() }
	},
	malformed: { ...session, session: { ...session.session, createdAt: 'invalid' } }
})) {
	test(`recovery rejects ${label} session proof`, async () => {
		await assert.rejects(
			verifyRecoverySession({ ...options, fetcher: async () => Response.json(value) }),
			/sign_in_again/
		);
	});
}

test('transport/server failure is retryable and cannot authorize reset', async () => {
	await assert.rejects(
		verifyRecoverySession({ ...options, fetcher: async () => new Response('', { status: 503 }) }),
		/session_unavailable/
	);
	await assert.rejects(
		verifyRecoverySession({
			...options,
			fetcher: async () => {
				throw new Error('offline');
			}
		}),
		/session_unavailable/
	);
});

test('recovery never forwards a cookie to a client-selected or insecure auth URL', async () => {
	for (const url of [
		'http://auth.example.test/.well-known/jwks.json',
		'https://auth.example.test/other',
		'https://user:password@auth.example.test/.well-known/jwks.json',
		'https://auth.example.test/.well-known/jwks.json?redirect=1'
	]) {
		assert.throws(() => neonSessionUrl(url));
	}
	for (const cookie of ['', 'fixture; other=value', 'fixture\r\nX-Test: value']) {
		await assert.rejects(
			verifyRecoverySession({
				...options,
				cookie,
				fetcher: async () => {
					assert.fail('Invalid cookie must never reach the network');
				}
			}),
			/sign_in_again/
		);
	}
});
