declare module '*cloudflare/_worker.js' {
	const worker: { fetch(request: Request, env: unknown, context: unknown): Promise<Response> };
	export default worker;
}
