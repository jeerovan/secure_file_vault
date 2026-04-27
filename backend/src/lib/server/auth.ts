import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_KEY, NEON_JWKS } from '$env/static/private';
import { getUserByRemoteId as getUserByRemoteAuthId } from './db/api';
import { ErrorCode, UserKeys } from './db/keys';
import type { Db, Tx } from './db/index';
import * as jose from 'jose';

export interface AuthUser {
	authorized: boolean;
	userId?: number;
	remoteAuthId?: string;
	email?: string;
	deviceUuid?: string;
	message?: number;
}

/**
 * Extracts and validates the Bearer token from the request.
 * Throws a SvelteKit HTTP error if auth fails.
 * Use in any +server.ts route.
 */
export async function requireAuth(db: Db | Tx, request: Request): Promise<AuthUser> {
	const authHeader = request.headers.get('authorization');
	const device_uuid = request.headers.get('device_uuid') || undefined;
	if (!authHeader?.startsWith('Bearer ')) {
		return { authorized: false, message: ErrorCode.UNAUTHORIZED };
	}

	const token = authHeader.split(' ')[1];

	const serviceHeader = request.headers.get('service');
	if (serviceHeader == 'neon') {
		try {
			// 2. Validate the JWT using Neon's JWKS Endpoint
			const JWKS = jose.createRemoteJWKSet(new URL(NEON_JWKS));
			const { payload } = await jose.jwtVerify(token, JWKS);
			// 3. Success, fetch user
			const userId = payload['sub']!;
			const email = payload['email']! as string;
			const userEntry = await getUserByRemoteAuthId(db, userId, email);

			if (!userEntry) {
				return { authorized: false, message: ErrorCode.UNAUTHORIZED };
			}

			return {
				authorized: true,
				remoteAuthId: userId,
				email: userEntry?.[UserKeys.EMAIL],
				deviceUuid: device_uuid,
				userId: userEntry?.[UserKeys.ID]
			};
		} catch (err) {
			console.log(err);
			return { authorized: false, message: ErrorCode.UNAUTHORIZED };
		}
	} else {
		// Use service role client ONLY for verifying the token — never expose this key
		const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
		const {
			data: { user },
			error: authError
		} = await supabase.auth.getUser(token);

		if (authError || !user) {
			return { authorized: false, message: ErrorCode.UNAUTHORIZED };
		}

		if (!user.email) {
			return { authorized: false, message: ErrorCode.UNAUTHORIZED };
		}

		const userEntry = await getUserByRemoteAuthId(db, user.id);

		if (!userEntry) {
			return { authorized: false, message: ErrorCode.UNAUTHORIZED };
		}

		return {
			authorized: true,
			remoteAuthId: user.id,
			email: user.email,
			deviceUuid: device_uuid,
			userId: userEntry?.[UserKeys.ID]
		};
	}
}
