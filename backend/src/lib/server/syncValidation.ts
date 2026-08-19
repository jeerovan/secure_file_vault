export const syncTables = ['files', 'items', 'parts'] as const;

export type SyncTable = (typeof syncTables)[number];

export function assertSyncTable(value: unknown): asserts value is SyncTable {
	if (!syncTables.includes(value as SyncTable)) {
		throw new Error('Unsupported sync table');
	}
}

export function parseSyncChangeData(value: unknown): Record<string, unknown> {
	const parsed = typeof value === 'string' ? JSON.parse(value) : value;
	if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
		throw new Error('Sync change data must be a JSON object');
	}
	return parsed as Record<string, unknown>;
}
