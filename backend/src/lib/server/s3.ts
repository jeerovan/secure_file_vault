import { HeadBucketCommand, S3Client } from '@aws-sdk/client-s3';

export type GenericS3Credentials = {
	endpoint: string;
	region: string;
	bucketName: string;
	appId: string;
	appKey: string;
	forcePathStyle: boolean;
};

function isNonPublicIpv4(hostname: string): boolean {
	const parts = hostname.split('.');
	if (parts.length !== 4) return false;
	const octets = parts.map(Number);
	if (octets.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return true;

	const [first, second] = octets;
	return (
		first === 0 ||
		first === 10 ||
		first === 127 ||
		(first === 100 && second >= 64 && second <= 127) ||
		(first === 169 && second === 254) ||
		(first === 172 && second >= 16 && second <= 31) ||
		(first === 192 && second === 168) ||
		(first === 198 && (second === 18 || second === 19)) ||
		first >= 224
	);
}

function isNonPublicIpv6(hostname: string): boolean {
	const normalized = hostname.replace(/^\[|\]$/g, '').toLowerCase();
	if (!normalized.includes(':')) return false;
	if (normalized.startsWith('::ffff:')) return true;
	const mappedIpv4 = normalized.match(/(?:^|:)ffff:(\d+\.\d+\.\d+\.\d+)$/)?.[1];
	if (mappedIpv4 && isNonPublicIpv4(mappedIpv4)) return true;
	return (
		normalized === '::' ||
		normalized === '::1' ||
		normalized.startsWith('fc') ||
		normalized.startsWith('fd') ||
		normalized.startsWith('fe8') ||
		normalized.startsWith('fe9') ||
		normalized.startsWith('fea') ||
		normalized.startsWith('feb')
	);
}

function normalizeS3Endpoint(
	value: string,
	{ allowHttp, allowPrivateHost }: { allowHttp: boolean; allowPrivateHost: boolean }
): string {
	let endpoint: URL;
	try {
		endpoint = new URL(value.trim());
	} catch {
		throw new Error('Invalid S3 endpoint URL');
	}

	if (endpoint.protocol !== 'https:' && !(allowHttp && endpoint.protocol === 'http:'))
		throw new Error(
			allowHttp ? 'S3 endpoint must use HTTP or HTTPS' : 'S3 endpoint must use HTTPS'
		);
	if (endpoint.username || endpoint.password)
		throw new Error('S3 endpoint cannot contain credentials');
	if (endpoint.search || endpoint.hash)
		throw new Error('S3 endpoint cannot contain a query or fragment');

	const hostname = endpoint.hostname.toLowerCase();
	if (
		!allowPrivateHost &&
		(hostname === 'localhost' ||
			hostname.endsWith('.localhost') ||
			hostname.endsWith('.local') ||
			isNonPublicIpv4(hostname) ||
			isNonPublicIpv6(hostname))
	) {
		throw new Error('S3 endpoint must use a public host');
	}

	endpoint.pathname = endpoint.pathname.replace(/\/+$/, '') || '/';
	return endpoint.toString().replace(/\/$/, '');
}

export function normalizePublicS3Endpoint(value: string): string {
	return normalizeS3Endpoint(value, { allowHttp: false, allowPrivateHost: false });
}

export function normalizeLocalS3Endpoint(value: string): string {
	return normalizeS3Endpoint(value, { allowHttp: true, allowPrivateHost: true });
}

export function createGenericS3Client(credentials: GenericS3Credentials): S3Client {
	return new S3Client({
		endpoint: credentials.endpoint,
		region: credentials.region,
		credentials: {
			accessKeyId: credentials.appId,
			secretAccessKey: credentials.appKey
		},
		forcePathStyle: credentials.forcePathStyle
	});
}

export async function verifyGenericS3Credentials(
	credentials: GenericS3Credentials
): Promise<boolean> {
	try {
		await createGenericS3Client(credentials).send(
			new HeadBucketCommand({ Bucket: credentials.bucketName })
		);
		return true;
	} catch {
		return false;
	}
}
