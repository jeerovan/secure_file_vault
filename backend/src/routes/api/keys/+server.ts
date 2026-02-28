import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { db } from '$lib/server/db'; // your drizzle db instance
import { user } from '$lib/server/db/schema';
import { eq } from 'drizzle-orm';

// ---------------------------------------------------
// GET /api/user-keys
// Returns keys for the currently authenticated user
// ---------------------------------------------------
export const GET: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	const result = db
		.select({
			id: user[1],
			cipher: user[5],
			nonce: user[6]
		})
		.from(user)
		.where(eq(user[1], authUser.id))
		.get();

	if (!result) {
		return json({ status: 0, error: 'User not found' });
	}

	return json({ status: 1, data: result });
};

// ---------------------------------------------------
// POST /api/user-keys
// ---------------------------------------------------
export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);

	let body: { cipher?: string; nonce?: string };
	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: 'Invalid JSON body' });
	}

	const { cipher, nonce } = body;

	if (!cipher || !nonce) {
		return json({ status: 0, error: 'Missing required fields: cipher, nonce' });
	}

	if (authUser.email === 'fife@jeerovan.com') {
		return json({ status: 1 });
	}

	const result = await db.insert(user).values({
		1: authUser.id,
		4: authUser.email,
		5: cipher,
		6: nonce
	});

	return json({ status: 1, data: result });
};
