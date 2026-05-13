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
		SmartphoneIcon,
		TerminalIcon,
		ArrowRightIcon
	} from 'lucide-svelte';

	const providers = ['Oracle', 'Cloudflare R2', 'Backblaze B2', 'IDrive E2', 'S3 Compatible'];
</script>

<svelte:head>
	<title>FiFe — Open-Source Secure Cloud Backup</title>
	<meta
		name="description"
		content="Compare FiFe to standard cloud storage: Open-source, cross-platform auto-sync with encryption stronger than AES-256. Leverage 50GB free from providers like Backblaze B2/Cloudflare R2. No metadata stored. Built on Cloudflare Workers & Neon PostgreSQL."
	/>
</svelte:head>

<section class="section-space">
	<div class="container-shell grid items-center gap-10 lg:grid-cols-[1.05fr_0.95fr]">
		<div>
			<div class="badge">
				<Sparkles class="h-3.5 w-3.5" />
				Open-source zero-knowledge encrypted backup
			</div>

			<h1
				class="mt-6 max-w-4xl text-4xl leading-tight font-semibold tracking-tight text-white md:text-6xl"
			>
				Uncompromising security with a file explorer people actually love using.
			</h1>

			<p class="mt-6 max-w-2xl text-lg leading-8 text-white/70">
				Protect your files with BYOK encryption, enjoy seamless cross-platform support with
				auto-sync, and manage everything through a sleek interface built for speed, clarity, and
				absolute data privacy.
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
				<div class="badge"><Check class="h-3.5 w-3.5" /> 50GB via R2/B2</div>
				<div class="badge"><Check class="h-3.5 w-3.5" /> Cross-platform auto-sync</div>
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
						Cross-platform sync
					</div>
				</div>

				<div class="rounded-2xl border border-white/10 bg-black/30 p-4">
					<div class="text-xs tracking-[0.2em] text-white/45 uppercase">Encryption</div>
					<div class="mt-2 text-sm font-medium text-white">Stronger than AES-256</div>
				</div>

				<div class="rounded-2xl border border-white/10 bg-black/30 p-4">
					<div class="text-xs tracking-[0.2em] text-white/45 uppercase">Privacy</div>
					<div class="mt-2 text-sm font-medium text-white">No metadata stored</div>
				</div>
			</div>
		</div>
	</div>
</section>

<section class="pb-8">
	<div class="container-shell">
		<div class="glass-card p-6 lg:p-8">
			<div class="section-label">Trusted integrations & up to 50GB Free</div>
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
			users the control they expect from serious open-source backup software.
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
					<h3 class="mt-5 text-xl font-semibold text-white">Cross-platform auto-sync</h3>
					<p class="mt-3 text-white/70">
						Enjoy seamless cross-platform support with auto-sync. Changes are encrypted locally and
						synced automatically, so every device stays current.
					</p>
				</div>

				<div class="grid-card">
					<div class="feature-icon">
						<ServerCog class="h-6 w-6" />
					</div>
					<h3 class="mt-5 text-xl font-semibold text-white">Bring your own storage & 50GB</h3>
					<p class="mt-3 text-white/70">
						Leverage up to 50GB of free tier storage offered by providers like Backblaze B2 or
						Cloudflare R2, preventing single-vendor lock-in.
					</p>
				</div>

				<div class="grid-card">
					<div class="feature-icon">
						<KeyRound class="h-6 w-6" />
					</div>
					<h3 class="mt-5 text-xl font-semibold text-white">Bring your own key (BYOK)</h3>
					<p class="mt-3 text-white/70">
						You control the master key. Combined with decentralized storage, this ensures users
						completely own their encrypted data.
					</p>
				</div>
			</div>
		</div>
	</div>
</section>

