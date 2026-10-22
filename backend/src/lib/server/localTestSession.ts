import { SignJWT, jwtVerify } from 'jose';
import type { LocalTestIdentity } from './localTest';
import { recoveryHash, RecoveryFault, type RecoverySession } from './recoverySession';

const issuer = 'fife-local-auth';
const audience = 'fife-vault-session';
const lifetimeSeconds = 30 * 24 * 60 * 60;
const sessionPrefix = 'fife-local.';

async function signingKey(identity: LocalTestIdentity) {
	return new Uint8Array(
		await crypto.subtle.digest(
			'SHA-256',
			new TextEncoder().encode(`fife-local-session-v1\0${identity.token}`)
		)
	);
}

/** A development identity provider replaces Neon; vault policy stays unchanged. */
export async function createLocalTestSession(identity: LocalTestIdentity, now = Date.now()) {
	const expires = Math.floor(now / 1000) + lifetimeSeconds;
	const token = await new SignJWT({ email: identity.email, createdAt: now })
		.setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
		.setIssuer(issuer)
		.setAudience(audience)
		.setSubject(identity.remoteAuthId)
		.setIssuedAt(Math.floor(now / 1000))
		.setExpirationTime(expires)
		.setJti(crypto.randomUUID())
		.sign(await signingKey(identity));
	return { sessionToken: sessionPrefix + token, expiresAt: expires * 1000 };
}

export async function verifyLocalTestSession(
	cookie: string | null,
	identity: LocalTestIdentity,
	now = Date.now()
): Promise<RecoverySession> {
	if (
		!cookie ||
		!cookie.startsWith(sessionPrefix) ||
		cookie.length > 4096 ||
		/[\s;,\r\n]/.test(cookie)
	)
		throw new RecoveryFault('sign_in_again');
	try {
		const { payload } = await jwtVerify(
			cookie.slice(sessionPrefix.length),
			await signingKey(identity),
			{
				algorithms: ['HS256'],
				issuer,
				audience,
				currentDate: new Date(now)
			}
		);
		if (
			payload.sub !== identity.remoteAuthId ||
			typeof payload.email !== 'string' ||
			payload.email.toLowerCase() !== identity.email.toLowerCase() ||
			!Number.isSafeInteger(payload.createdAt) ||
			(payload.createdAt as number) > now ||
			typeof payload.exp !== 'number' ||
			payload.exp * 1000 <= now
		)
			throw new RecoveryFault('sign_in_again');
		return {
			userId: identity.remoteAuthId,
			email: identity.email,
			createdAt: payload.createdAt as number,
			expiresAt: payload.exp * 1000,
			hash: await recoveryHash(cookie)
		};
	} catch {
		throw new RecoveryFault('sign_in_again');
	}
}
