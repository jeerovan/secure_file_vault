import { and, asc, eq, gt, ne } from 'drizzle-orm';
import type { Db, Tx } from './db';
import {
	user,
	vaultState,
	vaultUploadCapability,
	vaultUpload,
	recoveryReset,
	recoveryCleanupTarget,
	userDevice,
	userData,
	file,
	item,
	part,
	tempStorage,
	credential,
	storage
} from './db/schema';
import {
	UserKeys,
	UserDataKeys,
	UserDeviceKeys,
	FileKeys,
	ItemKeys,
	PartKeys,
	TempStorageKeys,
	CredentialKeys,
	StorageKeys,
	StorageProvider
} from './db/keys';
import { ensureDefaultFiFeStorage } from './defaultStorage';
import { backblazeS3Credentials } from './backblazeS3';
import { resetNotBefore } from './recoveryWait';
import {
	RecoveryFault,
	recoveryHash,
	requireFreshRecoverySession,
	requireCurrentVaultSession,
	type RecoverySession
} from './recoverySession';
import {
	vaultObjectPrefix,
	isRetiredVaultObject,
	type RecoveryStorage,
	type RecoveryTarget
} from './recoveryStorage';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const challengeHash = /^[a-f0-9]{64}$/;
const preparationLifetime = 5 * 60_000;

export interface ResetPreparation {
	operationId: string;
	expectedGeneration: string;
	challengeHash: string;
}
export interface ResetConfirmation {
	operationId: string;
	challenge: string;
	cipher: string;
	nonce: string;
}

