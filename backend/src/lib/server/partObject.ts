import { and, eq } from 'drizzle-orm';
import type { Db, Tx } from './db';
import { file, part } from './db/schema';
import { FileKeys, PartKeys } from './db/keys';

export function isVaultPartName(value: unknown): value is string {
	return typeof value === 'string' && /^[A-Za-z0-9_-]{43}_[1-9][0-9]*$/.test(value);
}

export function isManagedPartName(value: unknown): value is string {
	return (
		typeof value === 'string' &&
		/^[A-Za-z0-9_-]{43}_[1-9][0-9]*~[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
			value
		)
	);
}

/** Logical part IDs stay unchanged for old clients. Never accept another
 * account, generation, or logical part through a stored location override. */
export function storedPartObjectKey(prefix: string, name: string, data: unknown): string {
	if (!isVaultPartName(name)) throw new Error('invalid_part_location');
	const canonical = `${prefix}${name}`;
	if (typeof data === 'string') data = JSON.parse(data);
	const location = (data as Record<string, unknown> | null)?.managedObjectKey;
	if (location === undefined || location === canonical) return canonical;
	if (
		typeof location === 'string' &&
		location.startsWith(`${canonical}~`) &&
		isManagedPartName(location.slice(prefix.length))
	)
		return location;
	throw new Error('invalid_part_location');
}

export async function getPartObjectKey(
	db: Db | Tx,
	userId: number,
	storageId: number,
	name: string,
	prefix: string
) {
	if (!isVaultPartName(name)) throw new Error('invalid_part_location');
	const separator = name.lastIndexOf('_');
	const [entry] = await db
		.select({ data: part[PartKeys.JSON] })
		.from(part)
		.innerJoin(file, eq(part[PartKeys.FILE_ID], file[FileKeys.ID]))
		.where(
			and(
				eq(file[FileKeys.USER_ID], userId),
				eq(part[PartKeys.USER_ID], userId),
				eq(file[FileKeys.STORAGE_ID], storageId),
				eq(file[FileKeys.FILE_HASH], name.slice(0, separator)),
				eq(part[PartKeys.PART_NUMBER], Number(name.slice(separator + 1))),
				eq(file[FileKeys.DELETED], 0),
				eq(part[PartKeys.DELETED], 0)
			)
		)
		.limit(1);
	return storedPartObjectKey(prefix, name, entry?.data);
}

export function referencesPartObject(key: string, name: string, data: unknown): boolean {
	if (typeof data === 'string') data = JSON.parse(data);
	const location = (data as Record<string, unknown> | null)?.managedObjectKey;
	return location === key || (location === undefined && key.endsWith(`/${name}`));
}
