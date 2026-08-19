export interface B2FileEntry {
	fileId?: string;
	fileName?: string;
	contentLength?: number;
	contentSha1?: string;
	action?: string;
}

export function findMatchingB2Upload(
	files: B2FileEntry[],
	fileName: string,
	contentSha1: string,
	contentLength: number
): B2FileEntry | undefined {
	return files.find(
		(file) =>
			file.action === 'upload' &&
			file.fileName === fileName &&
			file.contentSha1 === contentSha1 &&
			file.contentLength === contentLength &&
			typeof file.fileId === 'string' &&
			file.fileId.length > 0
	);
}
