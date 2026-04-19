<script lang="ts">
	import { onMount } from 'svelte';
	import { enhance, applyAction } from '$app/forms';
	import { fade, slide } from 'svelte/transition';
	import {
		ArrowLeft,
		CircleCheck,
		Loader,
		LockKeyhole,
		LogOut,
		Mail,
		MailCheck,
		RectangleEllipsis
	} from 'lucide-svelte';

	let { data, form } = $props();

	let step = $state<'email' | 'otp' | 'signedIn'>('email');
	let email = $state('');
	let otp = $state('');
	let processing = $state(false);
	let errorMessage = $state('');

	let emailInput = $state<HTMLInputElement>();
	let otpInput = $state<HTMLInputElement>();

	onMount(async () => {
		await checkInitialAuthState();
	});

	async function checkInitialAuthState() {
		if (!data.session) {
			const sentOtpAt = parseInt(localStorage.getItem('fife_otpSentAt') || '0', 10);
			const savedEmail = localStorage.getItem('fife_otpSentTo') || '';
			const nowUtc = Date.now();

			if (sentOtpAt > 0 && nowUtc - sentOtpAt < 900000 && savedEmail) {
				email = savedEmail;
				step = 'otp';
				setTimeout(() => otpInput?.focus(), 100);
			}
		} else {
			step = 'signedIn';
		}
	}

	function changeEmail() {
		localStorage.removeItem('fife_otpSentTo');
		localStorage.removeItem('fife_otpSentAt');
		otp = '';
		step = 'email';
		errorMessage = '';
		setTimeout(() => emailInput?.focus(), 100);
	}
</script>

<svelte:head>
	<title>Sign In — FiFe</title>
</svelte:head>

