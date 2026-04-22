<script lang="ts">
	import {
		Check,
		Cloud,
		CloudCog,
		Download,
		FolderKanban,
		KeyRound,
		Lock,
		MonitorSmartphone,
		RefreshCcw,
		ServerCog,
		Sparkles,
		AppWindowIcon,
		AppWindowMacIcon,
		SmartphoneIcon
	} from 'lucide-svelte';

	const providers = ['Oracle', 'Cloudflare R2', 'Backblaze B2', 'IDrive E2', 'S3 Compatible'];
</script>

<svelte:head>
	<title>FiFe — Secure Cloud Backup</title>
	<meta
		name="description"
		content="Encrypted cloud backup with BYOK, multi-cloud support, and a premium file explorer."
	/>
</svelte:head>

<section class="section-space">
	<div class="container-shell grid items-center gap-10 lg:grid-cols-[1.05fr_0.95fr]">
		<div>
			<div class="badge">
				<Sparkles class="h-3.5 w-3.5" />
				Zero-knowledge encrypted cloud backup
			</div>

			<h1
				class="mt-6 max-w-4xl text-4xl leading-tight font-semibold tracking-tight text-white md:text-6xl"
			>
				Uncompromising security with a file explorer people actually love using.
			</h1>

			<p class="mt-6 max-w-2xl text-lg leading-8 text-white/70">
				Protect your files with BYOK encryption, sync them in real time across devices, and manage
				everything through a sleek interface built for speed, clarity, and trust.
			</p>

			<div class="mt-8 flex flex-col gap-3 sm:flex-row">
				<a href="#download" class="btn-primary">
					<Download class="mr-2 h-4 w-4" />
					Download now
				</a>

				<a href="#security" class="btn-secondary">
					<Lock class="mr-2 h-4 w-4" />
					See how security works
				</a>
			</div>

			<div class="mt-8 flex flex-wrap gap-3">
				<div class="badge"><Check class="h-3.5 w-3.5" /> BYOK encryption</div>
				<div class="badge"><Check class="h-3.5 w-3.5" /> Multi-cloud support</div>
				<div class="badge"><Check class="h-3.5 w-3.5" /> Cross-platform sync</div>
			</div>
		</div>

		<div class="glass-card relative overflow-hidden p-4 lg:p-5">
			<div
				class="absolute inset-x-0 top-0 h-28 bg-gradient-to-b from-[#FF4040]/20 to-transparent"
			></div>

			<img
				src="https://images.fife.jeero.one/fife-explorer-desktop.webp"
				alt="FiFe explorer UI placeholder"
				class="h-auto w-full rounded-[1.4rem] border border-white/10 object-cover"
			/>

			<div class="mt-4 grid gap-4 sm:grid-cols-3">
				<div class="rounded-2xl border border-white/10 bg-black/30 p-4">
					<div class="text-xs tracking-[0.2em] text-white/45 uppercase">Status</div>
					<div class="mt-2 flex items-center gap-2 text-sm font-medium text-white">
						<span class="h-2.5 w-2.5 rounded-full bg-emerald-400"></span>
						Sync active
					</div>
				</div>

				<div class="rounded-2xl border border-white/10 bg-black/30 p-4">
					<div class="text-xs tracking-[0.2em] text-white/45 uppercase">Encryption</div>
					<div class="mt-2 text-sm font-medium text-white">Zero-knowledge + BYOK</div>
				</div>

				<div class="rounded-2xl border border-white/10 bg-black/30 p-4">
					<div class="text-xs tracking-[0.2em] text-white/45 uppercase">Storage</div>
					<div class="mt-2 text-sm font-medium text-white">Your cloud, your rules</div>
				</div>
			</div>
		</div>
	</div>
</section>

