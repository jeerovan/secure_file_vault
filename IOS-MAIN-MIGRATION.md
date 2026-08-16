# iOS Support on `main`: Migration and macOS Handoff

**Status:** READY FOR MACOS IMPLEMENTATION  
**Prepared:** 2026-08-16  
**Remote state verified:** 2026-08-16  
**Recommended base:** `origin/main` at `402466d`  
**Reference branch:** `ios` at `5a7dc9c`  
**Merge base:** `ea066e01fad1dc1f629b03192feebda8098d483f`

## 1. Objective

Support Android, iOS, macOS, Windows, and Linux from `main` without weakening the reconciliation, persistence, transfer, authentication, logging, and UI fixes already completed on `main`.

Platform execution must remain distinct:

- Android uses its foreground service and persistent notification for dependable long-running work.
- iOS uses Workmanager/BGTaskScheduler. It must never try to start the Android-style foreground service.
- iOS and macOS use security-scoped bookmarks for user-selected folders.
- Android alone requires broad storage-permission onboarding.
- Desktop platforms retain their current foreground/timer behavior.

This migration does not promise exact-period iOS execution. Apple controls scheduling. Large, dependable background uploads may ultimately require native background `URLSession`, not only a Dart Workmanager callback.

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

**Status:** REMOTE MAIN READY; MACOS CHECKOUT NOT STARTED

- [x] Push latest repaired main commits; `main` and `origin/main` now both resolve to `402466d`.
- [ ] Commit this guide alone on `feat/ios-main-support` from main.
- [ ] Clone/fetch `feat/ios-main-support` on macOS and verify its main parent is `402466d`.
- [ ] Confirm analyzer is clean and all 57 main tests pass before migration edits.
- [ ] Record Xcode, Flutter, Dart, CocoaPods, and physical-device versions.

### Phase B — Restore iOS build dependencies safely

**Status:** NOT STARTED

- [ ] Add `workmanager` to main's dependencies.
- [ ] Retain `flutter_foreground_task`, `permission_handler`, and `file_picker`; Android still needs them.
- [ ] Do not add Firebase packages during the first migration slice.
- [ ] Regenerate and commit `pubspec.lock` from macOS.
- [ ] Set one consistent minimum iOS target. Prefer 15 unless product requirements demand iOS 14.
- [ ] Set the same target in Xcode project, Podfile, and generated pod build settings.
- [ ] Run `pod install` through normal Flutter tooling and open `ios/Runner.xcworkspace`, not the project file.

Acceptance:

- Android dependency resolution remains unchanged except for Workmanager's added transitive packages.
- `flutter build ios --debug --no-codesign` succeeds on macOS.
- Android build still succeeds after dependency integration.

### Phase C — Repair native iOS bookmarks

**Status:** NOT STARTED

- [ ] Port directory picker and MethodChannel registration from `ios/Runner/AppDelegate.swift`.
- [ ] Register the storage channel for both foreground engine and Workmanager background engine.
- [ ] Preserve main's `ChannelStorage.hasUsableBookmark` checks.
- [ ] Return the resolved path from `startAccessing`.
- [ ] Pass that resolved path—not bookmark data—to `stopAccessing`.
- [ ] Add reference counts keyed by canonical resolved path.
- [ ] Detect stale bookmarks. Refresh stored bookmark data when possible; otherwise require explicit re-selection.
- [ ] Never present a document picker from a headless background isolate.
- [ ] Release all acquired resources in `finally`.

Acceptance:

- Folder survives app termination and relaunch.
- Revoked, malformed, empty, legacy `sandboxed`, and stale bookmarks fail closed.
- Concurrent/repeated access remains balanced.
- Failed reconciliation leaves zero leaked active accesses.

### Phase D — Add platform-specific execution service

**Status:** NOT STARTED

- [ ] Replace direct platform checks scattered through startup/setup/settings with one execution service.
- [ ] Initialize `ServiceForeground` only on Android.
- [ ] Schedule Workmanager only on iOS.
- [ ] Keep desktop autosync behavior unchanged.
- [ ] Add a dedicated `ExecutionMode.backgroundWorker` or equivalent; do not pretend the iOS isolate is an Android foreground service.
- [ ] Add `@pragma('vm:entry-point')` to the top-level Workmanager dispatcher.
- [ ] Initialize bindings, SQLite, settings cache, crypto, auth, clients, and logger inside the background isolate.
- [ ] Close isolate-owned resources on completion without closing resources owned by another isolate.
- [ ] Make scheduling idempotent and cancellable when user signs out or disables background sync.

