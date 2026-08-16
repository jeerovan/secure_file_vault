# FiFe Product Specification

**Status:** Living specification  
**Version:** 0.1  
**Repository:** `file_vault_bb`  
**Product:** FiFe — Your Private Files Ferry

## 1. Purpose

FiFe is an open-source, cross-platform cloud-storage backup and synchronization service. It lets users connect storage accounts they control, preserve their file and folder organization, and transfer files without giving the FiFe backend access to plaintext file contents.

FiFe follows two central product principles:

1. **Bring Your Own Storage (BYOS):** users connect their own supported object-storage provider.
2. **Zero-knowledge client-side encryption:** file contents are encrypted on the user's device before upload. The backend must not be able to decrypt user files.

This document specifies product intent, system boundaries, and invariants. It complements:

- `README.md`, which describes features, setup, and project overview;
- `AGENTS.md`, which defines repository-working instructions for AI agents;
- the codebase knowledge graph, which describes current implementation structure and relationships.

When implementation and this specification disagree, do not silently choose one. Treat the difference as a defect or an unresolved specification change.

## 2. Repository Scope

This repository contains both client and server code.

### 2.1 Flutter client

The Flutter application lives primarily under `lib/`, with platform integration under the corresponding platform directories.

Responsibilities include:

- user-facing file, folder, storage-provider, device, and settings workflows;
- local encryption and decryption;
- local file hashing and duplicate detection;
- direct upload and download against connected storage providers;
- local metadata persistence using SQLite;
- secure local storage of sensitive client values;
- foreground/background synchronization where supported by the target platform.

### 2.2 SvelteKit backend

The backend lives under `backend/`. It is a SvelteKit application exposing APIs and web pages.

Responsibilities include:

- authentication and authorization;
- user, device, subscription, storage-account, key-cipher, and synchronization metadata;
- provider-specific account setup and short-lived upload/download authorization;
- database access through Drizzle ORM and Neon PostgreSQL;
- deployment to Cloudflare infrastructure;
- public web, connection, privacy, and terms pages.

The backend is a control plane. File payloads should travel directly between the client and the user's storage provider whenever provider capabilities allow it.

## 3. Platform and Branch Policy

### 3.1 `main` branch

The `main` branch is the source branch for:

- Android
- macOS
- Windows
- Linux

Changes on `main` must preserve these four targets unless a change is explicitly platform-specific and safely isolated.

Platform filesystem access rules:

- macOS sandboxed folder selection must persist real security-scoped bookmark data, never a sentinel value;
- macOS reconciliation must resolve and start bookmark access before scanning, fail closed when access cannot be acquired, and balance every successful start with a stop in `finally`;
- legacy or missing macOS bookmarks require explicit folder re-selection;
- filesystem identity must preserve exact names, including whitespace, case, and Unicode normalization differences where the host filesystem supports them;
- symlinks are ignored during reconciliation and hidden directories are pruned according to the shared hidden-content policy.

### 3.2 iOS branch

iOS is maintained and developed separately on the `ios` branch.

Rules:

- Do not treat iOS support on `main` as authoritative, even if iOS files exist there.
- Do not make iOS-specific changes on `main` unless explicitly requested.
- Do not assume a change made on `main` is already compatible with the `ios` branch.
- Shared changes intended for iOS require deliberate porting and validation on the `ios` branch.

## 4. Supported Storage Providers

Current provider scope:

- Backblaze B2
- Cloudflare R2
- Oracle Cloud Infrastructure Object Storage
- IDrive E2

Provider integrations must preserve common FiFe behavior while isolating provider-specific authentication, signing, URL-generation, and API details.

Adding a provider requires, at minimum:

- account connection and credential validation;
- secure credential handling;
- upload authorization or signed upload URLs;
- download authorization or signed download URLs;
- correct object addressing and folder-hierarchy behavior;
- actionable error handling;
- validation on every supported `main` platform affected by the change.

