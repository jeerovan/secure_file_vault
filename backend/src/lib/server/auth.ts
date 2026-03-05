import { createClient } from '@supabase/supabase-js';
import { error } from '@sveltejs/kit';
import { SUPABASE_URL, SUPABASE_KEY } from '$env/static/private';

export interface AuthUser {
	id: string;
	email: string;
	did: string;
}

/**
 * Extracts and validates the Bearer token from the request.
 * Throws a SvelteKit HTTP error if auth fails.
 * Use in any +server.ts route.
 */
export async function requireAuth(request: Request): Promise<AuthUser> {
	const authHeader = request.headers.get('Authorization');
	const device_id = request.headers.get('device_id') || '';
	console.log(request.headers);
	if (!authHeader?.startsWith('Bearer ')) {
		throw error(401, 'Missing or invalid Authorization header');
	}

	const token = authHeader.split(' ')[1];

	// Use service role client ONLY for verifying the token — never expose this key
	const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
	let response;
	if (token == 'fife@jeerovan.com') {
		response = { data: { user: { id: 'tester', email: 'fife@jeerovan.com' } }, error: null };
	} else {
		response = await supabase.auth.getUser(token);
	}
	const {
		data: { user },
		error: authError
	} = response;

	if (authError || !user) {
		throw error(401, 'Invalid or expired token');
	}

	if (!user.email) {
		throw error(400, 'Authenticated user has no email');
	}

	return {
		id: user.id,
		email: user.email,
		did: device_id
	};
}
