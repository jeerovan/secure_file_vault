import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authorize, addAccount } from '$lib/server/backblaze';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ status: 0, error: 'Invalid JSON body' });
	}

	const { app_id, app_key } = body;

	if (!app_id || !app_key) {
		return json({ status: 0, error: 'Missing required fields' });
	}
	const data = await authorize(app_id, app_key); // TODO Should be checked on user device
	if (data) {
		const {
			apiInfo: {
				storageApi: { capabilities }
			}
		} = data;
		const required = [
			'deleteFiles',
			'writeBuckets',
			'readBuckets',
			'readFiles',
			'shareFiles',
			'writeFiles',
			'listFiles'
		];
		const allExists = required.every((item) => capabilities.includes(item));
		if (allExists) {
			const result = await addAccount(authUser.id, app_id, app_key, data);
			return result;
		} else {
			return json({ status: 0, error: 'Credentials do not have required capabilities.' });
		}
	} else {
		return json({ status: 0, error: 'Invalid credentials' });
	}
};
