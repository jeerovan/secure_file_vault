import { ErrorCode } from './db/keys';
import type { GenericS3Credentials } from './s3';

export class BackblazeCredentialError extends Error {
	constructor(readonly code: number = ErrorCode.INVALID_CREDENTIALS) {
		super('Backblaze credential discovery failed');
	}
}

export interface BackblazeCredentials extends GenericS3Credentials {
	accountId: string;
	authorizationToken: string;
	bucketId: string;
	apiUrl: string;
	downloadUrl: string;
	s3ApiUrl: string;
	capabilities: string[];
	namePrefix: null;
	applicationKeyExpirationTimestamp: number | null;
}

function record(value: unknown): Record<string, unknown> {
	if (!value || typeof value !== 'object' || Array.isArray(value)) {
		throw new BackblazeCredentialError();
	}
	return value as Record<string, unknown>;
}

function required(value: unknown): string {
	if (typeof value !== 'string' || !value.trim()) throw new BackblazeCredentialError();
	return value;
}

function origin(value: unknown, hostname: RegExp): string {
	let url: URL;
	try {
		url = new URL(required(value));
	} catch {
		throw new BackblazeCredentialError();
	}
	if (
		url.protocol !== 'https:' ||
		!hostname.test(url.hostname) ||
		url.username ||
		url.password ||
		url.port ||
		url.search ||
		url.hash ||
		url.pathname !== '/'
	)
		throw new BackblazeCredentialError();
	return url.origin;
}

/** Derive per-user S3 settings from that user's v4 authorization response. */
export function backblazeCredentialsFromAuthorization(
	appId: string,
	appKey: string,
	value: unknown
): BackblazeCredentials {
	required(appId);
	required(appKey);
	const data = record(value);
	const api = record(record(data.apiInfo).storageApi);
	const allowed = record(api.allowed);
	const buckets = allowed.buckets;
	if (buckets === null || (Array.isArray(buckets) && !buckets.length)) {
		throw new BackblazeCredentialError(ErrorCode.NO_BUCKETS);
	}
	if (!Array.isArray(buckets)) throw new BackblazeCredentialError();
	if (buckets.length > 1) throw new BackblazeCredentialError(ErrorCode.MULTIPLE_BUCKETS);
	const bucket = record(buckets[0]);
	if (
		typeof bucket.id !== 'string' ||
		!bucket.id ||
		typeof bucket.name !== 'string' ||
		!bucket.name
	) {
		throw new BackblazeCredentialError(ErrorCode.BUCKET_INFO);
	}
	if (allowed.namePrefix != null) throw new BackblazeCredentialError(ErrorCode.NAMEPREFIX_EXIST);
	const capabilities = allowed.capabilities;
	if (!Array.isArray(capabilities) || capabilities.some((cap) => typeof cap !== 'string')) {
		throw new BackblazeCredentialError();
	}
	// Retain permissions required by existing native operations during S3 migration.
	if (
		![
			'deleteFiles',
			'writeBuckets',
			'readBuckets',
			'readFiles',
			'shareFiles',
			'writeFiles',
			'listFiles'
		].every((cap) => capabilities.includes(cap))
	) {
		throw new BackblazeCredentialError(ErrorCode.CREDENTIALS_INCAPABLE);
	}
	const endpoint = origin(api.s3ApiUrl, /^s3\.([a-z0-9-]+)\.backblazeb2\.com$/);
	const region = new URL(endpoint).hostname.split('.')[1];
	const expiresAt = data.applicationKeyExpirationTimestamp ?? null;
	if (
		expiresAt !== null &&
		(typeof expiresAt !== 'number' || !Number.isSafeInteger(expiresAt) || expiresAt <= 0)
	) {
		throw new BackblazeCredentialError();
	}
	return {
		appId,
		appKey,
		accountId: required(data.accountId),
		authorizationToken: required(data.authorizationToken),
		bucketId: bucket.id,
		bucketName: bucket.name,
		apiUrl: origin(api.apiUrl, /^api(?:[0-9]+)?\.backblazeb2\.com$/),
		downloadUrl: origin(api.downloadUrl, /^f[0-9]+\.backblazeb2\.com$/),
		s3ApiUrl: endpoint,
		endpoint,
		region,
		forcePathStyle: true,
		capabilities: [...capabilities],
		namePrefix: null,
		applicationKeyExpirationTimestamp: expiresAt
	};
}
