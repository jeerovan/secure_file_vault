import { StorageProvider } from './db/keys';

export const RESET_WAIT_MS = 15 * 60_000;
const legacyB2LifetimeMs = 24 * 60 * 60_000;
const legacyS3LifetimeMs = 60 * 60_000;
const legacyClockGraceMs = 60_000;

/** Set only after every issuer records capabilities under the account lock. */
export function uploadAccountingSince(value: string | undefined): number | undefined {
	if (!value || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)) return undefined;
	const timestamp = Date.parse(value);
	if (!Number.isSafeInteger(timestamp) || timestamp < 0) return undefined;
	const canonical = new Date(timestamp).toISOString();
	return value === canonical || value === canonical.replace('.000Z', 'Z') ? timestamp : undefined;
}

export function resetNotBefore(input: {
	now: number;
	providerIds: number[];
	capabilityExpiresAt?: number;
	uploadAccountingSince?: number;
}): number {
	const { now, providerIds, capabilityExpiresAt } = input;
	if (!providerIds.length) return now;
	const legacyLifetimeMs = providerIds.some((id) =>
		[StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(id)
	)
		? legacyB2LifetimeMs
		: legacyS3LifetimeMs;
	const since = input.uploadAccountingSince;
	// Missing, invalid or future cutovers cannot establish complete accounting.
	// A known cutover drains historical grants once, instead of restarting their
	// entire lifetime on every reset. Native grants issued later remain recorded.
	const lastUnaccountedIssuance =
		typeof since === 'number' && Number.isSafeInteger(since) && since >= 0 && since <= now
			? since
			: now;
	return Math.max(
		now + RESET_WAIT_MS,
		lastUnaccountedIssuance + legacyLifetimeMs + legacyClockGraceMs,
		// Issuance records expiry after the provider returns, conservatively
		// covering signing/authorization time without adding another minute.
		capabilityExpiresAt ?? 0
	);
}
