# iOS Support on `main`: Migration and macOS Handoff

**Status:** BOOKMARK ACCESS, ROOT RECOVERY AND EDITOR RESUME REFRESH VERIFIED ON PHYSICAL iPHONE; BOUNDED BACKGROUND WORK IMPLEMENTED

**Physical-device execution plan:** [IOS-PHYSICAL-TEST-PLAN.md](IOS-PHYSICAL-TEST-PLAN.md), updated 2026-10-07. The plan documents the bookmark fix's changed files/invariants and successful access after cold launch/reboot. Autonomous continuation exposed and fixed zero-part empty-file download rejection. All nine distinct uploads completed, including the interrupted 120 MiB file; all 10 restored files now match retained originals, with no remaining tasks. Earlier validation before the subsequent fixes: 10 native iPhone tests, 114 Flutter passes and one expected Linux-only skip; affected-file analysis/lints clean. Local rename/move, native in-place refresh, process-kill download recovery and valid root-rename recovery also passed. Unavailable-root fail-closed behavior, explicit existing-root renewal, picker cancellation and timestamp-level convergence now also passed. The renewal fix preserves root/child identity after an app-container location change. A bounded app-only memory recording is documented; full-lifecycle memory, raw remote-object inspection and remaining background/recovery acceptance cases are pending. The prior 2026-10-06 failures and all historical results remain recorded separately.
Upload and download recovery after confirmed Wi-Fi loss both passed: incomplete work stayed unfinished, retries converged, and the restored 120 MiB files matched their expected bytes. The 2026-10-07 daytime continuation also passed actual screen-lock recovery, App Switcher swipe-away recovery with manual sync after relaunch, repeated foreground/background upload overlap, short Low Power Mode and disabled per-app Background App Refresh recovery, explicit fixture archive/deletion, and sign-out with a verified pending upload. Hosted OTP login and saved-key recovery restored the account afterward. The subsequent resume fix passes the Runestone atomic-replacement variant: return without manual sync changes metadata from 50 to 70 bytes, preserves item ID/parent/archive state and creates no duplicate. Earlier automatic-refresh failure is retained as historical evidence. Bounded background execution now has 125 passing Flutter tests (one expected Linux-only skip), 14 passing native tests on the iPhone, clean affected-file analysis/lints and a successful profile build. Actual expiration, a delivered late callback after sign-out, and natural background delivery still require separate evidence. Overnight tests are deferred at the user's request. See the current test record before interpreting historical results below.

**Prepared:** 2026-08-16  
**Remote state verified:** 2026-08-16  
**Recommended base:** `origin/main` at `402466d`  
**Reference branch:** `ios` at `5a7dc9c`  
**Merge base:** `ea066e01fad1dc1f629b03192feebda8098d483f`

## 1. Objective

Support Android, iOS, macOS, Windows, and Linux from `main` without weakening the reconciliation, persistence, transfer, authentication, logging, and UI fixes already completed on `main`.

Platform execution must remain distinct:

- Android uses its foreground service and persistent notification for dependable long-running work.
- iOS uses an app-owned BGTaskScheduler callback and headless Flutter engine. It must never try to start the Android-style foreground service.
- iOS and macOS use security-scoped bookmarks for user-selected folders.
- Android alone requires broad storage-permission onboarding.
- Desktop platforms retain their current foreground/timer behavior.

This migration does not promise exact-period iOS execution. Apple controls scheduling. Large, dependable background uploads may ultimately require native background `URLSession`, rather than a short Dart callback.

## 2. Repository State Before Moving to macOS

At preparation time:

- current checkout: `ios`;
- local `ios`: `5a7dc9c`, equal to `origin/ios`;
- local `main`: `402466d`, equal to `origin/main`;
- main divergence after fetch: `0 0`;
- tracked worktree is clean;
- `.codebase-memory/`, `.codex/`, `AGENTS.md`, `PLAN-FIX-ISSUES.md`, and `venv/` appear untracked on `ios` because this branch changed `.gitignore`. Do not add them accidentally.

The eight guided commits are now safely available from `origin/main`. A fresh macOS clone can use commit `402466d` directly.

