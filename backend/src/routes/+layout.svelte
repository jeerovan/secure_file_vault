<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.png';
	import '@fontsource-variable/inter';
	import { enhance } from '$app/forms';
	import {
		ArrowRight,
		ChevronDown,
		LogOut,
		CodeXml,
		HardDrive,
		HardDriveIcon
	} from 'lucide-svelte';
	let { data, children } = $props();
	const footerGroups = [
		{
			title: 'Product',
			links: ['Download', 'Platforms', 'Integrations']
		},
		{
			title: 'Resources',
			links: ['Documentation', 'Security', 'Status']
		},
		{
			title: 'Company',
			links: ['About', 'GitHub', 'Contact']
		},
		{
			title: 'Legal',
			links: ['Privacy', 'Terms', 'Cookies']
		}
	];
	let isDropdownOpen = $state(false);

	// Function to mask email (e.g., user@example.com -> us***@example.com)
	function maskEmail(email: string) {
		if (!email) return '';
		const [localPart, domain] = email.split('@');
		if (localPart.length <= 2) return `${localPart}***@${domain}`;

		const firstTwo = localPart.slice(0, 2);
		return `${firstTwo}***@${domain}`;
	}
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

<div class="relative overflow-x-hidden">
	<div
		class="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_30%_10%,rgba(255,64,64,0.12),transparent_22%),radial-gradient(circle_at_85%_12%,rgba(255,255,255,0.08),transparent_18%)]"
	></div>

	<header class="sticky top-0 z-50 border-b border-white/10 bg-black/35 backdrop-blur-2xl">
		<div class="container-shell flex h-18 items-center justify-between py-4">
			<a href="/" class="flex items-center gap-3">
				<div
					class="flex items-center justify-center rounded-xl shadow-[0_10px_30px_rgba(255,64,64,0.28)]"
				>
					<img src="/images/fife-logo.webp" height="30" width="30" alt="Logo" />
				</div>
				<div>
					<div class="text-sm font-semibold tracking-wide text-white">FiFe</div>
					<div class="text-xs text-white/55">Encrypted backup, beautifully designed</div>
				</div>
			</a>

			<nav class="hidden items-center gap-8 text-sm text-white/75 md:flex">
				<a href="/#features" class="transition hover:text-white">Features</a>
				<a href="/#security" class="transition hover:text-white">Security</a>
				<a href="/#workflow" class="transition hover:text-white">How it works</a>
				<a href="/#download" class="transition hover:text-white">Download</a>
			</nav>

			<div class="flex items-center gap-3">
				{#if data?.user}
					<a href="/connect" class="btn-secondary hidden gap-2 text-primary sm:inline-flex"
						><HardDriveIcon class="h-4 w-4" />Storage</a
					>

					<!-- User Dropdown -->
					<div class="relative">
						<button
							class="flex items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-white transition hover:bg-white/10"
							onclick={() => (isDropdownOpen = !isDropdownOpen)}
						>
							{maskEmail(data.user.email)}
							<ChevronDown
								class="h-4 w-4 text-white/50 transition-transform {isDropdownOpen
									? 'rotate-180'
									: ''}"
							/>
						</button>

						{#if isDropdownOpen}
							<div
								class="ring-opacity-5 absolute right-0 mt-2 w-48 origin-top-right rounded-lg border border-white/10 bg-zinc-900 py-1 shadow-xl ring-1 ring-black"
							>
								<a
									href="/connect"
									class="inline-flex w-full gap-2 px-4 py-2 text-sm text-white/75 transition hover:bg-white/10 hover:text-white sm:hidden"
									><HardDriveIcon class="h-4 w-4" /> Storage</a
								>
								<form
									action="/login?/signout"
									method="POST"
									use:enhance={() => {
										// 1. Prevent the dropdown from unmounting the form during the network request
										isDropdownOpen = true;

										return async ({ update }) => {
											// 2. Force SvelteKit to re-run layout.ts and layout.server.ts to clear the user data
											await update({ invalidateAll: true });

											// 3. Safely close the dropdown now that the redirect has happened
											isDropdownOpen = false;
										};
									}}
								>
									<button
										type="submit"
										class="flex w-full items-center gap-2 px-4 py-2 text-sm text-white/75 transition hover:bg-white/10 hover:text-white"
									>
										<LogOut class="h-4 w-4" />
										Sign out
									</button>
								</form>
							</div>
						{/if}
					</div>
				{:else}
					<a href="/connect" class="btn-secondary hidden gap-2 text-primary sm:inline-flex"
						><HardDriveIcon class="h-4 w-4" />Storage</a
					>
					<a href="/login" class="btn-primary">
						Get started
						<ArrowRight class="ml-2 h-4 w-4" />
					</a>
				{/if}
			</div>
		</div>
	</header>
	{@render children()}
	<footer id="docs" class="border-t border-white/10 py-10">
		<div class="container-shell">
			<div class="grid gap-10 lg:grid-cols-[1.2fr_1fr]">
				<div>
					<a href="/" class="flex items-center gap-3">
						<div class="flex h-10 w-10 items-center justify-center rounded-2xl">
							<img src="/images/fife-logo.webp" height="30" width="30" alt="Logo" />
						</div>
						<div>
							<div class="font-semibold text-white">FiFe</div>
							<div class="text-sm text-white/55">Private cloud backup for people who care.</div>
						</div>
					</a>

					<p class="mt-5 max-w-md text-sm leading-7 text-white/60">
						Secure backup, zero-knowledge architecture, and a refined explorer interface designed to
						make privacy feel effortless.
					</p>

					<div class="mt-6 flex flex-wrap gap-3">
						<a href="/connect" class="btn-secondary">
							<HardDrive class="mr-2 h-4 w-4" />
							Storage
						</a>
						<a href="/" class="btn-secondary">
							<CodeXml class="mr-2 h-4 w-4" />
							GitHub
						</a>
					</div>
				</div>

				<div class="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
					{#each footerGroups as group}
						<div>
							<h3 class="text-sm font-semibold tracking-[0.18em] text-white/45 uppercase">
								{group.title}
							</h3>
							<ul class="mt-4 space-y-3">
								{#each group.links as link}
									<li>
										<a href="/" class="text-sm text-white/70 transition hover:text-white">{link}</a>
									</li>
								{/each}
							</ul>
						</div>
					{/each}
				</div>
			</div>

			<div
				class="mt-10 flex flex-col gap-3 border-t border-white/10 pt-6 text-sm text-white/45 sm:flex-row sm:items-center sm:justify-between"
			>
				<div>© 2026 FiFe. Built with precision. Secured by design.</div>
				<div>Primary accent: #FF4040</div>
			</div>
		</div>
	</footer>
</div>
