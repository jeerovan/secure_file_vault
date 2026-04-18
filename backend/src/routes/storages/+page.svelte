<script lang="ts">
	import { fade } from 'svelte/transition';
	import {
		ArrowDown,
		Cloud,
		CloudLightning,
		Database,
		HardDrive,
		KeyRound,
		Package,
		Server,
		TableProperties
	} from 'lucide-svelte';
	import type { PageData } from './$types';
	type ProviderStep = {
		id: number;
		title: string;
		image: string;
	};
	let { data }: { data: PageData } = $props();
	// Storage providers data with step-by-step images and descriptions
	const providerIcons: Record<number, any> = {
		2: Package,
		3: CloudLightning,
		4: Database,
		5: HardDrive
	};
	const providerSteps: Record<number, ProviderStep[]> = {
		2: [
			{
				id: 1,
				title: '',
				image: '/images/storage/backblaze/guide-1.webp'
			},
			{
				id: 2,
				title: '',
				image: '/images/storage/backblaze/guide-2.webp'
			},
			{
				id: 3,
				title: '',
				image: '/images/storage/backblaze/guide-3.webp'
			},
			{
				id: 4,
				title: '',
				image: '/images/storage/backblaze/guide-4.webp'
			},
			{
				id: 5,
				title: '',
				image: '/images/storage/backblaze/guide-5.webp'
			},
			{
				id: 6,
				title: '',
				image: '/images/storage/backblaze/guide-6.webp'
			},
			{
				id: 7,
				title: '',
				image: '/images/storage/backblaze/guide-7.webp'
			},
			{
				id: 8,
				title: '',
				image: '/images/storage/backblaze/guide-8.webp'
			},
			{
				id: 9,
				title: '',
				image: '/images/storage/backblaze/guide-9.webp'
			}
		],
		3: [
			{
				id: 1,
				title: '',
				image: '/images/storage/cloudflare/guide-1.webp'
			},
			{
				id: 2,
				title: '',
				image: '/images/storage/cloudflare/guide-2.webp'
			},
			{
				id: 3,
				title: '',
				image: '/images/storage/cloudflare/guide-3.webp'
			},
			{
				id: 4,
				title: '',
				image: '/images/storage/cloudflare/guide-4.webp'
			},
			{
				id: 5,
				title: '',
				image: '/images/storage/cloudflare/guide-5.webp'
			},
			{
				id: 6,
				title: '',
				image: '/images/storage/cloudflare/guide-6.webp'
			},
			{
				id: 7,
				title: '',
				image: '/images/storage/cloudflare/guide-7.webp'
			},
			{
				id: 8,
				title: '',
				image: '/images/storage/cloudflare/guide-8.webp'
			},
			{
				id: 9,
				title: '',
				image: '/images/storage/cloudflare/guide-9.webp'
			},
			{
				id: 10,
				title: '',
				image: '/images/storage/cloudflare/guide-10.webp'
			},
			{
				id: 11,
				title: '',
				image: '/images/storage/cloudflare/guide-11.webp'
			},
			{
				id: 12,
				title: '',
				image: '/images/storage/cloudflare/guide-12.webp'
			}
		],
		4: [
			{
				id: 1,
				title: '',
				image: '/images/storage/oracle/guide-1.webp'
			},
			{
				id: 2,
				title: '',
				image: '/images/storage/oracle/guide-2.webp'
			},
			{
				id: 3,
				title: '',
				image: '/images/storage/oracle/guide-3.webp'
			},
			{
				id: 4,
				title: '',
				image: '/images/storage/oracle/guide-4.webp'
			},
			{
				id: 5,
				title: '',
				image: '/images/storage/oracle/guide-5.webp'
			},
			{
				id: 6,
				title: '',
				image: '/images/storage/oracle/guide-6.webp'
			},
			{
				id: 7,
				title: '',
				image: '/images/storage/oracle/guide-7.webp'
			},
			{
				id: 8,
				title: '',
				image: '/images/storage/oracle/guide-8.webp'
			},
			{
				id: 9,
				title: '',
				image: '/images/storage/oracle/guide-9.webp'
			},
			{
				id: 10,
				title: '',
				image: '/images/storage/oracle/guide-10.webp'
			},
			{
				id: 11,
				title: '',
				image: '/images/storage/oracle/guide-11.webp'
			},
			{
				id: 12,
				title: '',
				image: '/images/storage/oracle/guide-12.webp'
			},
			{
				id: 13,
				title: '',
				image: '/images/storage/oracle/guide-13.webp'
			}
		],
		5: [
			{
				id: 1,
				title: '',
				image: '/images/storage/idrive/guide-1.webp'
			},
			{
				id: 2,
				title: '',
				image: '/images/storage/idrive/guide-2.webp'
			},
			{
				id: 3,
				title: '',
				image: '/images/storage/idrive/guide-3.webp'
			},
			{
				id: 4,
				title: '',
				image: '/images/storage/idrive/guide-4.webp'
			},
			{
				id: 5,
				title: '',
				image: '/images/storage/idrive/guide-5.webp'
			},
			{
				id: 6,
				title: '',
				image: '/images/storage/idrive/guide-6.webp'
			},
			{
				id: 7,
				title: '',
				image: '/images/storage/idrive/guide-7.webp'
			},
			{
				id: 8,
				title: '',
				image: '/images/storage/idrive/guide-8.webp'
			},
			{
				id: 9,
				title: '',
				image: '/images/storage/idrive/guide-9.webp'
			}
		]
	};
	let storageProviders = $derived(data.storageProviders);

	// Set the first provider as active by default
	let activeProviderId = $derived<number | null>(
		data.storageProviders.length > 0 ? data.storageProviders[0].id : null
	);

	// Svelte 5 derived state
	let activeProvider = $derived(storageProviders.find((p: any) => p.id === activeProviderId));

	function formatBytes(bytes: number, decimals = 2) {
		if (!+bytes) return '0 Bytes';
		const k = 1024;
		const dm = decimals < 0 ? 0 : decimals;
		const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
		const i = Math.floor(Math.log(bytes) / Math.log(k));
		return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;
	}