## 5. Core Functional Requirements

### 5.1 Account and device access

- Users must authenticate before accessing protected backend resources.
- Backend authorization must scope data to the authenticated user.
- Registered-device state must be enforceable by the client and backend.
- Sign-out and device reset must remove or invalidate sensitive local session state as appropriate.

### 5.2 Storage connection

- Users must be able to connect supported storage accounts they control.
- Storage credentials must not be exposed to unrelated users or returned through unnecessary API responses.
- Provider secrets stored server-side must receive protection appropriate to their sensitivity.
- Provider-specific failures must be translated into useful user-facing errors without leaking secrets.

### 5.3 File backup and restore

- Users must be able to select files or directories for backup.
- Folder hierarchy must be preserved in FiFe metadata and restored output.
- Files must be encrypted locally before uploaded bytes leave the device.
- Downloads must be decrypted locally only after encrypted bytes reach an authorized client.
- Upload and download flows should use short-lived, least-privilege provider authorization.
- Plaintext file payloads must bypass the FiFe backend.

### 5.4 Duplicate detection

- File hashes must be computed locally.
- Duplicate detection should avoid unnecessary transfer and storage use.
- A duplicate decision must not cause silent loss of distinct user files or folder entries.

### 5.5 Synchronization

- FiFe must synchronize relevant file/folder metadata and change records across a user's registered devices.
- Synchronization must preserve enough information to reconcile folder structure and pending local/remote changes.
- Sync operations must tolerate interruption and retry without silently duplicating or losing user data.
- Background synchronization must respect platform lifecycle and background-execution limits.
- Conflict resolution, deletion propagation, retry limits, and ordering semantics remain governed by current implementation until explicitly specified in Section 11.

### 5.6 Local state

- SQLite is the client-side source for local metadata required by browsing, queueing, and synchronization.
- Sensitive secrets must use platform-backed secure storage where supported, not ordinary preferences or logs.
- Schema changes must include safe migrations for existing installations.

### 5.7 Reconciliation safety

- A filesystem scan must complete before reconciliation mutates local metadata.
- Missing, inaccessible, partially readable, or partially hashed roots must never be interpreted as empty roots and must never authorize deletion.
- Filesystem basenames are identity data and must be preserved exactly; display normalization must not alter stored paths.
- Hidden files and hidden directories are excluded consistently, and symbolic links are not followed.
- When an original and an identical copy both exist, the copy receives a distinct `ModelItem` identity while both items may reference the same deduplicated `ModelFile`.
- Rename or move identity is retained only when the old path is absent from the same immutable snapshot and exactly one sufficiently strong candidate exists.
- Ambiguous or low-information candidates are treated as new items, never as authorization to mutate an existing identity.
- Reconciliation and sync commits use atomic owner-token leases with stale recovery; timestamps are observability data, not locks.
- All metadata, task, and change-journal mutations for one root reconciliation commit transactionally or roll back together.
- A folder move must not introduce a parent cycle.

### 5.8 Transfer safety

- Upload source size and keyed content hash must match reconciled metadata before encryption; a source that changes during encryption is blocked until reconciliation runs again.
- Encrypted upload artifacts use partial and ready states. Existence alone never proves an artifact complete; ready artifacts must match committed part size and checksum metadata.
- Download staging is isolated by opaque item identity, never basename. A persisted manifest binds staging to item ID, file hash, part count, expected plaintext length, and verified per-part checksums.
- A downloaded part becomes resumable only after transport, encrypted size/checksum, authenticated decryption, ready-file promotion, and manifest commit succeed.
- Final plaintext size and keyed content hash must match metadata before and after destination finalization. Transfer task completion is recorded only after destination verification. A different file or directory already occupying the destination is preserved and blocks finalization.
- Transfer tasks persist state, attempt count, next-attempt time, and non-sensitive error category. Retryable failures use exponential backoff with stable jitter, capped at fifteen minutes and ten attempts; later user/reconciliation action may requeue a failed task.
- `blocked`, `failed`, and `cancelled` tasks are not automatically dispatched. Interrupted `running` tasks become retryable after their lease expires.
- Auth refresh is single-flight. Idempotent operations may retry once only when refresh changes authorization; non-idempotent POST operations require explicit retry opt-in.
- Transfer and auth network operations use finite connection/response/stream timeouts.