<section id="security" class="section-space pt-8">
	<div class="container-shell grid gap-8 lg:grid-cols-[1.1fr_1.05fr]">
		<div class="glass-card flex flex-col justify-center p-4">
			<img
				src="https://images.fife.jeero.one/encryption-flow-explain.webp"
				alt="Encryption diagram placeholder"
				class="rounded-[1.5rem] border border-white/10"
			/>
		</div>

		<div class="flex items-center">
			<div>
				<div class="section-label">FiFe vs Standard Cloud Storage</div>
				<h2 class="section-title">Objective data privacy superiority you can verify.</h2>
				<p class="section-copy">
					Standard cloud providers hold your keys and harvest your file data. FiFe is an open-source
					alternative built on absolute zero-knowledge principles.
				</p>

				<div class="mt-8 grid gap-4">
					<div class="glass-card p-5">
						<div class="flex items-start gap-4">
							<div class="feature-icon">
								<Lock class="h-5 w-5" />
							</div>
							<div>
								<h3 class="text-lg font-semibold text-white">Stronger than standard AES-256</h3>
								<p class="mt-2 text-white/70">
									Data is encrypted before leaving the user device using modern cryptographic
									standards that are objectively stronger than the AES-256 encryption which other
									service providers normally use.
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
								<h3 class="text-lg font-semibold text-white">No metadata stored</h3>
								<p class="mt-2 text-white/70">
									Unlike standard cloud storage solutions that track your activity, FiFe does not
									store file metadata like others do, ensuring your folder structures and file sizes
									remain completely private.
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
								<h3 class="text-lg font-semibold text-white">Advanced Tech Stack</h3>
								<p class="mt-2 text-white/70">
									Our architecture routes the domain directly through Cloudflare Workers and
									Hyperdrive connected to a Neon.tech PostgreSQL database. This eliminates the need
									for certificate pinning and Cloudflare channels, maximizing backend security.
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
	<!-- Existing Workflow Section untouched to maintain design rhythm -->
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
					S3-compatible provider to claim your storage.
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
					with our cross-platform auto-sync.
				</p>
			</div>
		</div>
	</div>
</section>

<section id="download" class="section-space pt-8">
	<!-- Existing Download Section untouched -->
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
			</div>

			<div class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
				<!-- Windows -->
				<a
					href="https://github.com/jeerovan/secure_file_vault/releases"
					target="_blank"
					class="group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
				>
					<div class="flex items-center gap-3">
						<AppWindowIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="flex items-center gap-2 font-medium text-white">
							Windows
							<ArrowRightIcon
								class="h-4 w-4 text-white/50 transition-colors group-hover:text-white"
							/>
						</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Native-feeling backup and explorer workflow.</p>
				</a>

				<!-- macOS -->
				<a
					href="https://apps.apple.com/app/id6765812250"
					class="group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
				>
					<div class="flex items-center gap-3">
						<AppWindowMacIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="flex items-center gap-2 font-medium text-white">
							macOS
							<ArrowRightIcon
								class="h-4 w-4 text-white/50 transition-colors group-hover:text-white"
							/>
						</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Minimal, polished, and optimized for daily use.</p>
				</a>

				<!-- Android -->
				<a
					href="https://play.google.com/store/apps/details?id=com.jeerovan.fife"
					target="_blank"
					class="group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
				>
					<div class="flex items-center gap-3">
						<SmartphoneIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="flex items-center gap-2 font-medium text-white">
							Android
							<ArrowRightIcon
								class="h-4 w-4 text-white/50 transition-colors group-hover:text-white"
							/>
						</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Encrypted sync with a clean mobile-first UI.</p>
				</a>

				<!-- iOS -->
				<a
					href="https://apps.apple.com/app/id6765812250"
					class="group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
				>
					<div class="flex items-center gap-3">
						<SmartphoneIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="flex items-center gap-2 font-medium text-white">
							iOS
							<ArrowRightIcon
								class="h-4 w-4 text-white/50 transition-colors group-hover:text-white"
							/>
						</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Fast access to protected files on the go.</p>
				</a>

				<!-- Linux -->
				<a
					href="https://github.com/jeerovan/secure_file_vault/releases"
					target="_blank"
					class="group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
				>
					<div class="flex items-center gap-3">
						<TerminalIcon class="h-5 w-5 text-[#FF6B6B]" />
						<div class="flex items-center gap-2 font-medium text-white">
							Linux
							<ArrowRightIcon
								class="h-4 w-4 text-white/50 transition-colors group-hover:text-white"
							/>
						</div>
					</div>
					<p class="mt-3 text-sm text-white/65">Powerful command-line and desktop sync support.</p>
				</a>
			</div>
		</div>
	</div>
</section>
