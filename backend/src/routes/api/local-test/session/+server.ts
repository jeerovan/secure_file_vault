import { json } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { getDb } from '$lib/server/db';
import { ErrorCode } from '$lib/server/db/keys';
import { getLocalTestIdentity } from '$lib/server/localTest';
import { createLocalTestSession } from '$lib/server/localTestSession';

export const POST: RequestHandler = async ({ request, platform }) => {
	const reply = (body: Record<string, unknown>) =>
		json(body, { headers: { 'Cache-Control': 'no-store' } });
	if (!dev || request.headers.get('service') !== 'local-test')
		return reply({ success: 0, message: ErrorCode.UNAUTHORIZED });
	const auth = await requireAuth(getDb(platform), request, platform?.env.FIFE_AUTH_CACHE);
	if (
		!auth.localTesting ||
		(!auth.authorized && auth.message !== ErrorCode.NO_USER) ||
		!auth.remoteAuthId ||
		!auth.email
	)
		return reply({ success: 0, message: ErrorCode.UNAUTHORIZED });
	const identity = getLocalTestIdentity(env);
	if (!identity || identity.remoteAuthId !== auth.remoteAuthId || identity.email !== auth.email)
		return reply({ success: 0, message: ErrorCode.UNAUTHORIZED });
	return reply({
		success: 1,
		data: {
			...(await createLocalTestSession(identity)),
			user: { id: identity.remoteAuthId, email: identity.email }
		}
	});
};
