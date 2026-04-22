<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.png';
	import '@fontsource-variable/inter';
	import { CodeXml, HardDrive, HardDriveIcon } from 'lucide-svelte';
	let { children } = $props();
	const footerGroups = [
		{
			title: 'Product',
			links: [
				{ title: 'Download', url: '/#download' },
				{ title: 'Platforms', url: '/#download' },
				{ title: 'Integrations', url: '/connect' }
			]
		},
		{
			title: 'Resources',
			links: [
				{ title: 'Documentation', url: '/connect' },
				{ title: 'Security', url: '/#security' },
				{ title: 'Status', url: '/' }
			]
		},
		{
			title: 'Company',
			links: [
				{ title: 'About', url: '/' },
				{ title: 'GitHub', url: '/' },
				{ title: 'Contact', url: '/' }
			]
		},
		{
			title: 'Legal',
			links: [
				{ title: 'Privacy', url: '/' },
				{ title: 'Terms', url: '/' },
				{ title: 'Cookies', url: '/' }
			]
		}
	];
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
					<img
						src="https://images.fife.jeero.one/fife-logo.webp"
						height="30"
						width="30"
						alt="Logo"
					/>
				</div>
				<div>
					<div class="text-sm font-semibold tracking-wide text-white">FiFe</div>
					<div class="text-xs text-white/55">Your private Files Ferry</div>
				</div>
			</a>

			<nav class="hidden items-center gap-8 text-sm text-white/75 md:flex">
				<a href="/#features" class="transition hover:text-white">Features</a>
				<a href="/#security" class="transition hover:text-white">Security</a>
				<a href="/#workflow" class="transition hover:text-white">How it works</a>
				<a href="/#download" class="transition hover:text-white">Download</a>
			</nav>

			<div class="flex items-center gap-3">
				<a href="/connect" class="btn-secondary hidden gap-2 text-primary sm:inline-flex"
					><HardDriveIcon class="h-4 w-4" />Storage</a
				>
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
							<img
								src="https://images.fife.jeero.one/fife-logo.webp"
								height="30"
								width="30"
								alt="Logo"
							/>
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
						<a
							href="https://github.com/jeerovan/secure_file_vault"
							target="_blank"
							class="btn-secondary"
						>
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
										<a href={link.url} class="text-sm text-white/70 transition hover:text-white"
											>{link.title}</a
										>
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
