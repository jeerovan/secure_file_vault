import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ErrorCode } from '$lib/server/db/keys';
import { fetchFcmIds, removeFcmIds } from '$lib/server/db/api';
import { getDb } from '$lib/server/db';
import { FCM_KEY } from '$env/static/private';

export const GET: RequestHandler = async ({ request, url, platform }) => {
	const fcmKey = url.searchParams.get('fcm_key') || undefined;
	if (fcmKey != FCM_KEY) {
		return json({ success: 0 });
	}
	const rowId = parseInt(url.searchParams.get('row_id') || '0');
	const limit = parseInt(url.searchParams.get('limit') || '100');
	const minutes = parseInt(url.searchParams.get('minutes') || '60');
	const db = getDb(platform);

	const fcmIds = await fetchFcmIds(db, rowId, limit, minutes);

	return json({ success: 1, fcmIds });
};

export const POST: RequestHandler = async ({ request, platform }) => {
	let body;

	try {
		body = await request.json();
	} catch {
		return json({ success: 0, message: ErrorCode.INVALID_JSON });
	}

	const fcm_key = body.fcm_key ?? undefined;
	const tokens = body.tokens ?? undefined;
	if (!fcm_key || !tokens) {
		return json({ success: 0 });
	} else if (fcm_key != FCM_KEY) {
		return json({ success: 0 });
	} else {
		const db = getDb(platform);
		await removeFcmIds(db, tokens);
		return json({ success: 1 });
	}
};
