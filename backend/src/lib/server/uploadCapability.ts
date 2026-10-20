import { sql } from 'drizzle-orm';
import type { AuthUser } from './auth';
import type { Db, Tx } from './db';
import { vaultUploadCapability } from './db/schema';
import { withDeviceWrite } from './deviceAccess';

export const LEGACY_B2_UPLOAD_EXPIRY_SECONDS = 86_400;

/** Do not expose an authorization until its expiry commits under the reset lock. */
export async function withUploadAuthorization(
	db: Db | Tx,
	auth: AuthUser,
	expiresInSeconds: number,
	issue: (tx: Tx, current: AuthUser) => Promise<Response>,
	clock = Date.now
) {
	if (!Number.isSafeInteger(expiresInSeconds) || expiresInSeconds <= 0)
		throw new Error('Invalid upload authorization lifetime');
	return withDeviceWrite(db, auth, async (tx, current) => {
		const response = await issue(tx, current);
		const envelope = await response.clone().json();
		if (response.ok && envelope?.success === 1) {
			// Record after signing/provider issuance, conservatively covering the
			// time spent obtaining a legacy native token as well.
			const expiresAt = clock() + expiresInSeconds * 1000;
			if (!Number.isSafeInteger(expiresAt)) throw new Error('Invalid upload expiry');
			await tx
				.insert(vaultUploadCapability)
				.values({
					userId: current.userId!,
					generation: current.vaultGeneration!,
					expiresAt
				})
				.onConflictDoUpdate({
					target: [vaultUploadCapability.userId, vaultUploadCapability.generation],
					set: { expiresAt: sql`greatest(${vaultUploadCapability.expiresAt}, ${expiresAt})` }
				});
		}
		return response;
	});
}
