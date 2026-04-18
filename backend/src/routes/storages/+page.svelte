<script lang="ts">
	import { fade } from 'svelte/transition';
	import { ArrowDown, Cloud, Database, HardDrive, KeyRound, Server } from 'lucide-svelte';

	// Storage providers data with step-by-step images and descriptions
	const storageProviders = [
		{
			id: 'backblaze',
			name: 'Backblaze B2',
			icon: Database,
			steps: [
				{
					id: 1,
					title: 'Create Application Key',
					description:
						'Log into your Backblaze account, navigate to "Application Keys" in the sidebar, and click the "Add a New Application Key" button.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Backblaze+Step+1:+Create+Key'
				},
				{
					id: 2,
					title: 'Copy Credentials',
					description:
						'Instantly copy your "Key ID" and "Application Key". Warning: The Application Key will only be displayed once.',
					image:
						'https://placehold.co/1200x675/1e293b/e2e8f0?text=Backblaze+Step+2:+Copy+Credentials'
				},
				{
					id: 3,
					title: 'Connect in FiFe',
					description:
						'Open the FiFe app, select Backblaze as your provider, and paste the Key ID and Application Key to establish a secure connection.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Backblaze+Step+3:+Connect+App'
				}
			]
		},
		{
			id: 'cloudflare',
			name: 'Cloudflare R2',
			icon: Cloud,
			steps: [
				{
					id: 1,
					title: 'Create an R2 Bucket',
					description:
						'Open the Cloudflare dashboard, go to R2, and click "Create Bucket". Choose an appropriate region for your backups.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Cloudflare+Step+1:+Create+Bucket'
				},
				{
					id: 2,
					title: 'Generate API Tokens',
					description:
						'Click on "Manage R2 API Tokens" and create a token with "Admin Read & Write" permissions.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Cloudflare+Step+2:+API+Tokens'
				}
			]
		},
		{
			id: 'oracle',
			name: 'Oracle Cloud',
			icon: Server,
			steps: [
				{
					id: 1,
					title: 'Generate Customer Secret Keys',
					description:
						'Click your Profile icon -> User Settings. Under Resources, click "Customer Secret Keys" and generate a new key.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Oracle+Step+1:+Secret+Keys'
				},
				{
					id: 2,
					title: 'Locate Object Storage Namespace',
					description:
						'Find your Tenancy Namespace and Region string to construct your S3-compatible endpoint URL.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Oracle+Step+2:+Namespace'
				},
				{
					id: 3,
					title: 'Configure S3 Compatible Endpoint',
					description:
						"Enter your custom Endpoint URL, Access Key, and Secret Key into FiFe's S3-Compatible connection menu.",
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Oracle+Step+3:+Connect+S3'
				}
			]
		},
		{
			id: 'idrive',
			name: 'IDrive E2',
			icon: Cloud,
			steps: [
				{
					id: 1,
					title: 'Create an R2 Bucket',
					description:
						'Open the Cloudflare dashboard, go to R2, and click "Create Bucket". Choose an appropriate region for your backups.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Cloudflare+Step+1:+Create+Bucket'
				},
				{
					id: 2,
					title: 'Generate API Tokens',
					description:
						'Click on "Manage R2 API Tokens" and create a token with "Admin Read & Write" permissions.',
					image: 'https://placehold.co/1200x675/1e293b/e2e8f0?text=Cloudflare+Step+2:+API+Tokens'
				}
			]
		}
	];

	// Svelte 5 reactive state
	let activeProviderId = $state(storageProviders[0].id);

	// Svelte 5 derived state
	let activeProvider = $derived(storageProviders.find((p) => p.id === activeProviderId));
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
				{@const TabIcon = provider.icon}
				<button
					class="group flex items-center gap-3 rounded-2xl border p-4 text-sm font-medium transition-all duration-200
                {activeProviderId === provider.id
						? 'border-[#FF4040]/30 bg-[#FF4040]/10 text-[#FF4040]'
						: 'border-white/5 bg-white/5 text-white/60 hover:bg-white/10 hover:text-white'}"
					onclick={() => (activeProviderId = provider.id)}
				>
					<TabIcon
						class="h-4 w-4 shrink-0 {activeProviderId === provider.id
							? 'text-[#FF4040]'
							: 'text-white/40 group-hover:text-white/70'}"
					/>
					<span class="truncate">{provider.name}</span>
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
							{@const ActiveIcon = activeProvider.icon}
							<ActiveIcon class="h-6 w-6 text-white" />
						{/if}
					</div>
					<h2 class="text-2xl font-semibold text-white md:text-3xl">
						Connect <span class="text-[#FF4040]">{activeProvider?.name}</span>
					</h2>
				</div>

				<!-- Step-by-Step Vertical Guide -->
				<div class="relative space-y-12 pb-20">
					{#if activeProvider}
						{#each activeProvider.steps as step, index}
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
									<p class="mt-2 text-white/70">{step.description}</p>

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
