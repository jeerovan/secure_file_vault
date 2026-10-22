import assert from 'node:assert/strict';
import test from 'node:test';
import { createLocalTestSession, verifyLocalTestSession } from '../src/lib/server/localTestSession';
import {
	recoveryHash,
	requireFreshRecoverySession,
	requireCurrentVaultSession
} from '../src/lib/server/recoverySession';

const identity = {
	token: 'fixture-secret',
	remoteAuthId: 'fixture-user',
	email: 'fixture@example.test'
};
const now = Date.parse('2026-10-21T12:00:00Z');

test('local sign-in issues distinct server-bound sessions with stable authentication time', async () => {
	const first = await createLocalTestSession(identity, now);
	const second = await createLocalTestSession(identity, now);
	assert.notEqual(first.sessionToken, second.sessionToken);
	const verified = await verifyLocalTestSession(first.sessionToken, identity, now + 60_000);
	assert.equal(verified.userId, identity.remoteAuthId);
	assert.equal(verified.email, identity.email);
	assert.equal(verified.createdAt, now);
	assert.equal(verified.expiresAt, first.expiresAt);
	assert.equal(verified.hash, await recoveryHash(first.sessionToken));
});

test('local proof rejects forgery, identity changes, malformed cookies and future sessions', async () => {
	const issued = await createLocalTestSession(identity, now);
	for (const other of [
		{ ...identity, token: 'other-secret' },
		{ ...identity, remoteAuthId: 'other-user' },
		{ ...identity, email: 'other@example.test' }
	]) {
		await assert.rejects(verifyLocalTestSession(issued.sessionToken, other, now), {
			code: 'sign_in_again'
		});
	}
	for (const cookie of [
		null,
		'',
		' ',
		'x'.repeat(4097),
		`${issued.sessionToken};`,
		'forged.session.proof'
	]) {
		await assert.rejects(verifyLocalTestSession(cookie, identity, now), { code: 'sign_in_again' });
	}
	const future = await createLocalTestSession(identity, now + 1);
	await assert.rejects(verifyLocalTestSession(future.sessionToken, identity, now), {
		code: 'sign_in_again'
	});
	await assert.rejects(verifyLocalTestSession(issued.sessionToken, identity, issued.expiresAt), {
		code: 'sign_in_again'
	});
});

test('local authentication obeys the same freshness and retired-session barriers', async () => {
	const issued = await createLocalTestSession(identity, now);
	const session = await verifyLocalTestSession(issued.sessionToken, identity, now);
	assert.doesNotThrow(() => requireFreshRecoverySession(session, now + 10 * 60_000));
	assert.throws(() => requireFreshRecoverySession(session, now + 10 * 60_000 + 1), {
		code: 'sign_in_again'
	});
	const state = { resetAt: now, initiatingSessionHash: 'another-device-session' };
	assert.throws(() => requireCurrentVaultSession(session, state), { code: 'sign_in_again' });
	assert.doesNotThrow(() =>
		requireCurrentVaultSession(session, { ...state, initiatingSessionHash: session.hash })
	);
	const newer = await createLocalTestSession(identity, now + 1);
	const current = await verifyLocalTestSession(newer.sessionToken, identity, now + 1);
	assert.doesNotThrow(() => requireCurrentVaultSession(current, state));
});
