import type { HandleServerError } from '@sveltejs/kit';
import { serializeErrorChain } from '$lib/server/errorLogging';

export const handleError: HandleServerError = ({ error, event, status, message }) => {
	const errorId = crypto.randomUUID();

	try {
		console.error(
			`[server-error] ${JSON.stringify({
				errorId,
				status,
				method: event.request.method,
				path: event.url.pathname,
				routeId: event.route.id,
				cfRay: event.request.headers.get('cf-ray'),
				errors: serializeErrorChain(error)
			})}`
		);
	} catch (loggingError) {
		// Error reporting must never mask the original application failure.
		console.error('[server-error]', errorId, error, loggingError);
	}

	return { message, errorId };
};