This guide is still untracked. Before leaving Linux, put only this guide on a migration branch based on current main:

```bash
git switch main
git switch -c feat/ios-main-support
git add -f IOS-MAIN-MIGRATION.md
git commit -m "docs: add iOS main migration guide"
git push -u origin feat/ios-main-support
```

`-f` is required because main currently ignores `*.md`. Review `git status --short` before committing; do not add `.codebase-memory/`, `.codex/`, `venv/`, credentials, or unrelated files.

## 3. Migration Decision

Do **not** merge `ios` wholesale into `main`.

Branches contain 46 textual conflict hunks across 14 shared files. The iOS branch also predates the guided Phase 0–5 repairs. Direct merge would combine old reconciliation/transfer behavior with new platform behavior and make conflict resolution unsafe.

Use current repaired `main` as the base. Manually port the small iOS-specific surface:

- Workmanager dependency and iOS-only scheduler;
- AppDelegate Workmanager registration;
- Info.plist background declarations;
- iOS folder/file picker and security-scoped bookmark channel;
- optional Firebase notification work only after core Workmanager support is stable.

Useful reference commits, for inspection rather than blind cherry-picking:

- `02b30bf` — Workmanager scheduling and Firebase notification implementation;
- `5a7dc9c` — sync-on-app-start change;
- `e854e0e` — removal of permission-handler behavior on the iOS-only branch;
- `912ea4c` — removal of file-picker behavior on the iOS-only branch.

## 4. Existing iOS-Branch Findings

### Critical

1. `ReconciliationService` is the old implementation. It lacks main's complete-snapshot gate, operation leases, transaction boundary, conservative rename/copy identity, partial-read protection, stable hashing, and failure-safe deletion rules.
2. Bookmark access is released incorrectly: Dart passes the bookmark string to `stopAccessing`, while native code indexes active access by resolved filesystem path.
3. Bookmark acquisition is not guarded by `try/finally`. Exceptions leak scoped access.
4. Failed bookmark acquisition may continue with the persisted path without valid scoped access.

### High

1. Workmanager callback lacks `@pragma('vm:entry-point')`.
2. Full reconciliation, metadata synchronization, and file transfer can run inside one short iOS callback without a shared deadline.
3. Internal synchronization failures are swallowed, allowing Workmanager to receive a successful result.
4. FCM registration token, payload data, filesystem paths, and file hashes are logged.
5. The obsolete template widget test fails; main's 57 regression tests are absent.
6. The iOS `pubspec.yaml` removes Android dependencies, including foreground-service and permission packages. It cannot replace main's dependency file.

### Medium

1. Native bookmark resolution calculates `isStale` but ignores it.
2. Native active bookmark access has no reference count.
3. iOS deployment settings contain both 13 and 15. Workmanager documentation requires iOS 14 or later.
4. `remote-notification` background mode exists, but no push entitlement was found.
5. A requested 15-minute interval is not a guaranteed execution interval on iOS.

## 5. Target Architecture

Introduce one shared platform-facing background execution boundary. Suggested shape:

```text
BackgroundExecutionService
├── AndroidForegroundExecution
├── IosWorkmanagerExecution
└── DesktopForegroundExecution
```

Shared reconciliation, sync, transfer, repositories, logging, HTTP clients, and retry state remain platform-neutral.

Required invariants:

- Android foreground APIs are called only when `Platform.isAndroid`.
- Workmanager initialization and scheduling are called only when `Platform.isIOS`.
- iOS storage permission is always considered satisfied; access comes from each selected folder's bookmark.
- Every successful `startAccessing` is paired with `stopAccessing(resolvedPath)` in `finally`.
- Background work accepts an absolute deadline and does not start work unlikely to finish before it.
- Interrupted work remains resumable and never reports completion early.
- Workmanager returns failure/retry only for retryable failures and success only after durable state commit.
- Periodic background execution is an optimization, not the only trigger. Foreground launch/resume must also request safe synchronization.

## 6. Implementation Phases

### Phase A — Establish migration branch

**Status:** MACOS BASELINE VERIFIED; IOS BUILD BLOCKED ON PHASE B DEPENDENCY RESTORATION

