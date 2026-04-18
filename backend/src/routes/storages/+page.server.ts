// src/routes/dashboard/+page.server.ts (adjust path to your actual route)
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, locals }) => {
	// 1. (Optional but recommended) Verify the user is authenticated
	/* const { data: { session } } = await locals.supabase.auth.getSession();
    if (!session) {
        throw redirect(303, '/login');
    } */

	// 2. Use SvelteKit's internal fetch.
	// It automatically forwards the user's auth cookies to your API.
	const response = await fetch('http://192.168.31.225:5173/api/storages');
	const result = await response.json();

	let storageProviders = [];
	if (result.success === 1) {
		storageProviders = result.data.filter((provider: any) => provider.title !== 'FiFe');
	}

	// 3. Return the data so it becomes available in +page.svelte
	return {
		storageProviders
	};
};
