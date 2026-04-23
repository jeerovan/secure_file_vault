<script lang="ts">
	const lastUpdated = 'April 23, 2026';
	const contactEmail = 'jeerovan@gmail.com'; // Replace with your actual legal/support email
</script>

<svelte:head>
	<title>Terms of Service - FiFe</title>
	<meta
		name="description"
		content="Terms of Service for FiFe - Zero-Knowledge Encrypted Cloud Storage"
	/>
</svelte:head>

<main class="container mx-auto max-w-4xl px-4 py-12 leading-relaxed text-gray-300 md:py-16">
	<header class="mb-10 border-b border-gray-800 pb-6">
		<h1 class="mb-2 text-3xl font-bold text-white md:text-4xl">Terms of Service</h1>
		<p class="text-sm font-medium text-gray-400">Last Updated: {lastUpdated}</p>
	</header>

	<div class="space-y-8">
		<section>
			<p class="mb-4">
				Welcome to FiFe. These Terms of Service ("Terms") govern your access to and use of the FiFe
				application, website, and related services (collectively, the "Service").
			</p>
			<p>
				By creating an account, accessing, or using the Service, you agree to be bound by these
				Terms. If you do not agree to these Terms, do not use the Service.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">
				1. The FiFe Service & Zero-Knowledge Architecture
			</h2>
			<p class="mb-4">FiFe provides an encrypted cloud storage and file synchronization service.</p>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">Zero-Knowledge:</strong> Our Service is built on zero-knowledge,
					end-to-end encryption. This means your files are encrypted on your device before they are uploaded.
				</li>
				<li>
					<strong class="text-white">Master Key Responsibility:</strong> You hold the sole master
					encryption key. <strong>We do not possess, store, or transmit your master key.</strong>
				</li>
				<li>
					<strong class="text-white">No Data Recovery:</strong> Because we cannot access your key, we
					cannot recover, reset, or restore your encrypted data if you lose your master key or password.
					You bear sole responsibility for safeguarding your credentials.
				</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">2. Account Registration and Security</h2>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">Eligibility:</strong> You must be at least 13 years old to use the
					Service.
				</li>
				<li>
					<strong class="text-white">Account Information:</strong> You must provide a valid email address
					to register an account. You are responsible for maintaining the accuracy of this information.
				</li>
				<li>
					<strong class="text-white">Account Security:</strong> You are entirely responsible for maintaining
					the confidentiality of your account credentials and master key. You agree to notify us immediately
					of any unauthorized use of your account.
				</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">
				3. Subscriptions, Payments, and Auto-Sync
			</h2>
			<p class="mb-4">
				Certain features of the Service, such as automatic background synchronization (auto-sync)
				and expanded storage quotas, require a paid subscription.
			</p>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">Billing:</strong> Payments and subscriptions are processed securely
					through our third-party provider (RevenueCat) and your respective app store (Apple App Store,
					Google Play, etc.).
				</li>
				<li>
					<strong class="text-white">Renewals:</strong> Subscriptions automatically renew unless canceled
					at least 24 hours before the end of the current billing period.
				</li>
				<li>
					<strong class="text-white">Cancellation:</strong> You may cancel your subscription at any time
					through your app store settings. If canceled, you will retain access to premium features until
					the end of your current billing cycle.
				</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">4. Acceptable Use Policy</h2>
			<p class="mb-2">You agree not to use the Service to:</p>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					Store, upload, or share material that is illegal, defamatory, or violates the intellectual
					property rights of others.
				</li>
				<li>Distribute malware, viruses, or any other malicious code.</li>
				<li>Attempt to probe, scan, or test the vulnerability of our systems or networks.</li>
				<li>
					Engage in activity that disproportionately strains our infrastructure or violates any
					storage quotas.
				</li>
			</ul>
			<p class="mt-4 text-sm text-gray-400">
				<em
					>Note: While our zero-knowledge architecture prevents us from viewing your files, we
					reserve the right to suspend or terminate accounts that we can determine are violating
					these Terms based on metadata, abnormal bandwidth usage, or lawful reports.</em
				>
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">
				5. Distributed Storage and Availability
			</h2>
			<p>
				To ensure redundancy, your encrypted data is distributed across multiple third-party cloud
				storage providers. While we strive for 100% uptime, the Service is provided on an "AS IS"
				and "AS AVAILABLE" basis. We do not warrant that the Service will be uninterrupted, timely,
				secure, or error-free. You are encouraged to maintain local backups of your unencrypted
				files.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">6. Limitation of Liability</h2>
			<p class="mb-4">
				To the maximum extent permitted by law, FiFe and its developers shall not be liable for any
				indirect, incidental, special, consequential, or punitive damages, including without
				limitation, loss of profits, data, use, goodwill, or other intangible losses, resulting
				from:
			</p>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>Your access to or use of or inability to access or use the Service.</li>
				<li>The loss of your master access key and subsequent loss of data access.</li>
				<li>Any unauthorized access, use, or alteration of your transmissions or content.</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">7. Account Termination</h2>
			<p class="mb-4">
				You may terminate your account and delete your data at any time through the App settings.
				Upon deletion, your server-side keys and distributed encrypted files will be permanently
				purged and cannot be recovered.
			</p>
			<p>
				We may terminate or suspend your account immediately, without prior notice or liability, for
				any reason, including without limitation if you breach the Terms.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">8. Changes to Terms</h2>
			<p>
				We reserve the right to modify or replace these Terms at any time. We will provide notice of
				any material changes by updating the "Last Updated" date and posting the new Terms within
				the App and website. Your continued use of the Service after any such changes constitutes
				your acceptance of the new Terms.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">9. Contact Us</h2>
			<p>
				If you have any questions about these Terms, please contact us at
				<a
					href="mailto:{contactEmail}"
					class="font-medium text-blue-400 transition-colors hover:text-blue-300 hover:underline"
					>{contactEmail}</a
				>.
			</p>
		</section>
	</div>
</main>