- [x] Push latest repaired main commits; `main` and `origin/main` now both resolve to `402466d`.
- [x] Commit this guide alone on `feat/ios-main-support` from main.
- [x] Clone/fetch `feat/ios-main-support` on macOS and verify its main parent is `402466d`.
- [x] Confirm analyzer is clean and the 57-test main suite passes before migration edits.
- [x] Record Xcode, Flutter, Dart, and CocoaPods versions.
- [x] Record a physical-device version when a supported iPhone or iPad is connected — iPhone 13 Pro Max, iOS 27.0.1 (24A446), observed 2026-10-06.

MacOS baseline recorded on 2026-08-16:

- branch `feat/ios-main-support` at `d20854d`, with direct parent `402466d`;
- Flutter `3.41.9` stable, Dart `3.11.5`, DevTools `2.54.2`;
- Xcode `26.2` (`17C52`) and CocoaPods `1.16.2`;
- macOS `26.5.2` (`25F84`) on Apple silicon;
- analyzer clean;
- 57-test suite successful: 56 executed tests passed and the Linux-only test was skipped as designed on macOS;
- no physical iOS device connected during the baseline;
- no-codesign iOS debug build reached Swift compilation, then failed because repaired main's `AppDelegate.swift` imports `workmanager_apple` while main's `pubspec.yaml` intentionally does not yet include Workmanager. Restoring that dependency belongs to Phase B; no Phase B edits were made during this baseline.
- subsequent migration validation used an iPhone 16e simulator running iOS 26.2; the migrated app built, launched, rendered onboarding, and reported no Dart runtime errors;
- the simulator test-account secret-key flow completed after native Workmanager task registration was added; `com.jeerovan.fife.data_sync` was submitted without the prior `NSInternalInconsistencyException`/`SIGABRT` crash;
- the final simulator smoke test rendered the signed-in Explorer after pinning `path_provider_foundation` to `2.5.1`, avoiding the upstream `2.6.0` Objective-C native-assets loader regression;
- the expanded suite completed with 67 passing tests and the expected Linux-only skip; analyzer, unsigned iOS device build, Android debug build, and Android profile build all passed from the final dependency lock;
- Android validation used an Android 17/API 37 arm64 emulator with JDK 21; the migrated debug app built, installed, launched, and remained running without Dart runtime errors, and the profile APK build also succeeded.

### Phase B — Restore iOS build dependencies safely

**Status:** IMPLEMENTED; ANDROID DEBUG/PROFILE BUILDS VALIDATED

- [x] Add `workmanager` to main's dependencies.
- [x] Retain `flutter_foreground_task`, `permission_handler`, and `file_picker`; Android still needs them.
- [x] Do not add Firebase packages during the first migration slice.
- [x] Regenerate `pubspec.lock` from macOS.
- [ ] Commit `pubspec.lock` with the migration changes.
- [x] Set one consistent minimum iOS target. Prefer 15 unless product requirements demand iOS 14.
- [x] Set the same target in Xcode project, Podfile, and generated pod build settings.
- [x] Run `pod install` through normal Flutter tooling; use `ios/Runner.xcworkspace` for manual Xcode work.

Acceptance:

- Android dependency resolution remains unchanged except for Workmanager's added transitive packages.
- `flutter build ios --debug --no-codesign` succeeds on macOS.
- Android build still succeeds after dependency integration.

### Phase C — Repair native iOS bookmarks

**Status:** IMPLEMENTED; PHYSICAL REVOCATION/RESTORATION VALIDATION PENDING

- [x] Port directory picker and MethodChannel registration from `ios/Runner/AppDelegate.swift`.
- [x] Register the storage channel for both foreground and headless background engines.
- [x] Preserve main's `ChannelStorage.hasUsableBookmark` checks.
- [x] Return the resolved path from `startAccessing`.
- [x] Pass that resolved path—not bookmark data—to `stopAccessing`.
- [x] Add reference counts keyed by canonical resolved path.
- [x] Detect stale bookmarks and require explicit re-selection instead of reusing invalid access.
- [x] Never present a document picker from a headless background isolate.
- [x] Release all acquired resources in `finally`.

Acceptance:

