// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
import type { KVNamespace } from '@cloudflare/workers-types';
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
		interface Platform {
			env: {
				HYPERDRIVE: Hyperdrive;
				FIFE_AUTH_CACHE: KVNamespace;
			};
		}
	}
}

export {};
