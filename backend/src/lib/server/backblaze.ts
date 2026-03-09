import {
	addB2Account,
	getB2Account,
	markB2TokenUpdated,
	markB2TokenUpdating,
	updateB2Account
} from './db/api';

const B2_API_URL = 'https://api.backblazeb2.com/b2api/v4';

export async function authorize(appId: string, appKey: string) {
	let response;
	try {
		const authResponse = await fetch(`${B2_API_URL}/b2_authorize_account`, {
			headers: { Authorization: `Basic ${btoa(`${appId}:${appKey}`)}` }
		});

		if (!authResponse.ok) {
			console.error('B2 Authentication failed:', authResponse.status, authResponse.statusText);
		}

		response = await authResponse.json();
	} catch (error) {
		console.error('Error fetching B2 token:', error);
	}
	return response;
}

export async function addAccount(Id: string, AppId: string, KeyId: string, data: any) {
	await addB2Account(Id, AppId, KeyId, data);
}

export async function authenticate(Id: string) {
	// 1. Find the row for this Id
	const row = await getB2Account(Id);

	// Return undefined if the account does not exist
	if (!row) {
		return undefined;
	}

	const existingToken = row['6'] || undefined;
	const isUpdating = row['7'];
	const updatedAt = row['3'] || new Date(0); // Fallback to 1970 if null
	const appId = row['4'];
	const appKey = row['5'];

	// 2. If another process is currently updating, return the old token immediately
	if (isUpdating === 1) {
		return existingToken;
	}

	// 3. Check if we actually need to update
	// Token lasts 24 hours, but we refresh after 20 hours
	const now = new Date();
	const diffHours = (now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60);

	// If token exists and was updated less than 50 minutes ago, return it
	if (existingToken && diffHours < 20) {
		return existingToken;
	}

	// 4. Mark as updating (Atomic lock to prevent race conditions)
	const lockResult = await markB2TokenUpdating(Id);

	// If no rows are returned, another process grabbed the lock right before us
	if (lockResult.length === 0) {
		return existingToken;
	}

	// 5. Authenticate with B2
	const data = await authorize(appId, appKey);
	if (data) {
		const { authorizationToken } = data;
		await updateB2Account(Id, data);
		return authorizationToken;
	} else {
		await markB2TokenUpdated(Id);
		return existingToken;
	}
}
