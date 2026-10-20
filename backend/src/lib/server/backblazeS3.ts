import {
	DeleteObjectCommand,
	GetObjectCommand,
	HeadObjectCommand,
	PutObjectCommand,
	S3Client
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { PRESIGNED_UPLOAD_EXPIRY_SECONDS, type GenericS3Credentials } from './s3';

export const BACKBLAZE_UPLOAD_EXPIRY_SECONDS = PRESIGNED_UPLOAD_EXPIRY_SECONDS;
export const MAX_BACKBLAZE_PART_BYTES = 101 * 1024 * 1024;

/** Accept persisted pre-migration rows as well as discovered S3 metadata. */
export function backblazeS3Credentials(value: unknown): GenericS3Credentials {
	if (!value || typeof value !== 'object') throw new Error('Invalid Backblaze credentials');
	const data = value as Record<string, unknown>;
	const required = (key: string): string => {
		const result = data[key];
		if (typeof result !== 'string' || !result) throw new Error('Invalid Backblaze credentials');
		return result;
	};
	const endpoint = new URL(required(typeof data.s3ApiUrl === 'string' ? 's3ApiUrl' : 'endpoint'));
	if (
		endpoint.protocol !== 'https:' ||
		!/^s3\.([a-z0-9-]+)\.backblazeb2\.com$/.test(endpoint.hostname) ||
		endpoint.username ||
		endpoint.password ||
		endpoint.port ||
		endpoint.pathname !== '/' ||
		endpoint.search ||
		endpoint.hash
	)
		throw new Error('Invalid Backblaze endpoint');
	return {
		endpoint: endpoint.origin,
		region: endpoint.hostname.split('.')[1],
		bucketName: required('bucketName'),
		appId: required('appId'),
		appKey: required('appKey'),
		forcePathStyle: true
	};
}

export function createBackblazeS3Client(value: unknown): S3Client {
	const data = backblazeS3Credentials(value);
	return new S3Client({
		endpoint: data.endpoint,
		region: data.region,
		credentials: { accessKeyId: data.appId, secretAccessKey: data.appKey },
		forcePathStyle: true,
		// The client supplies the actual ciphertext MD5. Never sign an SDK-generated
		// checksum of an absent body when issuing a presigned upload URL.
		requestChecksumCalculation: 'WHEN_REQUIRED',
		maxAttempts: 2
	});
}

export interface BackblazeUploadIntegrity {
	content_sha1: string;
	content_md5: string;
	content_length: number;
}

export function validBackblazeUploadIntegrity(
	value: Record<string, unknown>
): value is Record<string, unknown> & BackblazeUploadIntegrity {
	if (
		typeof value.content_sha1 !== 'string' ||
		!/^[a-f0-9]{40}$/i.test(value.content_sha1) ||
		typeof value.content_md5 !== 'string' ||
		!/^[A-Za-z0-9+/]{22}==$/.test(value.content_md5) ||
		!Number.isSafeInteger(value.content_length) ||
		(value.content_length as number) < 0 ||
		(value.content_length as number) > MAX_BACKBLAZE_PART_BYTES
	)
		return false;
	return btoa(atob(value.content_md5)) === value.content_md5;
}

export async function backblazeS3Upload(
	value: unknown,
	key: string,
	integrity: BackblazeUploadIntegrity
) {
	const credentials = backblazeS3Credentials(value);
	const client = createBackblazeS3Client(credentials);
	const headers = {
		'Content-Type': 'application/octet-stream',
		'Content-Length': String(integrity.content_length),
		'Content-MD5': integrity.content_md5,
		'x-amz-meta-sha1': integrity.content_sha1.toLowerCase()
	};
	try {
		const uploadUrl = await getSignedUrl(
			client,
			new PutObjectCommand({
				Bucket: credentials.bucketName,
				Key: key,
				ContentType: headers['Content-Type'],
				ContentLength: integrity.content_length,
				ContentMD5: integrity.content_md5,
				Metadata: { sha1: headers['x-amz-meta-sha1'] }
			}),
			{
				expiresIn: BACKBLAZE_UPLOAD_EXPIRY_SECONDS,
				signableHeaders: new Set(['content-md5', 'content-length', 'content-type']),
				unhoistableHeaders: new Set(['x-amz-meta-sha1'])
			}
		);
		return {
			protocol: 's3',
			method: 'PUT',
			uploadUrl,
			headers,
			expiresIn: BACKBLAZE_UPLOAD_EXPIRY_SECONDS
		};
	} finally {
		client.destroy();
	}
}

export async function backblazeS3Download(value: unknown, key: string) {
	const credentials = backblazeS3Credentials(value),
		client = createBackblazeS3Client(credentials);
	try {
		return await getSignedUrl(
			client,
			new GetObjectCommand({ Bucket: credentials.bucketName, Key: key }),
			{ expiresIn: 3600 }
		);
	} finally {
		client.destroy();
	}
}

/** Undefined means old native metadata needs the compatibility lookup. */
export async function findBackblazeS3Upload(
	value: unknown,
	key: string,
	sha1: string,
	size: number
): Promise<{ fileId: string } | null | undefined> {
	const credentials = backblazeS3Credentials(value),
		client = createBackblazeS3Client(credentials);
	try {
		const object = await client.send(
			new HeadObjectCommand({ Bucket: credentials.bucketName, Key: key }),
			{ abortSignal: AbortSignal.timeout(15_000) }
		);
		const digest = object.Metadata?.sha1;
		if (!digest) return undefined;
		return object.ContentLength === size &&
			digest.toLowerCase() === sha1.toLowerCase() &&
			object.VersionId
			? { fileId: object.VersionId }
			: null;
	} catch (error) {
		if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404)
			return null;
		throw new Error('Backblaze object verification unavailable');
	} finally {
		client.destroy();
	}
}

export async function deleteBackblazeS3Version(value: unknown, key: string, versionId: unknown) {
	if (typeof versionId !== 'string' || !versionId) return false;
	const credentials = backblazeS3Credentials(value),
		client = createBackblazeS3Client(credentials);
	try {
		await client.send(
			new DeleteObjectCommand({ Bucket: credentials.bucketName, Key: key, VersionId: versionId }),
			{ abortSignal: AbortSignal.timeout(15_000) }
		);
		return true;
	} catch (error) {
		const failure = error as { name?: string; $metadata?: { httpStatusCode?: number } };
		return (
			failure.$metadata?.httpStatusCode === 404 &&
			['NoSuchKey', 'NoSuchVersion', 'NotFound'].includes(failure.name ?? '')
		);
	} finally {
		client.destroy();
	}
}
