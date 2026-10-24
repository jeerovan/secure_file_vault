// Local-only Wrangler launcher for the compiled package smoke test.
// The CLI's outer fetch proxy cannot dispatch native scheduled events. Keep
// the actual Worker's inner address/proxy proof in a private fixture file.
import { writeFile } from 'node:fs/promises';
import { unstable_DevEnv } from 'wrangler';

const [config, envFile, persist, rawPort, controlFile] = process.argv.slice(2);
const port = Number(rawPort);
if (
	!config ||
	!envFile ||
	!persist ||
	!controlFile ||
	!Number.isInteger(port) ||
	port < 1024 ||
	port > 65535
)
	throw new Error('Compiled Worker fixture arguments are required');
const environment = new unstable_DevEnv();
const onReloadComplete = environment.proxy.onReloadComplete.bind(environment.proxy);
environment.proxy.onReloadComplete = (event) => {
	onReloadComplete(event);
	const inner = event.proxyData.userWorkerUrl;
	if (inner.hostname !== '127.0.0.1' || inner.protocol !== 'http:')
		throw new Error('The compiled fixture must remain on loopback');
	void writeFile(
		controlFile,
		JSON.stringify({
			innerUrl: `http://${inner.hostname}:${inner.port}`,
			headers: event.proxyData.headers,
			workerName: event.config.name
		}),
		{ mode: 0o600 }
	).then(() => console.info(`Ready on http://127.0.0.1:${port}`));
};
const worker = await environment.startWorker({
	config,
	envFiles: [envFile],
	sendMetrics: false,
	dev: {
		remote: false,
		server: { hostname: '127.0.0.1', port },
		inspector: false,
		persist,
		watch: false,
		logLevel: 'error'
	}
});
await worker.ready;
for (const signal of ['SIGTERM', 'SIGINT'] as const)
	process.once(signal, () => {
		void worker.dispose().finally(() => process.exit());
	});
