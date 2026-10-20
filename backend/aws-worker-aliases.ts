import { createRequire } from 'node:module';

// Workers have fetch and Web Crypto but no DOMParser. The SDK's public CommonJS
// entry provides its DOM-free XML parser; keep the rest of the browser runtime.
const require = createRequire(import.meta.url);
export const awsWorkerAliases = {
	'@aws-sdk/xml-builder': require.resolve('@aws-sdk/xml-builder')
};