<section class="pb-8">
	<div class="container-shell">
		<div class="glass-card p-6 lg:p-8">
			<div class="section-label">Trusted integrations</div>
			<div class="mt-6 grid grid-cols-2 gap-3 text-center sm:grid-cols-3 lg:grid-cols-5">
				{#each providers as provider}
					<div
						class="rounded-2xl border border-white/10 bg-white/[0.04] px-4 py-5 text-sm font-medium text-white/80"
					>
						{provider}
					</div>
				{/each}
			</div>
		</div>
	</div>
</section>

<section id="features" class="section-space">
	<div class="container-shell">
		<div class="section-label">Core features</div>
		<h2 class="section-title">Built for privacy-first workflows without sacrificing elegance.</h2>
		<p class="section-copy">
			Everything is designed to feel premium, calm, and frictionless while still giving advanced
			users the control they expect from serious backup software.
		</p>

		<div class="mt-12 grid gap-6 lg:grid-cols-12">
			<div class="grid-card lg:col-span-7">
				<div class="feature-icon">
					<FolderKanban class="h-6 w-6" />
				</div>
				<h3 class="mt-5 text-2xl font-semibold text-white">A truly exceptional file explorer</h3>
				<p class="mt-3 max-w-2xl text-white/70">
					Navigate encrypted content through a polished interface with clean hierarchy, fast search,
					thoughtful spacing, and file management interactions that feel native on every platform.
				</p>

				<div class="mt-6 overflow-hidden rounded-[1.5rem] border border-white/10 bg-black/30 p-3">
					<img
						src="https://images.fife.jeero.one/fife-explorer-options.webp"
						alt="File explorer placeholder"
						class="h-auto w-full rounded-[1.1rem]"
					/>
				</div>
			</div>

			<div class="grid gap-6 lg:col-span-5">
				<div class="grid-card">
					<div class="feature-icon">
						<RefreshCcw class="h-6 w-6" />
					</div>
					<h3 class="mt-5 text-xl font-semibold text-white">Real-time auto-sync</h3>
					<p class="mt-3 text-white/70">
						Changes are encrypted locally and synced automatically, so every device stays current
						without manual upload rituals.
					</p>
				</div>

				<div class="grid-card">
					<div class="feature-icon">
						<ServerCog class="h-6 w-6" />
					</div>
					<h3 class="mt-5 text-xl font-semibold text-white">Multi-cloud by design</h3>
					<p class="mt-3 text-white/70">
						Connect the storage providers you trust and keep infrastructure flexibility instead of
						getting locked into a single vendor.
					</p>
				</div>

				<div class="grid-card">
					<div class="feature-icon">
						<KeyRound class="h-6 w-6" />
					</div>
					<h3 class="mt-5 text-xl font-semibold text-white">Bring your own key</h3>
					<p class="mt-3 text-white/70">
						You control the master key, which means control over access never leaves your hands.
					</p>
				</div>
			</div>
		</div>
	</div>
</section>

<section id="security" class="section-space pt-8">
	<div class="container-shell grid gap-8 lg:grid-cols-[1.1fr_1.05fr]">
		<div class="glass-card p-4">
			<img
				src="https://images.fife.jeero.one/encryption-flow-explain.webp"
				alt="Encryption diagram placeholder"
				class="rounded-[1.5rem] border border-white/10"
			/>
		</div>

		<div class="flex items-center">
			<div>
				<div class="section-label">Security deep dive</div>
				<h2 class="section-title">
					Zero-knowledge security, explained like a product people can trust.
				</h2>
				<p class="section-copy">
					Your files are encrypted before they leave your device. The cloud only receives protected
					ciphertext, and with BYOK, the critical secret remains under your control.
				</p>

				<div class="mt-8 grid gap-4">
					<div class="glass-card p-5">
						<div class="flex items-start gap-4">
							<div class="feature-icon">
								<Lock class="h-5 w-5" />
							</div>
							<div>
								<h3 class="text-lg font-semibold text-white">Local-first encryption</h3>
								<p class="mt-2 text-white/70">
									Files are protected before upload, reducing trust assumptions around the storage
									layer.
								</p>
							</div>
						</div>
					</div>

					<div class="glass-card p-5">
						<div class="flex items-start gap-4">
							<div class="feature-icon">
								<KeyRound class="h-5 w-5" />
							</div>
							<div>
								<h3 class="text-lg font-semibold text-white">BYOK architecture</h3>
								<p class="mt-2 text-white/70">
									You generate and hold the key material, giving advanced users stronger ownership
									and operational clarity.
								</p>
							</div>
						</div>
					</div>

					<div class="glass-card p-5">
						<div class="flex items-start gap-4">
							<div class="feature-icon">
								<CloudCog class="h-5 w-5" />
							</div>
							<div>
								<h3 class="text-lg font-semibold text-white">Storage provider independence</h3>
								<p class="mt-2 text-white/70">
									Security and storage are decoupled, so you can choose performance, region, and
									cost based on your own requirements.
								</p>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
</section>

<section id="workflow" class="section-space">
	<div class="container-shell">
		<div class="section-label">How it works</div>
		<h2 class="section-title">Start syncing in three easy steps.</h2>
		<p class="section-copy">
			The flow is intentionally simple so the product feels approachable, even though the foundation
			is built for serious privacy.
		</p>

		<div class="mt-12 grid gap-6 lg:grid-cols-3">
			<div class="grid-card">
				<div class="feature-icon">
					<Cloud class="h-6 w-6" />
				</div>
				<div class="mt-6 text-sm font-semibold text-[#FF8080]">Step 1</div>
				<h3 class="mt-2 text-xl font-semibold text-white">Connect your storage</h3>
				<p class="mt-3 text-white/70">
					Add your preferred backend such as Oracle Object Storage, Cloudflare R2, Backblaze, or any
					S3-compatible provider.
				</p>
			</div>

			<div class="grid-card">
				<div class="feature-icon">
					<KeyRound class="h-6 w-6" />
				</div>
				<div class="mt-6 text-sm font-semibold text-[#FF8080]">Step 2</div>
				<h3 class="mt-2 text-xl font-semibold text-white">Create your encryption key</h3>
				<p class="mt-3 text-white/70">
					Set up your key ownership model and keep control of the secrets that unlock your data.
				</p>
			</div>

			<div class="grid-card">
				<div class="feature-icon">
					<MonitorSmartphone class="h-6 w-6" />
				</div>
				<div class="mt-6 text-sm font-semibold text-[#FF8080]">Step 3</div>
				<h3 class="mt-2 text-xl font-semibold text-white">Sync and explore</h3>
				<p class="mt-3 text-white/70">
					Back up automatically, browse beautifully, and manage your files across desktop and mobile
					with one consistent experience.
				</p>
			</div>
		</div>
	</div>
</section>

<section id="download" class="section-space pt-8">
	<div class="container-shell">
		<div class="glass-card overflow-hidden p-8 lg:p-10">
			<div class="grid items-center gap-8 lg:grid-cols-[1fr_auto]">
				<div>
					<div class="section-label">Download</div>
					<h2 class="mt-4 text-3xl font-semibold tracking-tight text-white md:text-5xl">
						Your encrypted vault, available across your devices.
					</h2>
					<p class="mt-4 max-w-2xl text-base leading-7 text-white/70 md:text-lg">
						Install FiFe on desktop and mobile, connect your cloud, and keep everything in sync with
						a backup experience that feels premium from the first click.
					</p>
				</div>

				<a href="/" class="btn-primary">
					<Download class="mr-2 h-4 w-4" />
					Download now
				</a>
			</div>

			<div class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
				<div class="rounded-3xl border border-white/10 bg-white/5 p-5">
					<div class="flex items-center gap-3">
						<AppWindowIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="font-medium text-white">Windows</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Native-feeling backup and explorer workflow.</p>
				</div>

				<div class="rounded-3xl border border-white/10 bg-white/5 p-5">
					<div class="flex items-center gap-3">
						<AppWindowMacIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="font-medium text-white">macOS</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Minimal, polished, and optimized for daily use.</p>
				</div>

				<div class="rounded-3xl border border-white/10 bg-white/5 p-5">
					<div class="flex items-center gap-3">
						<SmartphoneIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="font-medium text-white">Android</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Encrypted sync with a clean mobile-first UI.</p>
				</div>

				<div class="rounded-3xl border border-white/10 bg-white/5 p-5">
					<div class="flex items-center gap-3">
						<SmartphoneIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="font-medium text-white">iOS</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Fast access to protected files on the go.</p>
				</div>
			</div>
		</div>
	</div>
</section>