- Folder survives app termination and relaunch.
- Revoked, malformed, empty, legacy `sandboxed`, and stale bookmarks fail closed.
- Concurrent/repeated access remains balanced.
- Failed reconciliation leaves zero leaked active accesses.

### Phase D — Add platform-specific execution service

**Status:** CORE IMPLEMENTATION COMPLETE

- [x] Replace direct platform checks scattered through startup/setup/settings with one execution service.
- [x] Initialize `ServiceForeground` only on Android.
- [x] Schedule native BGAppRefreshTask work only on iOS. The former Workmanager dependency was removed after its periodic expiration handler was found to log without cancelling the worker.
- [x] Keep desktop autosync behavior unchanged.
- [x] Add a dedicated `ExecutionMode.backgroundWorker` or equivalent; do not pretend the iOS isolate is an Android foreground service.
- [x] Add `@pragma('vm:entry-point')` to the top-level native background dispatcher.
- [x] Initialize bindings, SQLite, settings cache, crypto, auth, clients, and logger inside the background isolate.
- [x] Close isolate-owned resources on completion without closing resources owned by another isolate.
- [x] Make scheduling idempotent and cancellable when user signs out or disables background sync.
- [x] Keep iOS background sync off by default until the user explicitly enables it.
- [x] Keep optional background initialization off the foreground startup critical path.
- [x] Contain initialization, scheduling, cancellation, execution, and cleanup failures without propagating them into the foreground app.

Suggested task identifier:

```text
com.jeerovan.fife.data_sync
```

Keep identifier identical in Dart, AppDelegate registration, and `BGTaskSchedulerPermittedIdentifiers`.

### Phase E — Make background work bounded and resumable

**Status:** IMPLEMENTED AND AUTOMATED REGRESSIONS PASS; PHYSICAL EXPIRATION REMAINS INCONCLUSIVE

- [x] Pass one absolute deadline through reconciliation, sync, and task dispatch.
- [x] Reserve cleanup/commit time before deadline.
- [x] Reconcile at most a bounded number of roots/items per invocation.
- [x] Dispatch at most one transfer at a time in the iOS background isolate.
- [x] Gate encrypted parts using a conservative estimate and remaining budget.
- [x] Preserve cursors, task state, attempts, manifest state, and errors at durable boundaries.
- [x] Return failure for deferred, retryable or unfinished work to the native task callback.
- [x] Treat OS expiration/cancellation as interruption, not task success.
- [x] Reuse main's operation leases across foreground and background work.

The 2026-10-07 implementation uses an absolute 20-second work window starting at native task delivery. Before starting a part it reserves five seconds plus two seconds of preparation and the estimated transfer duration: half the last successful measured rate, capped at 16 MiB/s, with a conservative 1 MiB/s fallback. This is a heuristic; expiration still aborts actual HTTP requests and checks file streams. Scans rotate through at most two active bookmarked roots, cap each snapshot at 256 items, and process at most four metadata pages per direction. A partial scan never applies deletion inference; transaction checkpoints roll back interrupted reconciliation. Oversized roots are deferred to foreground reconciliation rather than partially committed.

Native OS expiration reports failure once and asks Dart to stop. Dart awaits transfer/reconciliation unwind, releases scopes and leases, cancels retry wakes, closes its own HTTP clients and SQLite connection, then acknowledges completion before native engine destruction. Expiration before worker startup destroys the unused engine without running sync. Pending downloads retain attempts and become restartable; completed staging manifests and upload-recovery markers remain durable. Disabled/signed-out callbacks are gated before authentication or reconciliation. Cleanup failures also return failure. Platform calls that cannot be interrupted may still be preempted by iOS; existing durable recovery handles an abruptly terminated process.

Validation: 125 Flutter tests pass with one expected Linux-only skip; 14 native tests pass on the physical iPhone, including completion-once, expiration-before-start, cancellation and cleanup sequencing. Tests cover real stalled HTTP upload/download abortion, incomplete-snapshot protection, lease/scope release and durable interrupted-download recovery. Affected-file analyzer/lint checks and the profile build pass. The short physical retry confirms native enablement, a saved callback handle and available refresh status, but OS pending-request queries remain zero despite successful submission, and development launch/expiration commands produce no worker/expiration receipt. This is inconclusive, not a physical expiration pass. Natural delivery and actual expiration/recovery remain acceptance gates.