### 5.9 Resource and lifecycle safety

- Transfer payloads and checksums must stream from disk; multipart payload size must not determine process memory growth.
- Concurrent transfer execution is bounded by platform policy: mobile may run at most two transfers and desktop at most three unless profiling supports a deliberate policy change.
- Backend, authentication, and upload HTTP clients are shared and lifecycle-managed. Injected clients retain explicit ownership; scoped clients close in `finally`.
- Transfer progress is monotonic and uses a 0–100 scale. Multipart progress includes completed parts and current-part bytes where available.
- Reconciliation, synchronization, storage-capacity, and task changes publish events. UI consumers must not poll SQLite on short periodic timers when equivalent events exist.
- UI-triggered reconciliation, refresh, and required follow-up synchronization are awaited. Busy state is repaired in mounted lifecycle guards even after failure.

### 5.10 Confirmed reconciliation and transfer policies

- A missing local file does not authorize broad metadata deletion. Reconciliation may remove metadata for never-uploaded content only when no upload task protects it; uploaded content remains represented until explicit archive/deletion policy handles it.
- User removal of synchronized items records archive metadata. Cross-device permanent deletion and retention duration remain product decisions.
- Existing destination files and directories are conflict boundaries: restore never overwrites them implicitly, and staging remains available for retry or user resolution.
- Rename/move conflicts use conservative identity rules from Section 5.7. No timestamp-only or first-match rule may choose between ambiguous candidates.
- A basename beginning with `.` excludes that entity. Excluded directories prune their entire subtree, and symbolic links are never followed during reconciliation.
- Retryable transfers use persisted exponential backoff; blocked, failed, or cancelled work requires explicit requeue. Authentication retry remains limited to one safe/idempotent retry after changed authorization.
- Item, file, part, and task models use typed repository boundaries for shared lookup, server-upsert, and task-queue persistence behavior. Raw SQL remains limited to specialized transactional/query operations.

## 6. Security and Privacy Invariants

These requirements are non-negotiable unless this specification is deliberately revised:

1. File contents are encrypted on the client before upload.
2. File contents are decrypted only on an authorized client.
3. The FiFe backend must not receive plaintext file payloads.
4. The FiFe backend must not possess sufficient plaintext key material to decrypt user files.
5. Stored key ciphers, nonces, hashes, metadata, credentials, and tokens must be treated as sensitive data.
6. Protected API endpoints must authenticate the caller and enforce per-user ownership.
7. Signed URLs or temporary provider credentials must be narrowly scoped and short-lived.
8. Secrets, plaintext keys, access tokens, provider credentials, and sensitive URLs must not be written to logs.
9. FiFe must not introduce third-party analytics, tracking, or data harvesting without an explicit product-specification change.
10. Cryptographic formats or key-derivation behavior must not change without backward-compatibility and recovery analysis.

Security-sensitive changes require tests or other concrete verification covering authorization boundaries, failure paths, and data exposure.

## 7. System Architecture and Data Flow

Expected upload flow:

1. Client authenticates with FiFe backend.
2. Client resolves user, device, storage, and encryption metadata.
3. Client encrypts file locally.
4. Client obtains provider-specific upload authorization from backend.
5. Client uploads encrypted bytes directly to user's storage provider.
6. Client records and synchronizes resulting metadata.

Expected download flow:

1. Client authenticates with FiFe backend.
2. Client obtains provider-specific download authorization.
3. Client downloads encrypted bytes directly from user's storage provider.
4. Client resolves authorized local decryption material.
5. Client decrypts file locally and writes restored output.

