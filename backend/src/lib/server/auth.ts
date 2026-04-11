import { createClient } from '@supabase/supabase-js';
import { error } from '@sveltejs/kit';
import { SUPABASE_URL, SUPABASE_KEY } from '$env/static/private';
import { db } from './db';
import { getUserBySupabaseId } from './db/api';
import { UserKeys } from './db/keys';

export interface AuthUser {
	userId?: number;
	supabaseId: string;
	email: string;
	deviceUuid: string;
}

/**
 * Extracts and validates the Bearer token from the request.
 * Throws a SvelteKit HTTP error if auth fails.
 * Use in any +server.ts route.
 */
export async function requireAuth(request: Request): Promise<AuthUser> {
	const authHeader = request.headers.get('Authorization');
	const device_uuid = request.headers.get('device_uuid') || '';
	if (!authHeader?.startsWith('Bearer ')) {
		throw error(401, 'Missing or invalid Authorization header');
	}

	const token = authHeader.split(' ')[1];

	// Use service role client ONLY for verifying the token — never expose this key
	const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
	const {
		data: { user },
		error: authError
	} = await supabase.auth.getUser(token);

	if (authError || !user) {
		throw error(401, 'Invalid or expired token');
	}

	if (!user.email) {
		throw error(400, 'Authenticated user has no email');
	}

	const userEntry = await getUserBySupabaseId(user.id);

	return {
		supabaseId: user.id,
		email: user.email,
		deviceUuid: device_uuid,
		userId: userEntry?.[UserKeys.ID]
	};
}
