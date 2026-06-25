<script lang="ts">
	import { onMount } from 'svelte';
	import gsap from 'gsap';
	import { ScrollTrigger } from 'gsap/dist/ScrollTrigger';
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

	onMount(() => {
		gsap.registerPlugin(ScrollTrigger);

		const runHeroAnimations = () => {
			// Initialize starting states explicitly
			gsap.set('.hero-title', { opacity: 0, y: 60 });
			gsap.set('.hero-subtitle', { opacity: 0, y: 30 });
			gsap.set('.hero-image', { opacity: 0, scale: 0.8 });

			// Animate to final states
			gsap.to('.hero-title', {
				opacity: 1,
				y: 0,
				duration: 1.2,
				ease: 'power4.out'
			});

			gsap.to('.hero-subtitle', {
				opacity: 1,
				y: 0,
				duration: 1,
				ease: 'power3.out',
				delay: 0.3
			});

			gsap.to('.hero-image', {
				opacity: 1,
				scale: 1,
				duration: 1.5,
				ease: 'expo.out',
				delay: 0.5
			});
		};

		const heroImg = document.querySelector('.hero-image img');
		if (heroImg) {
			if (heroImg.complete) {
				runHeroAnimations();
			} else {
				heroImg.addEventListener('load', runHeroAnimations);
			}
		} else {
			runHeroAnimations();
		}

		// Feature Cards Stagger - Scoped to #features
		gsap.from('#features .grid-card', {
			scrollTrigger: {
				trigger: '#features .grid-card',
				start: 'top 85%',
			},
			y: 40,
			opacity: 0,
			stagger: 0.15,
			duration: 0.8,
			ease: 'power2.out'
		});

		// Security Image Scale & Fade - Scoped to #security
		gsap.from('#security .security-img', {
			scrollTrigger: {
				trigger: '#security .security-img',
				start: 'top 90%',
				end: 'top 30%',
				scrub: 1,
			},
			scale: 0.8,
			opacity: 0.4,
			ease: 'none'
		});

		// Security Cards - Scoped to #security
		gsap.from('#security .security-card', {
			scrollTrigger: {
				trigger: '#security .security-card',
				start: 'top 85%',
			},
			x: -30,
			opacity: 0,
			stagger: 0.2,
			duration: 0.8,
			ease: 'power2.out'
		});

		// Workflow Cards - Scoped to #workflow
		gsap.from('#workflow .workflow-card', {
			scrollTrigger: {
				trigger: '#workflow .workflow-card',
				start: 'top 85%',
			},
			y: 30,
			opacity: 0,
			stagger: 0.2,
			duration: 0.8,
			ease: 'power2.out'
		});

		// Download Cards - Scoped to #download
		gsap.from('#download .download-card', {
			scrollTrigger: {
				trigger: '#download .download-card',
				start: 'top 90%',
			},
			y: 20,
			opacity: 0,
			stagger: 0.1,
			duration: 0.6,
			ease: 'power2.out'
		});

		// Magnetic Button Effect
		const buttons = document.querySelectorAll('.btn-magnetic');
		buttons.forEach(btn => {
			btn.addEventListener('mousemove', (e) => {
				const rect = btn.getBoundingClientRect();
				const x = e.clientX - rect.left - rect.width / 2;
				const y = e.clientY - rect.top - rect.height / 2;
				gsap.to(btn, {
					x: x * 0.3,
					y: y * 0.3,
					duration: 0.3,
					ease: 'power2.out'
				});
			});
			btn.addEventListener('mouseleave', () => {
				gsap.to(btn, {
					x: 0,
					y: 0,
					duration: 0.5,
					ease: 'elastic.out(1, 0.3)'
				});
			});
		});
	});
</script>

<svelte:head>
	<title>FiFe — Open-Source Secure Cloud Backup</title>
	<meta
		name="description"
		content="Compare FiFe to standard cloud storage: Open-source, cross-platform auto-sync with encryption superior than AES-256. Leverage 50GB free from providers like Backblaze B2/Cloudflare R2. No metadata stored. Built on Cloudflare Workers & Neon PostgreSQL."
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
				style="opacity: 0"
				class="hero-title mt-6 max-w-4xl text-4xl leading-tight font-semibold tracking-tight text-white md:text-6xl"
			>
				Uncompromising security with a file explorer people actually love using.
			</h1>

			<p
				style="opacity: 0"
				class="hero-subtitle mt-6 max-w-2xl text-lg leading-8 text-white/70"
			>
				Protect your files with BYOK encryption, enjoy seamless cross-platform support with
				auto-sync, and manage everything through a sleek interface built for speed, clarity, and
				absolute data privacy.
			</p>

			<div class="mt-8 flex flex-col gap-3 sm:flex-row">
				<a href="#download" class="btn-primary btn-magnetic">
					<Download class="mr-2 h-4 w-4" />
					Download now
				</a>

				<a href="#security" class="btn-secondary btn-magnetic">
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

		<div
			style="opacity: 0"
			class="hero-image glass-card relative overflow-hidden p-4 lg:p-5"
		>
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
					<div class="mt-2 text-sm font-medium text-white">Superior than AES-256</div>
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
				class="security-img rounded-[1.5rem] border border-white/10"
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
					<div class="security-card glass-card p-5">
							<div class="flex items-start gap-5">
								<div class="feature-icon">
									<Lock class="h-6 w-6" />
								</div>
								<div>
									<h3 class="text-lg font-semibold text-white">Superior than standard AES-256</h3>
									<p class="mt-2 text-white/70">
										Data is encrypted before leaving the user device using modern cryptographic
										standards that are objectively superior than the AES-256 encryption which other
										service providers normally use.
									</p>
								</div>
							</div>
						</div>

						<div class="security-card glass-card p-5">
							<div class="flex items-start gap-4">
								<div class="feature-icon">
									<KeyRound class="h-6 w-6" />
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

						<div class="security-card glass-card p-5">
							<div class="flex items-start gap-4">
								<div class="feature-icon">
									<CloudCog class="h-6 w-6" />
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
			<div class="workflow-card grid-card">
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

			<div class="workflow-card grid-card">
				<div class="feature-icon">
					<KeyRound class="h-6 w-6" />
				</div>
				<div class="mt-6 text-sm font-semibold text-[#FF8080]">Step 2</div>
				<h3 class="mt-2 text-xl font-semibold text-white">Create your encryption key</h3>
				<p class="mt-3 text-white/70">
					Set up your key ownership model and keep control of the secrets that unlock your data.
				</p>
			</div>

			<div class="workflow-card grid-card">
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
					class="download-card group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
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
					class="download-card group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
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
					class="download-card group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
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
					class="download-card group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
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
					class="download-card group block cursor-pointer rounded-3xl border border-white/10 bg-white/5 p-5 transition-colors hover:bg-white/10"
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
