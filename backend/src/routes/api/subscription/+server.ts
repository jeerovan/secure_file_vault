import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { syncPlanExpiry, updatePlanExpiryFromWebhook } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { REVENUECAT_WEBHOOK_SECRET } from '$env/static/private';

export const GET: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	const authUser = await requireAuth(db, request);
	if (!authUser.authorized) {
		return json({ success: 0, message: authUser.message });
	}
	syncPlanExpiry(db, authUser.userId!, authUser.supabaseId!); // no wait
	return json({ success: 1 });
};

export const POST: RequestHandler = async ({ request, platform }) => {
	const db = getDb(platform);
	try {
		// 1. Verify Authorization Header
		const authHeader = request.headers.get('authorization');

		// Define the expected token (e.g., 'Bearer my_super_secret_token')
		const expectedAuth = REVENUECAT_WEBHOOK_SECRET;

		if (!authHeader || authHeader !== expectedAuth) {
			// Reject unauthorized requests
			return json({ error: 'Unauthorized' }, { status: 401 });
		}

		// 2. Parse the Event Payload
		const body = await request.json();

		// RevenueCat sends the payload wrapped in an `event` object
		const { event } = body;

		if (!event) {
			return json({ error: 'Bad Request: Missing event data' }, { status: 400 });
		}

		const { expiration_at_ms, original_app_user_id } = event;

		// 3. Process the Data (Update your database)
		// Ensure you handle this robustly, perhaps in a try/catch if interacting with a DB
		await updatePlanExpiryFromWebhook(db, original_app_user_id, expiration_at_ms);

		// 4. Return a Success Response
		// RevenueCat expects a 200 OK status code. If it doesn't receive this,
		// it will retry up to 5 times.
		return json({ success: true, message: 'Webhook processed successfully' }, { status: 200 });
	} catch (error) {
		console.error('Error processing RevenueCat webhook:', error);
		// It's generally best to return a 500 if your server fails, so RevenueCat knows to retry
		return json({ error: 'Internal Server Error' }, { status: 500 });
	}
};
