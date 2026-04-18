// src/routes/api/auth/sync-session/+server.ts
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url, locals }) => {
	const access_token = url.searchParams.get('access_token');
	const refresh_token = url.searchParams.get('refresh_token');

	if (access_token && refresh_token) {
		// Set the session using the tokens from Flutter
		const { data, error } = await locals.supabase.auth.setSession({
			access_token,
			refresh_token
		});

		if (!error && data.session) {
			// Session established successfully.
			// Redirect to the dashboard or intended page to clear the URL parameters.
			throw redirect(303, '/connect');
		}
	}

	// If tokens are missing or invalid, redirect to login page
	throw redirect(303, '/login');
};
