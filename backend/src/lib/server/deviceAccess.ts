import { and, eq } from 'drizzle-orm';
import type { AuthUser } from './auth';
import type { Db, Tx } from './db';
import { ErrorCode, UserKeys, UserDeviceKeys } from './db/keys';
import { user, userDevice, vaultState } from './db/schema';
import { vaultObjectPrefix } from './recoveryStorage';
import { json } from '@sveltejs/kit';

export async function withDeviceWrite(
	db: Db | Tx,
	auth: AuthUser,
	action: (tx: Tx, current: AuthUser) => Promise<Response>
) {
	return db.transaction(async (tx) => {
		const access = await authorizeRegisteredDevice(tx, auth, true);
		if (!access.authorized)
			return json({ success: 0, message: access.message, reason: access.reason });
		return action(tx, access);
	});
}

export async function finalDeviceResponse(db: Db | Tx, auth: AuthUser, response: Response) {
	const access = await authorizeRegisteredDevice(db, auth);
	return access.authorized
		? response
		: json({ success: 0, message: access.message, reason: access.reason });
}

/** Identity-token caches must never grant access to a retired device. */
export async function authorizeRegisteredDevice(
	db: Db | Tx,
	auth: AuthUser,
	lock = false
): Promise<AuthUser> {
	if (!auth.authorized) return auth;
	if (!auth.userId || !auth.deviceUuid) {
		return { ...auth, authorized: false, message: ErrorCode.MISSING_FIELDS };
	}
	const accountQuery = db
		.select({ id: user[UserKeys.ID], remoteId: user[UserKeys.REMOTE_AUTH_ID] })
		.from(user)
		.where(eq(user[UserKeys.ID], auth.userId))
		.limit(1);
	const [account] = await (lock ? accountQuery.for('update') : accountQuery);
	if (!account) {
		return { ...auth, authorized: false, message: ErrorCode.NO_USER, reason: 'account_removed' };
	}
	const deviceQuery = db
		.select({ active: userDevice[UserDeviceKeys.ACTIVE] })
		.from(userDevice)
		.where(
			and(
				eq(userDevice[UserDeviceKeys.USER_ID], auth.userId),
				eq(userDevice[UserDeviceKeys.DEVICE_UUID], auth.deviceUuid)
			)
		)
		.limit(1);
	const [device] = await (lock ? deviceQuery.for('update') : deviceQuery);
	if (device?.active !== 1) {
		return { ...auth, authorized: false, message: ErrorCode.NO_DEVICE, reason: 'device_revoked' };
	}
	const [state] = await db
		.select()
		.from(vaultState)
		.where(eq(vaultState.userId, auth.userId))
		.limit(1);
	if (state && (auth.vaultProtocol !== 1 || auth.requestedVaultGeneration !== state.generation)) {
		return { ...auth, authorized: false, message: ErrorCode.NO_DEVICE, reason: 'vault_replaced' };
	}
	if (state?.ready === 0) {
		return { ...auth, authorized: false, message: 17, reason: 'vault_reset_pending' };
	}
	return {
		...auth,
		vaultGeneration: state?.generation ?? 'legacy',
		objectPrefix: vaultObjectPrefix(account.remoteId, state?.generation ?? 'legacy')
	};
}
