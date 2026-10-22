import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireBootstrapAuth as requireAuth } from '$lib/server/auth';
import { env } from '$env/dynamic/private';
import { recoveryAvailable } from '$lib/server/recoveryAvailability';
import { ErrorCode, UserKeys } from '$lib/server/db/keys';
import { addUser, getUser } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { supportsVaultSession } from '$lib/server/requestSession';
import { withBootstrapWrite } from '$lib/server/vaultBootstrap';
import { user as accounts } from '$lib/server/db/schema';
import { eq } from 'drizzle-orm';

export const GET: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
	}
	if (!authUser.userId) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	const user = await getUser(db, authUser.userId);
	if (!user) {
		return json({ success: 0, message: ErrorCode.NO_USER });
	}
	const missingKeys = user[UserKeys.CIPHER] === null && user[UserKeys.NONCE] === null;
	if (missingKeys && request.headers.get('x-fife-recovery-protocol') !== '2')
		return json({ success: 0, message: 18, reason: 'client_update_required' });

	return json(
		{
			success: 1,
			data: {
				cipher: user[UserKeys.CIPHER],
				nonce: user[UserKeys.NONCE],
				key_state: missingKeys ? 'missing' : 'present',
				vault_generation: authUser.vaultGeneration ?? 'legacy',
				recovery_reset_available:
					(await recoveryAvailable(db, env, authUser.email)) &&
					supportsVaultSession(authUser, request) &&
					request.headers.get('x-fife-recovery-protocol') === '2'
			}
		},
		{ headers: { 'Cache-Control': 'no-store' } }
	);
};

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const kv = platform?.env.FIFE_AUTH_CACHE;
	const authUser = await requireAuth(db, request, kv!);
	if (!authUser.authorized && authUser.message !== ErrorCode.NO_USER) {
		return json({ success: 0, message: authUser.message, reason: authUser.reason });
	}
	let body: { cipher?: string; nonce?: string; expectedGeneration?: string };
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	if (!body || typeof body !== 'object' || Array.isArray(body))
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	const { cipher, nonce } = body;

	if (typeof cipher !== 'string' || !cipher || typeof nonce !== 'string' || !nonce) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	if (authUser.authorized) {
		return withBootstrapWrite(db, authUser, async (tx) => {
			const existingUser = await getUser(tx, authUser.userId!);
			if (existingUser?.[UserKeys.CIPHER] === cipher && existingUser[UserKeys.NONCE] === nonce)
				return json({ success: 1 });
			if (existingUser?.[UserKeys.CIPHER] === null && existingUser[UserKeys.NONCE] === null) {
				if (request.headers.get('x-fife-recovery-protocol') !== '2')
					return json({ success: 0, message: 18, reason: 'client_update_required' });
				if (body.expectedGeneration !== authUser.vaultGeneration)
					return json({ success: 0, message: 15, reason: 'key_setup_conflict' });
				await tx
					.update(accounts)
					.set({ [UserKeys.CIPHER]: cipher, [UserKeys.NONCE]: nonce })
					.where(eq(accounts[UserKeys.ID], authUser.userId!));
				return json({ success: 1 });
			}
			return json({
				success: 0,
				message: ErrorCode.INVALID_DATA,
				...(request.headers.get('x-fife-recovery-protocol') === '2'
					? { reason: 'key_setup_conflict' }
					: {})
			});
		});
	}

	const result = await addUser(db, authUser.remoteAuthId!, authUser.email!, cipher, nonce);
	if (!result)
		return json({ success: 0, message: ErrorCode.INVALID_DATA, reason: 'key_setup_conflict' });

	return json({ success: 1, data: result });
};
