export class RecoveryFault extends Error {
	constructor(readonly code: string) {
		super(code);
	}
}

export interface RecoverySession {
	userId: string;
	email: string;
	createdAt: number;
	expiresAt: number;
	hash: string;
}

export async function recoveryHash(value: string): Promise<string> {
	const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
	return Array.from(new Uint8Array(bytes), (value) => value.toString(16).padStart(2, '0')).join('');
}

export function neonSessionUrl(jwks: string): URL {
	const url = new URL(jwks);
	const suffix = '/.well-known/jwks.json';
	if (
		url.protocol !== 'https:' ||
		url.username ||
		url.password ||
		!url.pathname.endsWith(suffix) ||
		url.search ||
		url.hash
	) {
		throw new RecoveryFault('recovery_unavailable');
	}
	url.pathname = `${url.pathname.slice(0, -suffix.length)}/get-session`;
	url.searchParams.set('disableCookieCache', 'true');
	return url;
}

/** The cookie is verified by Neon, never decoded or trusted as client claims. */
export async function verifyRecoverySession(options: {
	jwks: string;
	cookie: string | null;
	userId: string;
	email: string;
	now?: number;
	fetcher?: typeof fetch;
}): Promise<RecoverySession> {
	const { cookie } = options;
	if (!cookie || cookie.length > 4096 || /[\s;,\r\n]/.test(cookie)) {
		throw new RecoveryFault('sign_in_again');
	}
	const url = neonSessionUrl(options.jwks);
	let response: Response;
	try {
		response = await (options.fetcher ?? fetch)(url, {
			headers: {
				Cookie: `__Secure-neon-auth.session_token=${cookie}`,
				'Cache-Control': 'no-cache'
			},
			// Workerd supports manual/follow only. Reject non-2xx below without
			// forwarding the session cookie to any redirect destination.
			redirect: 'manual',
			signal: AbortSignal.timeout(10_000)
		});
	} catch {
		throw new RecoveryFault('session_unavailable');
	}
	if (response.status === 401 || response.status === 403) throw new RecoveryFault('sign_in_again');
	if (!response.ok) throw new RecoveryFault('session_unavailable');
	let data;
	try {
		const body = await response.text();
		if (body.length > 65536) throw new Error();
		data = JSON.parse(body);
	} catch {
		throw new RecoveryFault('session_unavailable');
	}
	const session = data?.session;
	const account = data?.user;
	const createdAt = typeof session?.createdAt === 'string' ? Date.parse(session.createdAt) : NaN;
	const expiresAt = typeof session?.expiresAt === 'string' ? Date.parse(session.expiresAt) : NaN;
	const now = options.now ?? Date.now();
	if (
		!session ||
		!account ||
		account.id !== options.userId ||
		session.userId !== options.userId ||
		account.email?.toLowerCase() !== options.email.toLowerCase() ||
		account.emailVerified !== true ||
		!Number.isFinite(createdAt) ||
		!Number.isFinite(expiresAt) ||
		createdAt > now ||
		expiresAt <= now
	) {
		throw new RecoveryFault('sign_in_again');
	}
	return {
		userId: account.id,
		email: account.email,
		createdAt,
		expiresAt,
		hash: await recoveryHash(cookie)
	};
}

export function requireFreshRecoverySession(session: RecoverySession, now: number) {
	if (
		session.createdAt > now ||
		now - session.createdAt > 10 * 60_000 ||
		session.expiresAt <= now
	) {
		throw new RecoveryFault('sign_in_again');
	}
}

export function requireCurrentVaultSession(
	session: RecoverySession,
	state?: { resetAt: number; initiatingSessionHash: string | null }
) {
	if (state && session.hash !== state.initiatingSessionHash && session.createdAt <= state.resetAt) {
		throw new RecoveryFault('sign_in_again');
	}
}
