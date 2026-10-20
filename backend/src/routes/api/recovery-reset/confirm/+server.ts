import type { RequestHandler } from './$types';
import { recoveryRequest } from '$lib/server/recoveryHttp';

export const POST: RequestHandler = ({ request, platform }) =>
	recoveryRequest(request, platform, 'confirm');