Suggested task identifier:

```text
com.jeerovan.fife.data_sync
```

Keep identifier identical in Dart, AppDelegate registration, and `BGTaskSchedulerPermittedIdentifiers`.

### Phase E — Make background work bounded and resumable

**Status:** NOT STARTED

- [ ] Pass one absolute deadline through reconciliation, sync, and task dispatch.
- [ ] Reserve cleanup/commit time before deadline.
- [ ] Reconcile at most a bounded number of roots/items per invocation.
- [ ] Dispatch at most one transfer at a time on iOS.
- [ ] Do not start an encrypted part that cannot reasonably finish inside remaining budget.
- [ ] Persist cursors, task state, attempts, manifest state, and errors after each durable unit.
- [ ] Propagate retryable failures to Workmanager instead of swallowing them.
- [ ] Treat OS expiration/cancellation as interruption, not task success.
- [ ] Reuse main's operation leases so foreground and background sync cannot mutate the same state concurrently.

For reliable large transfers, evaluate native background `URLSession`. Workmanager can schedule/control work, but should not be assumed to keep arbitrary Dart uploads alive indefinitely.

### Phase F — Correct onboarding and settings

**Status:** NOT STARTED

- [ ] Show broad storage permission only on Android.
- [ ] Show Android foreground-notification permission only when Android quick sync is enabled.
- [ ] Do not request a persistent-notification permission for iOS Workmanager.
- [ ] Add an iOS background-sync setting separate from Android's “sync with notification” setting.
- [ ] Explain that iOS scheduling is opportunistic and requires Background App Refresh.
- [ ] Trigger safe foreground reconciliation on Explorer startup/resume through main's awaited coordinator.
- [ ] Preserve lifecycle guards and same-ID Explorer snapshot refresh from main.

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

**Status:** NOT STARTED

Automated:

- [ ] Main's full analyzer remains clean.
- [ ] All existing 57 tests pass.
- [ ] Platform-selection tests prove Android never schedules Workmanager and iOS never starts foreground service.
- [ ] MethodChannel tests cover usable, malformed, stale, denied, and balanced bookmarks.
- [ ] Background callback tests cover initialization failure, no account, no network, busy lease, partial progress, timeout, retryable failure, and success.
- [ ] Reconciliation tests run unchanged on shared code.
- [ ] Android debug/profile builds pass after iOS integration.

Physical iPhone/iPad:

- [ ] Fresh install and onboarding with `--dart-define=API_BASE_URL=https://fife.jeero.one`.
- [ ] Test-account cold restart works without `NEON_AUTH`; obtain test credentials out of band and never commit them.
- [ ] Real-auth flow works with approved `NEON_AUTH` configuration.
- [ ] Pick local/iCloud Drive folder and reconcile.
- [ ] Force-stop/relaunch and verify bookmark restoration.
- [ ] Revoke provider/folder access and verify fail-closed recovery UI.
- [ ] Modify same-ID file and confirm current Explorer view refreshes immediately.
- [ ] Trigger background task from Xcode using Workmanager's documented debug procedure.
- [ ] Validate foreground/background transitions, screen lock, low-power mode, offline mode, process termination, and Background App Refresh disabled.
- [ ] Verify no secret, token, path, hash, recovery phrase, or raw payload appears in logs.
- [ ] Measure memory and time using small and large encrypted files.
- [ ] Confirm interrupted transfers resume without corrupting metadata or plaintext.

## 7. Xcode Configuration Checklist

- [ ] Deployment target consistent and supported by all pods.
- [ ] Background Modes capability enabled.
- [ ] Background fetch enabled if using periodic fetch.
- [ ] Background processing enabled for BGProcessingTask.
- [ ] `BGTaskSchedulerPermittedIdentifiers` contains exact registered identifiers.
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

iOS support may be declared part of `main` only when:

1. Android foreground service behavior remains physically validated.
2. iOS Workmanager behavior is physically validated on at least one supported iPhone.
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
