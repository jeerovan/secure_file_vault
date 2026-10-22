import assert from 'node:assert/strict';
import test from 'node:test';
import { resetNotBefore, uploadAccountingSince } from '../src/lib/server/recoveryWait';
import { StorageProvider as P } from '../src/lib/server/db/keys';

const now = Date.parse('2026-10-21T12:00:00Z');
const minute = 60_000;
const day = 24 * 60 * minute;

test('all providers use fifteen minutes after the historical capability drain', () => {
	for (const provider of Object.values(P))
		for (const expiresAt of [undefined, now - 1, now, now + 15 * minute])
			assert.equal(
				resetNotBefore({
					now,
					providerIds: [provider],
					capabilityExpiresAt: expiresAt,
					uploadAccountingSince: now - day - minute
				}),
				now + 15 * minute
			);
});

test('long recorded capabilities win without shortening or restarting their expiry', () => {
	const expiresAt = now + day;
	for (const provider of Object.values(P))
		assert.equal(
			resetNotBefore({
				now,
				providerIds: [provider],
				capabilityExpiresAt: expiresAt,
				uploadAccountingSince: 0
			}),
			expiresAt
		);
});

test('a recent known cutover retains only the remaining historical grant lifetime', () => {
	assert.equal(
		resetNotBefore({
			now,
			providerIds: [P.FIFE, P.S3],
			uploadAccountingSince: now - day + 20 * minute
		}),
		now + 21 * minute
	);
	assert.equal(
		resetNotBefore({ now, providerIds: [P.S3], uploadAccountingSince: now - 50 * minute }),
		now + 15 * minute
	);
});

test('unknown, malformed and future accounting dates retain historical containment', () => {
	for (const since of [undefined, -1, NaN, Infinity, now + 1, now + 0.5]) {
		assert.equal(
			resetNotBefore({ now, providerIds: [P.FIFE], uploadAccountingSince: since }),
			now + day + minute
		);
		assert.equal(
			resetNotBefore({ now, providerIds: [P.S3], uploadAccountingSince: since }),
			now + 61 * minute
		);
	}
});

test('empty storage does not invent a cloud waiting period', () => {
	assert.equal(resetNotBefore({ now, providerIds: [] }), now);
});

test('accounting configuration accepts only explicit valid UTC timestamps', () => {
	assert.equal(uploadAccountingSince('1970-01-01T00:00:00.000Z'), 0);
	assert.equal(uploadAccountingSince('2026-10-21T12:00:00Z'), now);
	for (const value of [
		undefined,
		'',
		'0',
		'yesterday',
		'2026-10-21',
		'2026-02-30T12:00:00Z',
		'2026-10-21T12:00:00+00:00',
		'1969-12-31T23:59:59Z'
	])
		assert.equal(uploadAccountingSince(value), undefined);
});
