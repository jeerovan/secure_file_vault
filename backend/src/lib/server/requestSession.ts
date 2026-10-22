import { dev } from '$app/environment';
import { env } from '$env/dynamic/private';
import { NEON_JWKS } from '$env/static/private';
import type { AuthUser } from './auth';
import { getLocalTestIdentity } from './localTest';
import { verifyLocalTestSession } from './localTestSession';
import { RecoveryFault, verifyRecoverySession } from './recoverySession';

export function supportsVaultSession(auth: AuthUser, request: Request) {
	const service = request.headers.get('service');
	return auth.localTesting ? dev && service === 'local-test' : service === 'neon';
}

/** Resolve authentication proof before entering the shared vault/reset policy. */
export async function verifyRequestSession(auth: AuthUser, request: Request) {
	if (!supportsVaultSession(auth, request)) throw new RecoveryFault('sign_in_again');
	const cookie = request.headers.get('x-fife-session');
	if (auth.localTesting) {
		const identity = dev ? getLocalTestIdentity(env) : null;
		if (
			!identity ||
			auth.remoteAuthId !== identity.remoteAuthId ||
			auth.email?.toLowerCase() !== identity.email.toLowerCase()
		)
			throw new RecoveryFault('sign_in_again');
		return verifyLocalTestSession(cookie, identity);
	}
	return verifyRecoverySession({
		jwks: NEON_JWKS,
		cookie,
		userId: auth.remoteAuthId!,
		email: auth.email!
	});
}