The timing policy follows Apple's [background-strategy guidance](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app). For reliable large transfers, evaluate native background `URLSession`; a short Dart callback cannot guarantee that a large part will finish on a slow connection. Natural scheduling, overnight interruption patterns and full lifecycle memory remain separate physical acceptance cases.

### Phase F — Correct onboarding and settings

**Status:** PLATFORM ONBOARDING/SETTINGS IMPLEMENTED

- [x] Show broad storage permission only on Android.
- [x] Show Android foreground-notification permission only when Android quick sync is enabled.
- [x] Do not request a persistent-notification permission for iOS background refresh.
- [x] Add an iOS background-sync setting separate from Android's “sync with notification” setting.
- [x] Explain that iOS scheduling is opportunistic and requires Background App Refresh.
- [x] Trigger safe foreground reconciliation on Explorer startup/resume through main's awaited coordinator.
- [x] Preserve lifecycle guards and same-ID Explorer snapshot refresh from main.

### Phase G — Optional silent push

**Status:** DEFERRED

Do this only if server-triggered sync materially improves product behavior.

- [ ] Add Firebase packages without removing Android dependencies.
- [ ] Add Push Notifications capability and correct `aps-environment` entitlement through Xcode.
- [ ] Keep `remote-notification` background mode only when silent push is active.
- [ ] Never log registration tokens or raw message payloads.
- [ ] Treat silent push as a hint; delivery is not guaranteed.
- [ ] Coalesce push-triggered work with existing reconciliation/sync leases.

### Phase H — Tests and physical validation

**Status:** IN PROGRESS

Automated:

- [x] Main's full analyzer remains clean.
- [x] All existing 57 tests pass; the expanded suite passes 67 tests with one expected Linux-only skip.
- [x] Platform-selection tests prove Android never schedules iOS refresh and iOS never starts foreground service.
- [x] Failure-injection tests prove iOS scheduler initialization, scheduling, cancellation, execution, and cleanup errors are contained.
- [x] Cross-language configuration test keeps the Dart, AppDelegate, and Info.plist task identifier aligned.
- [ ] MethodChannel tests cover usable, malformed, stale, denied, and balanced bookmarks.
- [ ] Background callback tests cover initialization failure, no account, no network, busy lease, partial progress, timeout, retryable failure, and success.
- [x] Reconciliation tests run unchanged on shared code.
- [x] Android debug build passes after iOS integration.
- [x] Android profile build passes after iOS integration.

Physical iPhone/iPad:

- [ ] Fresh install and onboarding with `--dart-define=API_BASE_URL=https://fife.jeero.one`.
- [x] Built-in simulation setup/cold restart works without `NEON_AUTH` — verified 2026-10-06; hosted authentication was tested separately with its approved configuration.
- [x] Real-auth flow works with approved `NEON_AUTH` configuration — actual OTP, expiring-session refresh, logout/login and saved-phrase key recovery verified 2026-10-06.
- [x] Pick local Files folders and reconcile — two On My iPhone roots verified; iCloud/provider testing is excluded from this run.
- [x] Force-stop/relaunch and verify bookmark restoration — local roots verified after cold launch and phone reboot; passcode-protected first-unlock behavior remains unverified.
- [ ] Revoke provider/folder access and verify fail-closed recovery UI.
- [ ] Modify same-ID file and confirm current Explorer view refreshes immediately — Runestone saves/upload identity pass with manual sync; returning alone leaves metadata stale. Native-identity-preserving editor behavior remains unverified.
- [x] Trigger background task from Xcode using Workmanager's documented debug procedure — a delivered forced worker accessed the roots and uploaded; actual expiration and natural delivery are separate unverified cases.
- [x] Validate the tested short foreground/background, screen-lock, Low Power Mode, offline, process-termination and disabled Background App Refresh variants — see B03–B09 for durations and required manual recovery; overnight behavior is deferred.
- [ ] Verify no secret, token, path, hash, recovery phrase, or raw payload appears in logs — bounded known-value review passes; complete console/crash coverage remains unverified.
- [ ] Measure memory and time using small and large encrypted files.
- [x] Confirm tested network, screen-lock and process-interrupted transfers recover without corrupting metadata or plaintext — restored bytes/hashes match; expiration/deadline handling remains deferred in phase E.

