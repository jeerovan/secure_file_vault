import { eq } from 'drizzle-orm';
import { NEON_JWKS } from '$env/static/private';
import type { AuthUser } from './auth';
import type { Db, Tx } from './db';
import { vaultState } from './db/schema';
import { authorizeRegisteredDevice } from './deviceAccess';
import { verifyRecoverySession, RecoveryFault } from './recoverySession';
import { json } from '@sveltejs/kit';
import { user } from './db/schema';
import { UserKeys } from './db/keys';

export async function withBootstrapWrite(
	db: Db | Tx,
	auth: AuthUser,
	action: (tx: Tx) => Promise<Response>
) {
	return db.transaction(async (tx) => {
		const [account] = await tx
			.select({ id: user[UserKeys.ID] })
			.from(user)
			.where(eq(user[UserKeys.ID], auth.userId!))
			.for('update');
		if (!account) return json({ success: 0, message: 1, reason: 'account_removed' });
		// A bootstrap request from an already registered device is not a new
		// registration. Recheck its live membership after acquiring the same
		// account lock used by removal/reset, before permitting any mutation.
		if (auth.deviceUuid && auth.vaultGeneration !== undefined) {
			const current = await authorizeRegisteredDevice(tx, auth, true);
			if (!current.authorized)
				return json({ success: 0, message: current.message, reason: current.reason });
		}
		const [state] = await tx
			.select()
			.from(vaultState)
			.where(eq(vaultState.userId, auth.userId!))
			.limit(1);
		if ((state?.generation ?? 'legacy') !== (auth.vaultGeneration ?? 'legacy')) {
			return json({ success: 0, message: 8, reason: 'vault_replaced' });
		}
		if (state?.ready === 0) return json({ success: 0, message: 17, reason: 'vault_reset_pending' });
		return action(tx);
	});
}

export async function authorizeVaultBootstrap(
	db: Db | Tx,
	auth: AuthUser,
	request: Request
): Promise<AuthUser> {
	if (!auth.authorized || !auth.userId) return auth;
	const deviceUuid = request.headers.get('device_uuid') || undefined;
	const decorated = {
		...auth,
		deviceUuid,
		vaultProtocol: request.headers.get('x-fife-vault-protocol') === '1' ? 1 : 0,
		requestedVaultGeneration: request.headers.get('x-fife-vault-generation') ?? undefined
	};
	const [state] = await db
		.select()
		.from(vaultState)
		.where(eq(vaultState.userId, auth.userId))
		.limit(1);
	if (!state) {
		if (!deviceUuid) return auth;
		const access = await authorizeRegisteredDevice(db, decorated);
		// Released clients may include their proposed UUID before registration.
		// Preserve legacy account bootstrap for those requests, while marking
		// known members so their write must revalidate membership under the lock.
		return access.authorized || access.reason === 'account_removed' ? access : auth;
	}
	if (deviceUuid) return authorizeRegisteredDevice(db, decorated);
	if (
		decorated.vaultProtocol !== 1 ||
		auth.localTesting ||
		request.headers.get('service') !== 'neon'
	) {
		return { ...auth, authorized: false, message: 18, reason: 'client_update_required' };
	}
	try {
		const session = await verifyRecoverySession({
			jwks: NEON_JWKS,
			cookie: request.headers.get('x-fife-session'),
			userId: auth.remoteAuthId!,
			email: auth.email!
		});
		if (session.hash !== state.initiatingSessionHash && session.createdAt <= state.resetAt) {
			return { ...auth, authorized: false, message: 8, reason: 'vault_replaced' };
		}
		if (!state.ready)
			return { ...auth, authorized: false, message: 17, reason: 'vault_reset_pending' };
		return { ...auth, vaultGeneration: state.generation };
	} catch (error) {
		// An unavailable auth service is retryable, never local deletion evidence.
		return {
			...auth,
			authorized: false,
			message: error instanceof RecoveryFault && error.code === 'sign_in_again' ? 18 : 19
		};
	}
}
