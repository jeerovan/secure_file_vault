import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireAuth } from '$lib/server/auth';
import { authorize, addAccount } from '$lib/server/backblaze';
import { ErrorCode } from '$lib/server/db/keys';

export const POST: RequestHandler = async ({ request }) => {
	const authUser = await requireAuth(request);
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const { app_id, app_key } = body;

	if (!app_id || !app_key) {
		return json({ success: 0, message: ErrorCode.MISSING_FIELDS });
	}
	const { message, data } = await authorize(app_id, app_key); // TODO Should be checked on user device also
	if (message) {
		// TODO flag user with attempt count
		return json({ success: 0, message });
	}
	if (data) {
		const {
			apiInfo: {
				storageApi: {
					allowed: { buckets, capabilities, namePrefix }
				}
			}
		} = data;
		if (buckets == null || buckets.length == 0) {
			return json({ success: 0, message: ErrorCode.NO_BUCKETS });
		} else if (buckets.length > 1) {
			return json({ success: 0, message: ErrorCode.MULTIPLE_BUCKETS });
		} else {
			const { id, name } = buckets[0];
			if (id == null || name == null) {
				return json({ success: 0, message: ErrorCode.BUCKET_INFO });
			}
		}
		if (namePrefix != null) {
			return json({ success: 0, message: ErrorCode.NAMEPREFIX_EXIST });
		}
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
			const result = await addAccount(authUser.id!, app_id, app_key, data);
			return result;
		} else {
			return json({ success: 0, message: ErrorCode.CREDENTIALS_INCAPABLE });
		}
	} else {
		return json({ success: 0, message: ErrorCode.INVALID_CREDENTIALS });
	}
};
