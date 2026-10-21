import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
// Read-only negotiation must precede any cloud initiation. An older backend
// returns 404 without leaving an ambiguous upload behind.
export const POST: RequestHandler = () =>
	json(
		{ success: 1, data: { protocol: 'managed-v1' } },
		{ headers: { 'Cache-Control': 'no-store' } }
	);
