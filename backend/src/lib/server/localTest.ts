import {
	DeleteObjectsCommand,
	ListObjectsV2Command,
	type ObjectIdentifier
} from '@aws-sdk/client-s3';
import { createGenericS3Client, normalizeLocalS3Endpoint, type GenericS3Credentials } from './s3';

export type LocalTestIdentity = {
	token: string;
	remoteAuthId: string;
	email: string;
};

type PrivateEnvironment = Record<string, string | undefined>;

function required(environment: PrivateEnvironment, key: string): string {
	const value = environment[key]?.trim();
	if (!value) throw new Error(`${key} is required for local integration testing`);
	return value;
}

export function getLocalTestIdentity(environment: PrivateEnvironment): LocalTestIdentity | null {
	if (environment.LOCAL_TEST_AUTH_ENABLED !== 'true') return null;
	return {
		token: required(environment, 'LOCAL_TEST_AUTH_TOKEN'),
		remoteAuthId: required(environment, 'LOCAL_TEST_USER_ID'),
		email: required(environment, 'LOCAL_TEST_EMAIL')
	};
}

export function getLocalTestS3Credentials(environment: PrivateEnvironment): GenericS3Credentials {
	return {
		endpoint: normalizeLocalS3Endpoint(required(environment, 'LOCAL_S3_ENDPOINT')),
		region: required(environment, 'LOCAL_S3_REGION'),
		bucketName: required(environment, 'LOCAL_S3_BUCKET'),
		appId: required(environment, 'LOCAL_S3_ACCESS_KEY_ID'),
		appKey: required(environment, 'LOCAL_S3_SECRET_ACCESS_KEY'),
		forcePathStyle: environment.LOCAL_S3_FORCE_PATH_STYLE !== 'false'
	};
}

export async function tokensMatch(candidate: string, expected: string): Promise<boolean> {
	const encoder = new TextEncoder();
	const [candidateHash, expectedHash] = await Promise.all([
		crypto.subtle.digest('SHA-256', encoder.encode(candidate)),
		crypto.subtle.digest('SHA-256', encoder.encode(expected))
	]);
	const left = new Uint8Array(candidateHash);
	const right = new Uint8Array(expectedHash);
	let difference = left.length ^ right.length;
	for (let index = 0; index < left.length; index++) {
		difference |= left[index] ^ right[index];
	}
	return difference === 0;
}

export async function deleteLocalTestObjects(
	credentials: GenericS3Credentials,
	remoteAuthId: string
): Promise<void> {
	const client = createGenericS3Client(credentials);
	while (true) {
		const listed = await client.send(
			new ListObjectsV2Command({
				Bucket: credentials.bucketName,
				Prefix: `${remoteAuthId}/`,
				MaxKeys: 1000
			})
		);
		const objects: ObjectIdentifier[] = (listed.Contents ?? [])
			.map((object) => object.Key)
			.filter((key): key is string => Boolean(key))
			.map((Key) => ({ Key }));
		if (objects.length === 0) return;
		const deleted = await client.send(
			new DeleteObjectsCommand({
				Bucket: credentials.bucketName,
				Delete: { Objects: objects, Quiet: true }
			})
		);
		if (deleted.Errors?.length) {
			throw new Error(`Failed to delete ${deleted.Errors.length} local test objects`);
		}
	}
}
