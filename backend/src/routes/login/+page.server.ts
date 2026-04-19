import { fail, redirect } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { safeGetSession } }) => {
	// Check if the user is already authenticated
	const { session } = await safeGetSession();

	return {
		// Passing the session to the client so the UI can default to the "signedIn" step
		session
	};
};

export const actions: Actions = {
	sendOtp: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const email = formData.get('email') as string;

		if (!email || typeof email !== 'string') {
			return fail(400, {
				error: 'Please enter a valid email address.',
				email
			});
		}

		// Optional: Simulate testing delay just like your Flutter code
		if (email === 'test@example.com') {
			await new Promise((resolve) => setTimeout(resolve, 1000));
			return { success: true, email, step: 'otp' };
		}

		const { error } = await supabase.auth.signInWithOtp({
			email,
			options: {
				// Prevent Supabase from attempting to redirect via Magic Link,
				// forcing the 6-digit OTP code flow instead.
				shouldCreateUser: true
			}
		});

		if (error) {
			console.error('sendOtp server error:', error);
			return fail(500, {
				error: error.message || 'Failed to send OTP. Please try again.',
				email
			});
		}

		return { success: true, email, step: 'otp' };
	},

	verifyOtp: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const email = formData.get('email') as string;
		const otp = formData.get('otp') as string;

		if (!email || !otp) {
			return fail(400, {
				error: 'Both email and OTP are required.',
				email
			});
		}

		const {
			data: { session },
			error
		} = await supabase.auth.verifyOtp({
			email,
			token: otp,
			type: 'email'
		});

		if (error || !session) {
			console.error('verifyOtp server error:', error);
			return fail(401, {
				error: 'OTP verification failed. Please check the code and try again.',
				email
			});
		}

		// At this point, @supabase/ssr automatically sets the auth cookies
		// because of hooks.server.ts configuration.

		// TODO: We can perform ModelProfile and ModelItem database inserts here
		// securely on the server side using the authenticated user's ID: session.user.id

		// Redirect to the main app dashboard (File Explorer) upon successful sign in
		throw redirect(303, '/connect');
	},

	signout: async ({ locals: { supabase } }) => {
		await supabase.auth.signOut();

		// Redirect back to the sign-in page, clearing the state
		throw redirect(303, '/signin');
	}
};
