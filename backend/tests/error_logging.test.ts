import assert from 'node:assert/strict';
import test from 'node:test';

import { serializeErrorChain } from '../src/lib/server/errorLogging';

test('serializes nested database errors and their diagnostic fields', () => {
	const databaseError = Object.assign(new Error('connection was closed'), {
		name: 'PostgresError',
		code: '08006',
		severity: 'FATAL',
		routine: 'pq_getmsgend'
	});
	const queryError = new Error('Failed query: select 1\nparams: private-value', {
		cause: databaseError
	});

	assert.deepEqual(serializeErrorChain(queryError), [
		{
			name: 'Error',
			message: 'Failed query: select 1',
			stack: queryError.stack?.replace('\nparams: private-value', '')
		},
		{
			name: 'PostgresError',
			message: 'connection was closed',
			stack: databaseError.stack,
			database: {
				code: '08006',
				severity: 'FATAL',
				routine: 'pq_getmsgend'
			}
		}
	]);
});

test('redacts credentials embedded in database error messages', () => {
	const [loggedError] = serializeErrorChain(
		new Error('failed to connect to postgres://user:secret@database.example/fife')
	);

	assert.equal(
		loggedError.message,
		'failed to connect to postgres://<redacted>@database.example/fife'
	);
});
