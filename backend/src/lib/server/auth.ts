import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_KEY } from '$env/static/private';
import { getUserBySupabaseId } from './db/api';
import { ErrorCode, UserKeys } from './db/keys';
import type { Db, Tx } from './db/index';

export interface AuthUser {
	authorized: boolean;
	userId?: number;
	supabaseId?: string;
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

	const userEntry = await getUserBySupabaseId(db, user.id);

	return {
		authorized: true,
		supabaseId: user.id,
		email: user.email,
		deviceUuid: device_uuid,
		userId: userEntry?.[UserKeys.ID]
	};
}