<div class="relative flex min-h-screen items-center justify-center overflow-hidden p-6">
	<div
		class="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_50%_-20%,rgba(255,64,64,0.15),transparent_45%),linear-gradient(180deg,#07090c_0%,#0b0d10_100%)]"
	></div>

	<div class="w-full max-w-[420px]">
		{#if errorMessage || form?.error}
			<div
				transition:slide
				class="mb-4 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200"
			>
				{form?.error || errorMessage}
			</div>
		{/if}

		<div
			class="relative overflow-hidden rounded-[1.5rem] border border-white/10 bg-white/5 p-8 shadow-[0_10px_50px_rgba(0,0,0,0.28)] backdrop-blur-2xl"
		>
			<div
				class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-transparent via-[#FF4040]/50 to-transparent"
			></div>

			{#if step === 'email'}
				<div in:fade={{ duration: 200, delay: 100 }} out:fade={{ duration: 100 }}>
					<div class="flex justify-center">
						<LockKeyhole class="h-12 w-12 text-[#FF4040]" />
					</div>
					<h1 class="mt-6 text-center text-2xl font-bold text-white">Welcome</h1>
					<p class="mt-2 text-center text-white/60">Sign in to continue to FiFe</p>

					<form
						class="mt-8 space-y-6"
						method="POST"
						action="?/sendOtp"
						use:enhance={() => {
							processing = true;
							errorMessage = '';
							return async ({ result, update }) => {
								// applyAction syncs the response back to SvelteKit's reactive $props
								await applyAction(result);
								await update();
								processing = false;

								if (result.type === 'success' && result.data) {
									step = 'otp';
									email = result.data.email as string;

									// Save to local storage for persistence across reloads
									localStorage.setItem('fife_otpSentTo', email);
									localStorage.setItem('fife_otpSentAt', Date.now().toString());

									setTimeout(() => otpInput?.focus(), 100);
								}
							};
						}}
					>
						<div class="space-y-2">
							<label for="email" class="text-sm font-medium text-white/80">Email Address</label>
							<div class="relative">
								<div
									class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-white/40"
								>
									<Mail class="h-5 w-5" />
								</div>
								<input
									bind:this={emailInput}
									bind:value={email}
									name="email"
									type="email"
									id="email"
									required
									placeholder="your.email@example.com"
									disabled={processing}
									class="w-full rounded-xl border border-white/10 bg-black/40 py-3.5 pr-4 pl-12 text-white placeholder-white/30 transition-all outline-none focus:border-[#FF4040] focus:ring-1 focus:ring-[#FF4040] disabled:opacity-50"
								/>
							</div>
						</div>

						<button
							type="submit"
							disabled={processing}
							class="flex w-full items-center justify-center rounded-xl bg-gradient-to-r from-[#FF4040] to-[#FF6969] py-3.5 font-semibold text-white shadow-[0_8px_20px_rgba(255,64,64,0.25)] transition hover:scale-[1.02] disabled:opacity-70 disabled:hover:scale-100"
						>
							{#if processing}
								<Loader class="h-5 w-5 animate-spin" />
							{:else}
								{form?.error || errorMessage ? 'Retry Sending OTP' : 'Send OTP'}
							{/if}
						</button>
					</form>
				</div>
			{:else if step === 'otp'}
				<!-- Same fade block... -->
				<div in:fade={{ duration: 200, delay: 100 }} out:fade={{ duration: 100 }}>
					<div class="flex justify-center">
						<MailCheck class="h-12 w-12 text-[#FF4040]" />
					</div>
					<h1 class="mt-6 text-center text-2xl font-bold text-white">Check your email</h1>
					<p class="mt-2 text-center text-white/60">
						We've sent a 6-digit code to<br /><span class="font-medium text-white">{email}</span>
					</p>

					<form
						class="mt-8 space-y-6"
						method="POST"
						action="?/verifyOtp"
						use:enhance={() => {
							processing = true;
							errorMessage = '';
							return async ({ result, update }) => {
								await applyAction(result);
								await update();
								processing = false;

								// Because the server action throws a redirect on success,
								// SvelteKit will automatically handle routing if successful.
								// If it fails, form?.error will be populated.
							};
						}}
					>
						<div class="space-y-2">
							<label for="otp" class="text-sm font-medium text-white/80">Enter OTP</label>
							<div class="relative">
								<div
									class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-4 text-white/40"
								>
									<RectangleEllipsis class="h-5 w-5" />
								</div>
								<input type="hidden" name="email" value={email} />
								<input
									bind:this={otpInput}
									bind:value={otp}
									name="otp"
									type="text"
									id="otp"
									required
									maxlength="6"
									disabled={processing}
									placeholder="000000"
									class="w-full rounded-xl border border-white/10 bg-black/40 py-3.5 pr-4 pl-12 text-center text-2xl font-bold tracking-[0.5em] text-white placeholder-white/30 transition-all outline-none focus:border-[#FF4040] focus:ring-1 focus:ring-[#FF4040] disabled:opacity-50"
								/>
							</div>
						</div>

						<button
							type="submit"
							disabled={processing || otp.length < 6}
							class="flex w-full items-center justify-center rounded-xl bg-gradient-to-r from-[#FF4040] to-[#FF6969] py-3.5 font-semibold text-white shadow-[0_8px_20px_rgba(255,64,64,0.25)] transition hover:scale-[1.02] disabled:opacity-70 disabled:hover:scale-100"
						>
							{#if processing}
								<Loader class="h-5 w-5 animate-spin" />
							{:else}
								Verify OTP
							{/if}
						</button>
					</form>

					<div class="mt-6 text-center">
						<button
							onclick={changeEmail}
							disabled={processing}
							class="inline-flex items-center text-sm font-medium text-white/60 transition hover:text-white disabled:opacity-50"
						>
							<ArrowLeft class="mr-2 h-4 w-4" />
							Use a different email
						</button>
					</div>
				</div>
			{:else if step === 'signedIn'}
				<div
					in:fade={{ duration: 200, delay: 100 }}
					out:fade={{ duration: 100 }}
					class="text-center"
				>
					<div class="flex justify-center">
						<CircleCheck class="h-12 w-12 text-[#10b981]" />
					</div>
					<h1 class="mt-6 text-2xl font-bold text-white">Already Signed In</h1>
					<p class="mt-2 text-white/60">You are securely connected to your vault.</p>

					<div class="mt-8">
						<!-- Standard enhance here is perfectly fine since signout handles itself -->
						<form method="POST" action="?/signout" use:enhance>
							<button
								type="submit"
								disabled={processing}
								class="flex w-full items-center justify-center rounded-xl border border-red-500/30 bg-red-500/10 py-3.5 font-semibold text-red-400 transition hover:bg-red-500/20 disabled:opacity-50"
							>
								{#if processing}
									<Loader class="mr-2 h-5 w-5 animate-spin" />
									Signing Out...
								{:else}
									<LogOut class="mr-2 h-5 w-5" />
									Sign Out
								{/if}
							</button>
						</form>
					</div>
				</div>
			{/if}
		</div>
	</div>
</div>
