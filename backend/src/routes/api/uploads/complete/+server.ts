import type { RequestHandler } from './$types';
import { managedUploadRequest } from '$lib/server/managedUploadHttp';
export const POST: RequestHandler = ({ request, platform }) =>
	managedUploadRequest(request, platform, 'complete');
