import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
// Read-only negotiation must precede any cloud initiation. An older backend
// returns 404 without leaving an ambiguous upload behind.
export const POST: RequestHandler = () =>
	json(
		env.MANAGED_UPLOADS_ENABLED === 'true'
			? { success: 1, data: { protocol: 'managed-v1' } }
			: { success: 0, message: 'managed_uploads_disabled' },
		{
			status: env.MANAGED_UPLOADS_ENABLED === 'true' ? 200 : 404,
			headers: { 'Cache-Control': 'no-store' }
		}
	);
