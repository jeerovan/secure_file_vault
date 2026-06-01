
<div align="center">
  <img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="FiFe icon" width="120" />
  
  # FiFe - Your private Files Ferry
  
  **[https://fife.jeero.one](https://fife.jeero.one)**

  An open-source, cloud storage backup service built with zero-trust architecture. Your data is encrypted locally before it ever leaves your device.
  
  ![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
  ![SvelteKit](https://img.shields.io/badge/SvelteKit-%23FF3E00.svg?style=for-the-badge&logo=Svelte&logoColor=white)
  ![PostgreSQL](https://img.shields.io/badge/Neon_Postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
  ![Open Source](https://img.shields.io/badge/Open%20Source-%E2%99%A5-red?style=for-the-badge)
</div>

<br/>

## 🛡️ Why FiFe?

Traditional cloud storage providers hold the keys to your data. FiFe shifts the control back to you. By combining **Bring Your Own Storage (BYOS)** with strict **Client-Side Encryption**, FiFe ensures that nobody—not even the server hosting the app—can read your files.

## ✨ Key Features

- **🔒 Zero-Knowledge Client-Side Encryption:** Files are encrypted entirely on your device using `libsodium` before uploading. The server only stores encrypted key ciphers and nonces.
- **☁️ Bring Your Own Storage:** Connect your own object storage buckets. Currently supports **Backblaze B2**, **Cloudflare R2**, **ORACLE** and **IDrive E2**.
- **📂 Preserves Folder Structure:** Back up entire directories without losing your organizational hierarchy.
- **⚡ Smart Duplicate Detection:** Computes hashes locally on-demand to detect duplicate files, saving your bandwidth and storage space.
- **🚀 Direct-to-Cloud Uploads:** Uploads bypass the backend completely, utilizing secure, pre-signed URLs directly to the storage provider.
- **🚫 Zero Tracking:** Built with strict privacy in mind. Absolutely no third-party analytics or data harvesting.

## 🏗️ Architecture & Tech Stack

FiFe is split into a robust cross-platform client and an edge-optimized server:

**Frontend / Client App**
- Built with **Flutter** for Android, iOS, OSX, and Linux (AppImages).
- Background task synchronization using Workmanager.
- Local metadata management via SQLite.

**Backend / API**
- Built with **SvelteKit** and deployed on **Cloudflare Workers**.
- Database: **Neon Postgres** using **Drizzle ORM**.
- Uses Cloudflare Hyperdrive for accelerated database connections.
- Authentication handled securely via Email OTP (Neon.tech).

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- Node.js & npm (for backend development)
- A Neon Postgres database URL
- Cloudflare Wrangler CLI

### Running the App Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jeerovan/secure_file_vault.git
   cd secure_file_vault
   ```

2. **Run the Flutter Client:**
   ```bash
   flutter pub get
   flutter run
   ```

3. **Backend Setup (SvelteKit):**
   Navigate to the server directory, install dependencies, and configure your `.env` with your Neon `DATABASE_URL`.
   ```bash
   npm install
   npm run dev
   ```

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/jeerovan/secure_file_vault/issues).

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is open-source and available under the [AGPL-3.0 License](LICENSE).
