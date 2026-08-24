const MAX_CAUSE_DEPTH = 8;

const DATABASE_ERROR_FIELDS = [
	'code',
	'severity',
	'severity_local',
	'detail',
	'hint',
	'position',
	'internal_position',
	'internal_query',
	'where',
	'schema_name',
	'table_name',
	'column_name',
	'data_type_name',
	'constraint_name',
	'file',
	'line',
	'routine'
] as const;

export interface LoggedError {
	name: string;
	message: string;
	stack?: string;
	database?: Record<string, string | number | boolean>;
}

function readProperty(value: object, property: PropertyKey): unknown {
	try {
		return Reflect.get(value, property);
	} catch {
		return undefined;
	}
}

function errorMessage(value: unknown): string {
	if (typeof value === 'string') return value;
	if (typeof value !== 'object' || value === null) {
		try {
			return String(value);
		} catch {
			return 'Unknown error';
		}
	}

	const message = readProperty(value, 'message');
	if (typeof message === 'string') return message;

	try {
		return String(value);
	} catch {
		return 'Unknown error';
	}
}

function sanitizeMessage(message: string): string {
	return message
		.split('\n')
		.filter((line) => !line.trimStart().startsWith('params:'))
		.join('\n')
		.replace(/(postgres(?:ql)?:\/\/)[^@\s]+@/gi, '$1<redacted>@');
}

function databaseFields(value: object): Record<string, string | number | boolean> | undefined {
	const fields: Record<string, string | number | boolean> = {};

	for (const field of DATABASE_ERROR_FIELDS) {
		const fieldValue = readProperty(value, field);
		if (
			typeof fieldValue === 'string' ||
			typeof fieldValue === 'number' ||
			typeof fieldValue === 'boolean'
		) {
			fields[field] = fieldValue;
		}
	}

	return Object.keys(fields).length > 0 ? fields : undefined;
}

export function serializeErrorChain(error: unknown): LoggedError[] {
	const errors: LoggedError[] = [];
	const seen = new WeakSet<object>();
	let current: unknown = error;

	while (current !== undefined && current !== null && errors.length < MAX_CAUSE_DEPTH) {
		if (typeof current !== 'object') {
			errors.push({ name: typeof current, message: sanitizeMessage(errorMessage(current)) });
			break;
		}

		if (seen.has(current)) break;
		seen.add(current);

		const name = readProperty(current, 'name');
		const stack = readProperty(current, 'stack');
		const constructor = readProperty(current, 'constructor');
		const loggedError: LoggedError = {
			name:
				typeof name === 'string'
					? name
					: typeof constructor === 'function' && constructor.name
						? constructor.name
						: 'Error',
			message: sanitizeMessage(errorMessage(current))
		};

		if (typeof stack === 'string') loggedError.stack = sanitizeMessage(stack);

		const database = databaseFields(current);
		if (database) loggedError.database = database;

		errors.push(loggedError);
		current = readProperty(current, 'cause');
	}

	return errors;
}