function normalizedCredentials(providerId: number, raw: unknown): Record<string, unknown> {
	if (typeof raw !== 'object' || raw === null || Array.isArray(raw))
		throw new RecoveryFault('storage_access_required');
	const data = raw as Record<string, unknown>;
	const keys = ['appId', 'appKey', 'bucketName'];
	if ([StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(providerId)) keys.push('bucketId');
	else if (providerId === StorageProvider.CLOUDFLARE) keys.push('accountId');
	else if (providerId === StorageProvider.OCI) keys.push('namespace', 'region');
	else if (providerId === StorageProvider.IDRIVE) keys.push('region');
	else if (providerId === StorageProvider.S3) keys.push('region', 'endpoint', 'forcePathStyle');
	else throw new RecoveryFault('storage_unsupported');
	const normalized = Object.fromEntries(
		keys.map((key) => {
			const value = data[key];
			if (key === 'forcePathStyle' && value === undefined) return [key, false];
			if (
				key === 'forcePathStyle' ? typeof value !== 'boolean' : typeof value !== 'string' || !value
			) {
				throw new RecoveryFault('storage_access_required');
			}
			return [key, value];
		})
	);
	if (
		[StorageProvider.FIFE, StorageProvider.BACKBLAZE].includes(providerId) &&
		(Object.hasOwn(data, 's3ApiUrl') || Object.hasOwn(data, 'endpoint'))
	) {
		try {
			const s3 = backblazeS3Credentials(data);
			return {
				...normalized,
				s3ApiUrl: s3.endpoint,
				endpoint: s3.endpoint,
				region: s3.region,
				forcePathStyle: true
			};
		} catch {
			throw new RecoveryFault('storage_access_required');
		}
	}
	return normalized;
}

export async function recoveryTargets(
	db: Db | Tx,
	userId: number,
	prefix: string
): Promise<RecoveryTarget[]> {
	const allocations = await db
		.select({ credentials: credential })
		.from(storage)
		.leftJoin(credential, eq(storage[StorageKeys.CREDENTIAL_ID], credential[CredentialKeys.ID]))
		.where(eq(storage[StorageKeys.USER_ID], userId))
		.orderBy(asc(storage[StorageKeys.ID]));
	const owned = await db
		.select()
		.from(credential)
		.where(eq(credential[CredentialKeys.USER_ID], userId))
		.orderBy(asc(credential[CredentialKeys.ID]));
	const targets = new Map<string, RecoveryTarget>();
	for (const row of [...allocations.map((row) => row.credentials), ...owned]) {
		if (!row) throw new RecoveryFault('storage_access_required');
		const providerId = row[CredentialKeys.PROVIDER_ID];
		const target = {
			providerId,
			prefix,
			credentials: normalizedCredentials(providerId, row[CredentialKeys.CREDENTIALS])
		};
		targets.set(JSON.stringify(target), target);
	}
	// A provider connection may have been removed/replaced during an upload.
	// Its original private cleanup snapshot still belongs to the retired vault.
	const uploads = await db
		.select()
		.from(vaultUpload)
		.where(and(eq(vaultUpload.userId, userId), ne(vaultUpload.phase, 'deleted')));
	for (const upload of uploads) {
		if (!isRetiredVaultObject(prefix, upload.objectKey)) continue;
		const target = {
			providerId: upload.providerId,
			prefix,
			credentials: normalizedCredentials(upload.providerId, upload.credentials)
		};
		targets.set(JSON.stringify(target), target);
	}
	return [...targets.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([, target]) => target);
}

function validEnvelope(cipher: unknown, nonce: unknown): cipher is string {
	if (typeof cipher !== 'string' || typeof nonce !== 'string') return false;
	try {
		return (
			atob(cipher).length === 48 &&
			atob(nonce).length === 24 &&
			btoa(atob(cipher)) === cipher &&
			btoa(atob(nonce)) === nonce
		);
	} catch {
		return false;
	}
}

export class RecoveryResetService {
	constructor(
		private readonly db: Db | Tx,
		private readonly userId: number,
		private readonly session: RecoverySession,
		private readonly cloud: RecoveryStorage,
		private readonly clock: () => number = Date.now,
		private readonly uploadAccountingSince?: number
	) {}

	private async account(tx: Db | Tx, lock = false) {
		const query = tx.select().from(user).where(eq(user[UserKeys.ID], this.userId)).limit(1);
		const [account] = await (lock ? query.for('update') : query);
		if (
			!account ||
			account[UserKeys.REMOTE_AUTH_ID] !== this.session.userId ||
			account[UserKeys.EMAIL].toLowerCase() !== this.session.email.toLowerCase() ||
			this.session.userId === 'fife'
		) {
			throw new RecoveryFault('sign_in_again');
		}
		return account;
	}

	private async state(tx: Db | Tx) {
		const [state] = await tx
			.select()
			.from(vaultState)
			.where(eq(vaultState.userId, this.userId))
			.limit(1);
		return state;
	}

	private view(operation: typeof recoveryReset.$inferSelect) {
		return {
			operationId: operation.id,
			phase: operation.phase,
			generation: operation.nextGeneration,
			keySetupProtocol: 2,
			expiresAt: operation.expiresAt,
			expired: operation.phase === 'prepared' && operation.expiresAt <= this.clock(),
			requiresFreshSignin:
				operation.phase === 'prepared' && this.clock() - this.session.createdAt > 10 * 60_000,
			notBefore: operation.notBefore,
			envelopeHash: operation.envelopeHash,
			error: operation.error
		};
	}

	async prepare(input: ResetPreparation) {
		if (
			!input ||
			!uuid.test(input.operationId) ||
			!challengeHash.test(input.challengeHash) ||
			typeof input.expectedGeneration !== 'string'
		)
			throw new RecoveryFault('invalid_reset_request');
		const now = this.clock();
		requireFreshRecoverySession(this.session, now);
		return this.db.transaction(async (tx) => {
			await this.account(tx, true);
			const [existing] = await tx
				.select()
				.from(recoveryReset)
				.where(eq(recoveryReset.id, input.operationId));
			if (existing) {
				if (
					existing.userId !== this.userId ||
					existing.sessionHash !== this.session.hash ||
					existing.challengeHash !== input.challengeHash ||
					existing.expectedGeneration !== input.expectedGeneration
				) {
					throw new RecoveryFault('reset_conflict');
				}
				return this.view(existing);
			}
			const state = await this.state(tx);
			requireCurrentVaultSession(this.session, state);
			if ((state?.generation ?? 'legacy') !== input.expectedGeneration)
				throw new RecoveryFault('vault_changed');
			if (state?.ready === 0) throw new RecoveryFault('reset_in_progress');
			const recent = await tx
				.select()
				.from(recoveryReset)
				.where(
					and(eq(recoveryReset.userId, this.userId), gt(recoveryReset.createdAt, now - 60 * 60_000))
				);
			if (recent.some((op) => op.phase === 'prepared' && op.expiresAt > now))
				throw new RecoveryFault('reset_conflict');
			if (recent.length >= 3) throw new RecoveryFault('rate_limited');
			const [operation] = await tx
				.insert(recoveryReset)
				.values({
					id: input.operationId,
					userId: this.userId,
					expectedGeneration: input.expectedGeneration,
					nextGeneration: crypto.randomUUID(),
					sessionHash: this.session.hash,
					challengeHash: input.challengeHash,
					createdAt: now,
					expiresAt: now + preparationLifetime
				})
				.returning();
			return this.view(operation);
		});
	}

	async status(operationId: string) {
		await this.account(this.db);
		const [operation] = await this.db
			.select()
			.from(recoveryReset)
			.where(and(eq(recoveryReset.id, operationId), eq(recoveryReset.userId, this.userId)))
			.limit(1);
		if (!operation) throw new RecoveryFault('reset_not_found');
		const state = await this.state(this.db);
		requireCurrentVaultSession(this.session, state);
		if (operation.phase !== 'prepared' && state?.generation !== operation.nextGeneration)
			throw new RecoveryFault('vault_changed');
		return this.view(operation);
	}

	async confirm(input: ResetConfirmation) {
		if (
			!input ||
			!uuid.test(input.operationId) ||
			!/^[A-Za-z0-9_-]{43}$/.test(input.challenge) ||
			!validEnvelope(input.cipher, input.nonce)
		)
			throw new RecoveryFault('invalid_reset_request');
		const proofHash = await recoveryHash(input.challenge);
		const envelopeHash = await recoveryHash(`${input.cipher}.${input.nonce}`);
		// Snapshot under the account lock, then probe providers outside SQL.
		const snapshot = await this.db.transaction(async (tx) => {
			const account = await this.account(tx, true);
			const [operation] = await tx
				.select()
				.from(recoveryReset)
				.where(eq(recoveryReset.id, input.operationId));
			if (
				!operation ||
				operation.userId !== this.userId ||
				operation.sessionHash !== this.session.hash ||
				operation.challengeHash !== proofHash
			)
				throw new RecoveryFault('reset_not_found');
			if (operation.phase !== 'prepared') {
				if (operation.envelopeHash !== envelopeHash) throw new RecoveryFault('reset_conflict');
				const state = await this.state(tx);
				if (state?.generation !== operation.nextGeneration)
					throw new RecoveryFault('vault_changed');
				return { completed: this.view(operation) };
			}
			requireFreshRecoverySession(this.session, this.clock());
			if (operation.expiresAt <= this.clock()) throw new RecoveryFault('reset_expired');
			const state = await this.state(tx);
			if ((state?.generation ?? 'legacy') !== operation.expectedGeneration || state?.ready === 0)
				throw new RecoveryFault('vault_changed');
			return {
				targets: await recoveryTargets(
					tx,
					this.userId,
					vaultObjectPrefix(account[UserKeys.REMOTE_AUTH_ID], operation.expectedGeneration)
				)
			};
		});
		if (snapshot.completed) return snapshot.completed;
		try {
			for (const target of snapshot.targets!) await this.cloud.probe(target);
		} catch (error) {
			const code =
				error instanceof RecoveryFault && error.code.startsWith('storage_')
					? error.code
					: 'storage_access_required';
			await this.db
				.update(recoveryReset)
				.set({ error: code })
				.where(
					and(
						eq(recoveryReset.id, input.operationId),
						eq(recoveryReset.userId, this.userId),
						eq(recoveryReset.phase, 'prepared')
					)
				);
			throw new RecoveryFault(code);
		}
		return this.db.transaction(async (tx) => {
			const account = await this.account(tx, true);
			const [operation] = await tx
				.select()
				.from(recoveryReset)
				.where(eq(recoveryReset.id, input.operationId))
				.for('update');
			if (operation.phase !== 'prepared') {
				if (operation.envelopeHash !== envelopeHash) throw new RecoveryFault('reset_conflict');
				const state = await this.state(tx);
				if (state?.generation !== operation.nextGeneration)
					throw new RecoveryFault('vault_changed');
				return this.view(operation);
			}
			const now = this.clock();
			requireFreshRecoverySession(this.session, now);
			if (operation.expiresAt <= now) throw new RecoveryFault('reset_expired');
			const state = await this.state(tx);
			if ((state?.generation ?? 'legacy') !== operation.expectedGeneration || state?.ready === 0)
				throw new RecoveryFault('vault_changed');
			const targets = await recoveryTargets(
				tx,
				this.userId,
				vaultObjectPrefix(account[UserKeys.REMOTE_AUTH_ID], operation.expectedGeneration)
			);
			if (JSON.stringify(targets) !== JSON.stringify(snapshot.targets))
				throw new RecoveryFault('storage_changed');
			const [capability] = await tx
				.select()
				.from(vaultUploadCapability)
				.where(
					and(
						eq(vaultUploadCapability.userId, this.userId),
						eq(vaultUploadCapability.generation, operation.expectedGeneration)
					)
				);
			if (capability && !targets.length) throw new RecoveryFault('storage_access_required');
			const notBefore = resetNotBefore({
				now,
				providerIds: targets.map((target) => target.providerId),
				capabilityExpiresAt: capability?.expiresAt,
				uploadAccountingSince: this.uploadAccountingSince
			});
			for (const target of targets)
				await tx.insert(recoveryCleanupTarget).values({
					id: crypto.randomUUID(),
					operationId: operation.id,
					...target
				});
			// Retain upload obligations independently of the ordinary vault rows.
			// In-flight provider requests finish outside SQL and observe retirement
			// when checkpointing; readiness also waits for this durable record.
			await tx
				.update(vaultUpload)
				.set({ retired: 1, operationId: operation.id, nextAttemptAt: now })
				.where(
					and(
						eq(vaultUpload.userId, this.userId),
						eq(vaultUpload.generation, operation.expectedGeneration)
					)
				);
			await tx.delete(userDevice).where(eq(userDevice[UserDeviceKeys.USER_ID], this.userId));
			await tx.delete(item).where(eq(item[ItemKeys.USER_ID], this.userId));
			await tx.delete(part).where(eq(part[PartKeys.USER_ID], this.userId));
			await tx.delete(tempStorage).where(eq(tempStorage[TempStorageKeys.USER_ID], this.userId));
			await tx.delete(file).where(eq(file[FileKeys.USER_ID], this.userId));
			// Connections and provider credentials belong to the account, not the
			// retired encryption keys. Keep their IDs/configuration so the fresh
			// vault can reuse them after verified cleanup; only old usage is reset.
			await tx
				.update(storage)
				.set({ [StorageKeys.USED_BYTES]: 0 })
				.where(eq(storage[StorageKeys.USER_ID], this.userId));
			await tx
				.update(userData)
				.set({
					[UserDataKeys.USER_NAME]: null,
					[UserDataKeys.PROFILE_IMAGE]: null,
					[UserDataKeys.DEVICE_UUID]: 'Server'
				})
				.where(eq(userData[UserDataKeys.USER_ID], this.userId));
			await tx
				.update(user)
				// Confirmation staging binds retries; it must not initialize keys.
				// Any current authenticated device may claim the fresh envelope only
				// after cleanup has been verified, through the atomic /keys write.
				.set({ [UserKeys.CIPHER]: null, [UserKeys.NONCE]: null })
				.where(eq(user[UserKeys.ID], this.userId));
			await tx
				.insert(vaultState)
				.values({
					userId: this.userId,
					generation: operation.nextGeneration,
					resetAt: now,
					initiatingSessionHash: this.session.hash,
					ready: targets.length ? 0 : 1
				})
				.onConflictDoUpdate({
					target: vaultState.userId,
					set: {
						generation: operation.nextGeneration,
						resetAt: now,
						initiatingSessionHash: this.session.hash,
						ready: targets.length ? 0 : 1
					}
				});
			if (!targets.length) await ensureDefaultFiFeStorage(tx, this.userId);
			const [committed] = await tx
				.update(recoveryReset)
				.set({
					phase: targets.length ? 'cleanup_pending' : 'ready',
					committedAt: now,
					notBefore,
					envelopeHash,
					error: null
				})
				.where(eq(recoveryReset.id, operation.id))
				.returning();
			return this.view(committed);
		});
	}
}
