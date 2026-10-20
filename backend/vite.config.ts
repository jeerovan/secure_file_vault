import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { awsWorkerAliases } from './aws-worker-aliases';

export default defineConfig({
	resolve: { alias: awsWorkerAliases },
	plugins: [tailwindcss(), sveltekit()]
});
