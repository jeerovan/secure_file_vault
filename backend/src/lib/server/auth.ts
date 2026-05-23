import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_KEY, NEON_JWKS } from '$env/static/private';
import { getUserByRemoteId as getUserByRemoteAuthId } from './db/api';
import { ErrorCode, UserKeys } from './db/keys';
import type { Db, Tx } from './db/index';
import * as jose from 'jose';
import type { KVNamespace } from '@cloudflare/workers-types';

export interface AuthUser {
	authorized: boolean;
	userId?: number;
	remoteAuthId?: string;
	email?: string;
	deviceUuid?: string;
	message?: number;
}

/**
 * Hashes the JWT to safely use as a KV key (KV keys have a 512 byte limit).
 */
async function hashToken(token: string): Promise<string> {
	const msgUint8 = new TextEncoder().encode(token);
	const hashBuffer = await crypto.subtle.digest('SHA-256', msgUint8);
	const hashArray = Array.from(new Uint8Array(hashBuffer));
	return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Extracts and validates the Bearer token from the request.
 * Caches successful validations in Cloudflare KV until the token expires.
 */
export async function requireAuth(
	db: Db | Tx,
	request: Request,
	kv: KVNamespace // Pass the bound KV from event.platform?.env
): Promise<AuthUser> {
	const authHeader = request.headers.get('authorization');
	const device_uuid = request.headers.get('device_uuid') || undefined;

	if (!authHeader?.startsWith('Bearer ')) {
		return { authorized: false, message: ErrorCode.UNAUTHORIZED };
	}

	const token = authHeader.split(' ')[1];
	const cacheKey = `auth:${await hashToken(token)}`;

	// 1. Check KV Cache First
	if (kv) {
		const cachedAuth = await kv.get<AuthUser>(cacheKey, 'json');
		if (cachedAuth) {
			cachedAuth.deviceUuid = device_uuid;
			return cachedAuth;
		}
	}

	const serviceHeader = request.headers.get('service');
	let authResult: AuthUser;
	let expirationSeconds: number | undefined;

	if (serviceHeader == 'neon') {
		try {
			const JWKS = jose.createRemoteJWKSet(new URL(NEON_JWKS));
			const { payload } = await jose.jwtVerify(token, JWKS);

			const userId = payload['sub']!;
			const email = payload['email']! as string;
			expirationSeconds = payload['exp']; // Extract exp for KV TTL

			const userEntry = await getUserByRemoteAuthId(db, userId, email);

			if (!userEntry) {
				return {
					authorized: false,
					remoteAuthId: userId,
					email: email,
					message: ErrorCode.NO_USER
				};
			}

			authResult = {
				authorized: true,
				remoteAuthId: userId,
				email: email,
				deviceUuid: device_uuid,
				userId: userEntry?.[UserKeys.ID]
			};
		} catch (err) {
			console.log(err);
			return { authorized: false, message: ErrorCode.UNAUTHORIZED };
		}
	} else {
		const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
		const {
			data: { user },
			error: authError
		} = await supabase.auth.getUser(token);

		if (authError || !user || !user.email) {
			return { authorized: false, message: ErrorCode.UNAUTHORIZED };
		}

		const userEntry = await getUserByRemoteAuthId(db, user.id);

		if (!userEntry) {
			return {
				authorized: false,
				remoteAuthId: user.id,
				email: user.email,
				message: ErrorCode.NO_USER
			};
		}

		authResult = {
			authorized: true,
			remoteAuthId: user.id,
			email: user.email,
			deviceUuid: device_uuid,
			userId: userEntry?.[UserKeys.ID]
		};

		// Extract expiration synchronously since Supabase remote verify succeeded
		try {
			const decoded = jose.decodeJwt(token);
			expirationSeconds = decoded.exp;
		} catch (err) {
			console.log('Failed to decode Supabase JWT', err);
		}
	}

	// 2. Write to Cloudflare KV Cache
	if (kv && authResult.authorized && expirationSeconds) {
		const currentUnix = Math.floor(Date.now() / 1000);

		// Cloudflare KV requires a minimum TTL of 60 seconds
		if (expirationSeconds - currentUnix >= 60) {
			await kv.put(cacheKey, JSON.stringify(authResult), {
				expiration: expirationSeconds
			});
		}
	}

	return authResult;
}
