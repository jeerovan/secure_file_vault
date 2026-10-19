import assert from 'node:assert/strict';
import test from 'node:test';

import { serializeErrorChain } from '../src/lib/server/errorLogging';

test('cyclic error causes cannot hang the request error handler', () => {
	const first = new Error('first');
	const second = new Error('second', { cause: first });
	(first as Error & { cause: unknown }).cause = second;
	assert.deepEqual(
		serializeErrorChain(first).map((entry) => entry.message),
		['first', 'second']
	);
});

test('deep exception chains are bounded while retaining the outer diagnosis', () => {
	let error = new Error('root');
	for (let index = 0; index < 50; index++) error = new Error(`layer-${index}`, { cause: error });
	const serialized = serializeErrorChain(error);
	assert.equal(serialized.length, 8);
	assert.equal(serialized[0].message, 'layer-49');
});

test('throwing diagnostic getters cannot break error serialization', () => {
	const error = Object.create(null);
	for (const key of ['message', 'stack', 'constructor', 'code', 'cause']) {
		Object.defineProperty(error, key, {
			get() {
				throw new Error('getter unavailable');
			}
		});
	}
	assert.doesNotThrow(() => serializeErrorChain(error));
	assert.equal(serializeErrorChain(error).length, 1);
});

test('primitive and missing errors serialize without secondary failures', () => {
	for (const value of [false, 42, 'request aborted', Symbol('error')]) {
		assert.equal(serializeErrorChain(value).length, 1);
	}
	assert.deepEqual(serializeErrorChain(null), []);
	assert.deepEqual(serializeErrorChain(undefined), []);
});

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