</script>

<svelte:head>
	<title>Storages | FiFe Connection Guides</title>
</svelte:head>

<!-- Background Elements -->
<div class="fixed inset-0 -z-10 bg-gradient-to-b from-[#0b0d10] to-[#07090c]"></div>
<div
	class="fixed inset-0 -z-10 bg-[radial-gradient(circle_at_top_right,rgba(255,64,64,0.08),transparent_40%)]"
></div>

<div class="container-shell section-space min-h-screen pt-24 lg:pt-32">
	<!-- Page Header -->
	<header class="max-w-2xl">
		<div class="flex items-center gap-2 text-[#FF4040]">
			<HardDrive class="h-5 w-5" />
			<span class="text-xs font-semibold tracking-[0.2em] uppercase">Documentation</span>
		</div>
		<h1 class="mt-4 text-4xl font-semibold tracking-tight text-white md:text-5xl">
			Connect different storages
		</h1>
		<p class="mt-4 text-lg text-white/60">
			Learn how to generate secure credentials and connect your preferred cloud storage provider to
			your FiFe vault.
		</p>
	</header>

	<!-- Tabbed Navigation -->
	<div class="mt-12 w-full">
		<div class="grid grid-cols-2 gap-2 md:grid-cols-3 lg:grid-cols-4">
			{#each storageProviders as provider}
				<!-- Look up the icon, fallback to Package if not found -->
				{@const TabIcon = providerIcons[provider.id] || Package}

				<button
					class="group flex flex-col items-start gap-3 rounded-2xl border p-4 transition-all duration-200
        {activeProviderId === provider.id
						? 'border-[#FF4040]/30 bg-[#FF4040]/10 text-[#FF4040]'
						: 'border-white/5 bg-white/5 text-white/60 hover:bg-white/10 hover:text-white'}"
					onclick={() => (activeProviderId = provider.id)}
				>
					<div class="flex w-full items-center gap-3 text-sm font-medium">
						<TabIcon
							class="h-4 w-4 shrink-0 {activeProviderId === provider.id
								? 'text-[#FF4040]'
								: 'text-white/40 group-hover:text-white/70'}"
						/>
						<span class="truncate">{provider.title}</span>

						<!-- Show "Added" badge if the user has configured this provider -->
						{#if provider.added === 1}
							<span
								class="ml-auto rounded-full bg-emerald-500/10 px-2 py-0.5 text-[10px] text-emerald-400"
							>
								Added
							</span>
						{/if}
					</div>

					<!-- Storage Metrics -->
					<div
						class="mt-1 flex w-full flex-col gap-1 text-[11px] {activeProviderId === provider.id
							? 'text-[#FF4040]/80'
							: 'text-white/40 group-hover:text-white/60'}"
					>
						<div class="flex w-full justify-between">
							<span>Used:</span>
							<span class="font-medium">{formatBytes(provider.used)}</span>
						</div>
						<div class="flex w-full justify-between">
							<span>Limit:</span>
							<span class="font-medium">{formatBytes(provider.bytes)}</span>
						</div>

						<!-- Optional: Tiny visual progress bar -->
						<div class="mt-1 h-1 w-full overflow-hidden rounded-full bg-black/20">
							<div
								class="h-full rounded-full {activeProviderId === provider.id
									? 'bg-[#FF4040]'
									: 'bg-white/20 group-hover:bg-white/40'}"
								style="width: {provider.bytes > 0 ? (provider.used / provider.bytes) * 100 : 0}%"
							></div>
						</div>
					</div>
				</button>
			{/each}
		</div>
	</div>

	<!-- Content Area with Transition -->
	<div class="relative mt-12 lg:mt-16">
		{#key activeProviderId}
			<div in:fade={{ duration: 300, delay: 100 }} class="max-w-4xl">
				<!-- H2 for the active provider -->
				<div class="mb-10 flex items-center gap-4">
					<div
						class="flex h-12 w-12 items-center justify-center rounded-2xl border border-white/10 bg-white/5 shadow-lg"
					>
						{#if activeProvider}
							{@const ActiveIcon = providerIcons[activeProvider.id] || Package}
							<ActiveIcon class="h-6 w-6 text-white" />
						{/if}
					</div>
					<h2 class="text-2xl font-semibold text-white md:text-3xl">
						Connect <span class="text-[#FF4040]">{activeProvider?.title}</span>
					</h2>
				</div>

				<!-- Step-by-Step Vertical Guide -->
				<div class="relative space-y-12 pb-20">
					{#if activeProvider}
						{@const Steps = providerSteps[activeProvider.id]}
						{#each Steps as step, index}
							<div class="relative grid gap-6 md:grid-cols-[auto_1fr] md:gap-8">
								<!-- Step Number & Connector Line -->
								<div class="flex flex-col items-center">
									<div
										class="z-10 flex aspect-square h-10 w-10 shrink-0 items-center justify-center rounded-full border border-[#FF4040]/30 bg-[#FF4040]/10 text-sm font-bold text-[#FF4040] shadow-[0_0_15px_rgba(255,64,64,0.15)] outline outline-4 outline-[#0b0d10]"
									>
										{step.id}
									</div>

									<div
										class="relative mt-2 flex h-full w-px flex-col items-center bg-gradient-to-b from-[#FF4040]/30 to-white/10 md:min-h-[200px]"
									>
										<div
											class="absolute bottom-4 flex aspect-square h-6 w-6 items-center justify-center rounded-full bg-[#0b0d10]"
										>
											<ArrowDown class="h-3 w-3 text-white/30" />
										</div>
									</div>
								</div>

								<!-- Step Content & Image -->
								<div class="pt-1 pb-8">
									<h3 class="text-xl font-medium text-white">{step.title}</h3>

									<div
										class="mt-6 overflow-hidden rounded-2xl border border-white/10 bg-white/5 p-2 shadow-2xl backdrop-blur-sm"
									>
										<img
											src={step.image}
											alt="Visual guide for {activeProvider.name} step {step.id}"
											class="h-auto w-full rounded-xl border border-white/5 object-cover opacity-90 transition-opacity hover:opacity-100"
											loading="lazy"
										/>
									</div>
								</div>
							</div>
						{/each}
					{/if}
				</div>
			</div>
		{/key}
	</div>
</div>
