import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { and, eq, gt, desc } from 'drizzle-orm';
import { requireAuth } from './auth';
import { getDb } from './db';
import { recoveryReset, vaultState, user } from './db/schema';
import { UserKeys } from './db/keys';
import { RecoveryResetService } from './recoveryReset';
import { ProviderRecoveryStorage } from './recoveryStorage';
import { RecoveryFault, requireCurrentVaultSession } from './recoverySession';
import { recoveryAvailable } from './recoveryAvailability';
import { supportsVaultSession, verifyRequestSession } from './requestSession';
import { uploadAccountingSince } from './recoveryWait';

const reply = (data: Record<string, unknown>) =>
	json(data, { headers: { 'Cache-Control': 'no-store' } });

export async function recoveryRequest(
	request: Request,
	platform: App.Platform | undefined,
	action: 'prepare' | 'confirm' | 'status'
) {
	try {
		const db = getDb(platform);
		const auth = await requireAuth(db, request, platform?.env.FIFE_AUTH_CACHE);
		if (!auth.authorized || !auth.userId || !supportsVaultSession(auth, request)) {
			return reply({ success: 0, message: 14 });
		}
		if (request.headers.get('x-fife-vault-protocol') !== '1')
			throw new RecoveryFault('client_update_required');
		const session = await verifyRequestSession(auth, request);
		const service = new RecoveryResetService(
			db,
			auth.userId,
			session,
			new ProviderRecoveryStorage(),
			Date.now,
			uploadAccountingSince(env.RECOVERY_UPLOAD_ACCOUNTING_SINCE)
		);
		if (action === 'status') {
			const userId = auth.userId;
			return await db.transaction(async (tx) => {
				const [account] = await tx
					.select({
						id: user[UserKeys.ID],
						cipher: user[UserKeys.CIPHER],
						nonce: user[UserKeys.NONCE]
					})
					.from(user)
					.where(eq(user[UserKeys.ID], userId))
					.for('share');
				if (!account) throw new RecoveryFault('sign_in_again');
				const scopedService = new RecoveryResetService(
					tx,
					userId,
					session,
					new ProviderRecoveryStorage()
				);
				let operationId = new URL(request.url).searchParams.get('operation_id');
				const [state] = await tx
					.select()
					.from(vaultState)
					.where(eq(vaultState.userId, userId))
					.limit(1);
				requireCurrentVaultSession(session, state);
				if (!operationId && state?.ready === 0) {
					const [pending] = await tx
						.select({ id: recoveryReset.id })
						.from(recoveryReset)
						.where(
							and(
								eq(recoveryReset.userId, userId),
								eq(recoveryReset.nextGeneration, state.generation),
								eq(recoveryReset.phase, 'cleanup_pending')
							)
						)
						.limit(1);
					operationId = pending?.id ?? null;
				}
				const operation = operationId ? await scopedService.status(operationId) : null;
				const [preparation] = await tx
					.select({ expiresAt: recoveryReset.expiresAt })
					.from(recoveryReset)
					.where(
						and(
							eq(recoveryReset.userId, userId),
							eq(recoveryReset.phase, 'prepared'),
							gt(recoveryReset.expiresAt, Date.now())
						)
					)
					.orderBy(desc(recoveryReset.expiresAt))
					.limit(1);
				return reply({
					success: 1,
					data: {
						available: await recoveryAvailable(tx, env, auth.email),
						generation: state?.generation ?? 'legacy',
						key_setup_protocol: 2,
						vault_ready: state?.ready !== 0,
						key_state: account.cipher === null && account.nonce === null ? 'missing' : 'present',
						pendingConfirmation: !!preparation,
						confirmationExpiresAt: preparation?.expiresAt ?? null,
						operation
					}
				});
			});
		}
		let body;
		try {
			body = await request.json();
		} catch {
			throw new RecoveryFault('invalid_reset_request');
		}
		if (!body || typeof body !== 'object' || Array.isArray(body))
			throw new RecoveryFault('invalid_reset_request');
		if (action === 'prepare' && request.headers.get('x-fife-recovery-protocol') !== '2')
			throw new RecoveryFault('client_update_required');
		const available = await recoveryAvailable(db, env, auth.email);
		if (
			!available &&
			(action === 'prepare' || (await service.status(body.operationId)).phase === 'prepared')
		)
			throw new RecoveryFault('recovery_unavailable');
		const result = action === 'prepare' ? await service.prepare(body) : await service.confirm(body);
		return reply({ success: 1, data: result });
	} catch (error) {
		// Do not log cookies, ciphertext envelopes, provider errors or body data.
		return reply({
			success: 0,
			message: error instanceof RecoveryFault ? error.code : 'recovery_unavailable'
		});
	}
}
