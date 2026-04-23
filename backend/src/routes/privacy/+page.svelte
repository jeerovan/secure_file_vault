<script>
	const lastUpdated = 'April 23, 2026';
	const contactEmail = 'jeerovan@gmail.com'; // Replace with your actual contact email
</script>

<svelte:head>
	<title>Privacy Policy - FiFe</title>
	<meta
		name="description"
		content="Privacy Policy for FiFe - Zero-Knowledge Encrypted Cloud Storage"
	/>
</svelte:head>

<main class="container mx-auto max-w-4xl px-4 py-12 leading-relaxed text-gray-300 md:py-16">
	<header class="mb-10 border-b border-gray-800 pb-6">
		<h1 class="mb-2 text-3xl font-bold text-white md:text-4xl">Privacy Policy for FiFe</h1>
		<p class="text-sm font-medium text-gray-400">Last Updated: {lastUpdated}</p>
	</header>

	<div class="space-y-8">
		<section>
			<p class="mb-4">
				Welcome to FiFe ("we," "our," or "us"). We are committed to protecting your privacy and
				ensuring the security of your data. This Privacy Policy explains how we collect, use, and
				protect your information when you use the FiFe application (the "App").
			</p>
			<p>
				By using FiFe, you agree to the collection and use of information in accordance with this
				Privacy Policy.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">
				1. Zero-Knowledge Architecture & Data Security
			</h2>
			<p class="mb-4">
				FiFe is built on a zero-knowledge encryption model, meaning we cannot read, view, or access
				the files you store using our service.
			</p>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">End-to-End Encryption:</strong> All your files are encrypted directly
					on your device before they are transmitted over the internet via secure SSL/TLS protocols.
				</li>
				<li>
					<strong class="text-white">Access Keys:</strong> The master access key required to decrypt your
					files remains strictly on your device. We do not transmit or store your plaintext master key.
				</li>
				<li>
					<strong class="text-white">Distributed Storage:</strong> Your encrypted data is distributed
					across various cloud storage providers to ensure redundancy and availability. Because the data
					is encrypted before it leaves your device, these cloud providers cannot read your files.
				</li>
				<li>
					<strong class="text-white">Server Storage:</strong> The only file-related data stored on our
					servers are encrypted keys (the access key cipher and nonce). Without your local master key,
					these server-side encrypted keys cannot be used to decrypt your data.
				</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">2. Information We Collect</h2>
			<p class="mb-4">
				We intentionally limit the amount of personal information we collect to the absolute minimum
				required to operate the App.
			</p>

			<h3 class="mt-6 mb-2 text-xl font-medium text-white">Information You Provide</h3>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">Email Address:</strong> We require your email address solely to authenticate
					your account and manage your subscription.
				</li>
			</ul>

			<h3 class="mt-6 mb-2 text-xl font-medium text-white">Information We Do NOT Collect</h3>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">Analytics:</strong> We do not use any third-party analytics services
					to track your usage behavior within the App.
				</li>
				<li>
					<strong class="text-white">File Contents:</strong> We do not and cannot collect, view, or analyze
					the contents of the files you back up.
				</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">3. Third-Party Services</h2>
			<p class="mb-4">
				We use trusted third-party services to handle authentication and billing. These services
				have their own privacy policies governing how they handle your data.
			</p>
			<ul class="list-disc space-y-3 pl-6 marker:text-gray-500">
				<li>
					<strong class="text-white">Supabase (Authentication):</strong> We use Supabase to securely
					authenticate your account using your email address. You can read more about how Supabase
					handles your data in the
					<a
						href="https://supabase.com/privacy"
						target="_blank"
						rel="noopener noreferrer"
						class="text-blue-400 transition-colors hover:text-blue-300 hover:underline"
						>Supabase Privacy Policy</a
					>.
				</li>
				<li>
					<strong class="text-white">RevenueCat (Subscriptions):</strong> We use RevenueCat to
					manage in-app purchases and subscriptions. We share your email address and anonymous
					Supabase user ID with RevenueCat to associate your subscription with your account. We do
					not process or store your credit card or payment information. You can read more about how
					RevenueCat handles your data in the
					<a
						href="https://www.revenuecat.com/privacy"
						target="_blank"
						rel="noopener noreferrer"
						class="text-blue-400 transition-colors hover:text-blue-300 hover:underline"
						>RevenueCat Privacy Policy</a
					>.
				</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">4. How We Use Your Information</h2>
			<p class="mb-2">We use your email address exclusively for the following purposes:</p>
			<ul class="list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>To create and authenticate your FiFe account.</li>
				<li>
					To verify your subscription status and grant access to premium features (like auto-sync).
				</li>
				<li>To send you critical account notifications (e.g., password resets).</li>
			</ul>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">5. Data Retention and Deletion</h2>
			<p class="mb-4">
				You can request to delete your account at any time within the App. Upon account deletion:
			</p>
			<ul class="mb-6 list-disc space-y-2 pl-6 marker:text-gray-500">
				<li>
					Your email address and authentication data will be permanently deleted from our Supabase
					database.
				</li>
				<li>Your subscription association will be removed.</li>
				<li>
					Your encrypted files and server-side encrypted keys will be permanently deleted from our
					servers and distributed cloud storage providers.
				</li>
			</ul>
			<div class="rounded-r-md border-l-4 border-amber-500 bg-amber-900/20 p-4">
				<p class="text-sm text-amber-200">
					<strong class="text-amber-400">Important:</strong> Because we use a zero-knowledge architecture,
					if you lose your master access key, your data cannot be recovered, and we cannot bypass the
					encryption to retrieve it for you.
				</p>
			</div>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">6. Children's Privacy</h2>
			<p>
				Our App is not intended for use by children under the age of 13. We do not knowingly collect
				personal identifiable information from children under 13. If we discover that a child under
				13 has provided us with personal information, we will immediately delete this from our
				servers.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">7. Changes to This Privacy Policy</h2>
			<p>
				We may update our Privacy Policy from time to time. We will notify you of any changes by
				posting the new Privacy Policy on this page and updating the "Last Updated" date at the top.
				You are advised to review this Privacy Policy periodically for any changes.
			</p>
		</section>

		<section>
			<h2 class="mb-4 text-2xl font-semibold text-white">8. Contact Us</h2>
			<p>
				If you have any questions or suggestions about our Privacy Policy, do not hesitate to
				contact us at
				<a
					href="mailto:{contactEmail}"
					class="font-medium text-blue-400 transition-colors hover:text-blue-300 hover:underline"
					>{contactEmail}</a
				>.
			</p>
		</section>
	</div>
</main>
