import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireBootstrapAuth as requireAuth } from '$lib/server/auth';
import { env } from '$env/dynamic/private';
import { recoveryAvailable } from '$lib/server/recoveryAvailability';
import { ErrorCode, UserKeys } from '$lib/server/db/keys';
import { addUser, getUser } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';

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

	return json(
		{
			success: 1,
			data: {
				cipher: user[UserKeys.CIPHER],
				nonce: user[UserKeys.NONCE],
				vault_generation: authUser.vaultGeneration ?? 'legacy',
				recovery_reset_available:
					(await recoveryAvailable(db, env, authUser.email)) &&
					request.headers.get('service') === 'neon' &&
					!authUser.localTesting
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
	let body: { cipher?: string; nonce?: string };
	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { cipher, nonce } = body;

	if (!cipher || !nonce) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	if (authUser.authorized) {
		const existingUser = authUser.userId ? await getUser(db, authUser.userId) : undefined;
		if (existingUser?.[UserKeys.CIPHER] === cipher && existingUser[UserKeys.NONCE] === nonce) {
			return json({ success: 1 });
		}
		return json({ success: 0, message: ErrorCode.INVALID_DATA });
	}

	const result = await addUser(db, authUser.remoteAuthId!, authUser.email!, cipher, nonce);

	return json({ success: 1, data: result });
};