## 7. Xcode Configuration Checklist

- [x] Deployment target consistent and supported by all pods.
- [x] Background Modes capability enabled.
- [x] Background fetch enabled for periodic refresh.
- [x] Background processing mode enabled.
- [x] `BGTaskSchedulerPermittedIdentifiers` contains exact registered identifiers.
- [ ] App signing team and bundle identifier correct.
- [ ] iCloud/document-provider behavior tested where supported.
- [ ] Push Notifications capability and entitlement present only if Phase G is enabled.
- [ ] Release archive validates without missing entitlement, background-mode, privacy-manifest, or CocoaPods warnings.

## 8. Transfer and macOS Baseline Commands

Finish on Linux first:

```bash
git switch main
git switch -c feat/ios-main-support
git add -f IOS-MAIN-MIGRATION.md
git status --short
git commit -m "docs: add iOS main migration guide"
git push -u origin feat/ios-main-support
```

Then on macOS:

```bash
git clone --branch feat/ios-main-support <repository-url> file_vault_bb
cd file_vault_bb
git fetch origin --prune
git status --short
git branch --show-current
git merge-base --is-ancestor 402466d HEAD
```

`git merge-base --is-ancestor` must exit successfully. Next run the baseline:

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build ios --debug --no-codesign \
  --dart-define=API_BASE_URL=https://fife.jeero.one
open ios/Runner.xcworkspace
```

Open the same Codex/ChatGPT conversation on macOS when available. Otherwise start a new session in the cloned repository with:

> Read `AGENTS.md` and `IOS-MAIN-MIGRATION.md` completely. Resume Phase A on `feat/ios-main-support`. Keep repaired main as the base. Do not merge `ios` wholesale and do not start Phase B until the 57-test baseline passes.

Do not embed `NEON_AUTH`, test credentials, signing secrets, or Git credentials in this document, source files, shell history shared with others, or committed build scripts.

## 9. Definition of Done

### Merge eligibility without a physical iOS device

This migration slice is eligible for `main` because background sync is an
optional enhancement rather than a correctness dependency:

- iOS background sync defaults to disabled and requires explicit opt-in;
- manual sync remains available through the foreground reconciliation path;
- background initialization does not block foreground startup;
- scheduler and worker failures are logged, contained, and reported as task
  failure without escaping into the foreground application;
- cleanup actions are independently guarded so one cleanup failure cannot skip
  later cleanup or crash the foreground application;
- analyzer, tests, simulator smoke test, iOS build, and Android builds pass.

Physical iPhone/iPad checks remain required before claiming that opportunistic
background execution and real document-provider behavior are production
validated. They do not block merging this fail-safe, opt-in implementation.

### Production validation

iOS background support may be declared physically validated only when:

1. Android foreground service behavior remains physically validated.
2. iOS Workmanager behavior is physically validated on at least one supported iPhone or iPad.
3. Bookmark restoration, revocation, staleness, and release are validated.
4. Main's reconciliation and transfer safety invariants remain unchanged.
5. Analyzer and full test suite pass.
6. Android and iOS builds pass from the same commit.
7. No platform asks for irrelevant permissions or starts an unsupported execution service.
8. Background interruption produces resumable state, not false completion.
9. `SPEC.md`, `PLAN-FIX-ISSUES.md`, README build instructions, and codebase graph are updated.
10. The old `ios` branch is retained until one unified-main release is proven, then archived rather than immediately deleted.

## 10. Primary References

- Workmanager iOS quick start: <https://docs.page/fluttercommunity/flutter_workmanager/quickstart>
- Workmanager debugging: <https://docs.page/fluttercommunity/flutter_workmanager/debugging>
- Apple background tasks: <https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app>
- Apple scheduling semantics: <https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate>
- Firebase Apple background messages: <https://firebase.google.com/docs/cloud-messaging/ios/receive-messages>
