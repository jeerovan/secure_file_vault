<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.png';
	import '@fontsource-variable/inter';
	let { children } = $props();
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<title>FiFe — Secure Cloud Backup</title>
	<meta
		name="description"
		content="Encrypted cloud backup with BYOK, multi-cloud support, and a premium file explorer."
	/>
</svelte:head>
{@render children()}
