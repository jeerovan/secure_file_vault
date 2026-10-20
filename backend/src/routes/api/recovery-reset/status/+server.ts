import type { RequestHandler } from './$types';
import { recoveryRequest } from '$lib/server/recoveryHttp';

export const GET: RequestHandler = ({ request, platform }) =>
	recoveryRequest(request, platform, 'status');
