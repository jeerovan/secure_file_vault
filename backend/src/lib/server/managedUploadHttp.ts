import { json } from '@sveltejs/kit';
import { requireDeviceAuth } from './auth';
import { getDb } from './db';
import { ManagedUploadService, type UploadInput } from './managedUpload';
import { ProviderManagedUploadStorage, UploadFault } from './managedUploadStorage';

export async function managedUploadRequest(
	request: Request,
	platform: App.Platform | undefined,
	action: 'prepare' | 'complete' | 'report'
) {
	const reply = (body: Record<string, unknown>, status = 200) =>
		json(body, { status, headers: { 'Cache-Control': 'no-store' } });
	try {
		let body: Record<string, unknown>;
		try {
			body = await request.json();
			if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
		} catch {
			return reply({ success: 0, message: 'invalid_upload_request' }, 400);
		}
		const db = getDb(platform);
		const service = new ManagedUploadService(db, new ProviderManagedUploadStorage());
		let result;
		if (action === 'report') {
			// A receipt grants only cleanup of one existing upload. It cannot
			// enumerate storage, issue upload URLs or finalize any object.
			result = await service.report(body.id as string, body.receipt as string);
		} else {
			const auth = await requireDeviceAuth(db, request, platform?.env.FIFE_AUTH_CACHE);
			if (!auth.authorized)
				return reply({ success: 0, message: auth.message, reason: auth.reason });
			result =
				action === 'prepare'
					? await service.prepare(auth, body as unknown as UploadInput)
					: await service.complete(auth, body.id as string, body.receipt as string);
		}
		return reply(
			{ success: 1, data: result },
			['pending', 'cleanup_pending'].includes(result.state) ? 202 : 200
		);
	} catch (error) {
		const code = error instanceof UploadFault ? error.code : 'upload_service_unavailable';
		if (['device_revoked', 'vault_replaced', 'account_removed'].includes(code))
			return reply({ success: 0, message: code === 'account_removed' ? 1 : 8, reason: code });
		return reply(
			{ success: 0, message: code },
			code === 'upload_not_found'
				? 404
				: code === 'invalid_upload_request'
					? 400
					: ['upload_conflict', 'upload_not_ready'].includes(code)
						? 409
						: 503
		);
	}
}