Architectural boundaries:

- UI code should orchestrate presentation, not own cryptography, persistence, or provider protocol logic.
- Client models represent file, folder, task, setting, storage, and sync state.
- Client services and utilities own API communication, task execution, encryption, file transfer, and synchronization behavior.
- Storage adapters own SQLite, secure storage, and platform-channel persistence details.
- SvelteKit route handlers own HTTP validation and responses; shared server modules own authentication, database, and provider behavior.

## 8. Backend API Expectations

Backend API surface currently covers these domains:

- authentication and sign-out;
- devices;
- subscriptions;
- storage accounts;
- encrypted key metadata;
- synchronization and file-part metadata;
- notification token metadata;
- provider account setup;
- provider upload and download authorization.

API changes must:

- preserve authorization and user ownership checks;
- validate untrusted request data;
- return stable, explicit status codes and response shapes;
- avoid returning internal errors or secret values;
- consider compatibility with released clients on all supported branches;
- keep provider-specific behavior behind provider-specific modules or routes where practical.

## 9. Compatibility and Change Requirements

A change is acceptable only when applicable requirements below hold:

- Existing user data remains readable, or a tested migration is supplied.
- Existing encrypted files remain decryptable.
- Backend changes remain compatible with deployed clients, or rollout is explicitly coordinated.
- Shared Flutter behavior works on Android, macOS, Windows, and Linux from `main`.
- Platform-specific code is isolated behind supported platform checks or abstractions.
- Interrupted file transfers and sync operations do not corrupt metadata or silently lose user data.
- Errors shown to users are actionable; logs retain diagnostic value without exposing secrets.
- New dependencies are justified and cannot reasonably be replaced by SDK APIs or current dependencies.

## 10. Definition of Done

For each change:

1. Behavior matches this specification and stated task acceptance criteria.
2. Flutter/Dart changes pass analyzer checks for affected code.
3. Backend changes pass relevant Svelte/TypeScript checks.
4. Relevant automated tests pass; missing coverage for critical behavior is added when practical.
5. UI/runtime changes are exercised on affected platforms or limitations are documented.
6. Database changes include migration and compatibility handling.
7. Security and privacy invariants remain intact.
8. `README.md`, this specification, or other user-facing documentation is updated when behavior or setup changes.
9. Codebase knowledge graph is re-indexed after material structural changes.

## 11. Underspecified Product Decisions

These subjects need explicit decisions before an AI agent should materially change their behavior:

- synchronization conflict-resolution rules beyond the conservative identity and destination-conflict behavior in Section 5;
- remote deletion propagation, trash retention duration, and permanent-delete semantics beyond the safety rules in Section 5;
- offline queue ordering and user-facing retry controls;
- multi-device limits and device-revocation behavior;
- subscription tiers, quotas, and expiry behavior;
- encryption-key recovery, rotation, and lost-device workflows;
- partial/multipart upload recovery and stale-part cleanup;
- exact metadata retained by backend and its retention period;
- compatibility and merge policy between `main` and `ios` branches;
- supported minimum OS versions and release packaging requirements.

Until documented, preserve existing behavior. Do not infer new product policy from UI text, one platform implementation, or a single API route.

## 12. Explicit Non-Goals

Unless separately specified, FiFe is not intended to:

- host plaintext user files on its backend;
- provide FiFe-owned general-purpose object storage;
- let server operators recover or inspect plaintext user content;
- add analytics or advertising tracking;
- guarantee iOS compatibility from changes made only on `main`;
- replace provider-native durability, billing, lifecycle, or quota guarantees.

## 13. Specification Maintenance

- Update this document when product behavior, supported platforms, providers, security invariants, or system boundaries change.
- Describe desired behavior, not transient class names or file layouts already discoverable through the codebase graph.
- Mark unresolved behavior explicitly instead of inventing certainty.
- Prefer small, reviewable specification changes alongside related code changes.
