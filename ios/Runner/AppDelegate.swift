import UIKit
import Flutter
import UniformTypeIdentifiers
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        IosBackgroundSync.shared.registerLaunchHandler()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
      GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
      SecureStorageManager.register(with: engineBridge.applicationRegistrar.messenger())
      IosBackgroundSync.shared.registerScheduler(with: engineBridge.applicationRegistrar.messenger())
    }
}

/// Completion is reported once. OS expiration reports failure promptly but
/// keeps the engine alive until Dart acknowledges its resource cleanup.
final class BackgroundSyncSession {
    private(set) var expired = false
    private(set) var finished = false
    private var reported = false
    var started = false
    var cancelWork: () -> Void = {}
    var cleanup: () -> Void = {}
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) { self.completion = completion }

    func expire(reportImmediately: Bool = true) {
        guard !finished else { return }
        if !expired {
            expired = true
            cancelWork()
        }
        if reportImmediately { report(false) }
        if !started { finish(success: false) }
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        report(success && !expired)
        cleanup()
    }

    private func report(_ success: Bool) {
        guard !reported else { return }
        reported = true
        completion(success)
    }
}

final class IosBackgroundSync {
    static let shared = IosBackgroundSync()
    static let identifier = "com.jeerovan.fife.data_sync"
    private let handleKey = "fife.backgroundSync.callbackHandle"
    private let enabledKey = "fife.backgroundSync.enabled"
    private var registered = false
    private var active: BackgroundSyncSession?
    private var engine: FlutterEngine?
    private var workerChannel: FlutterMethodChannel?
    private var deadlineTimer: Timer?

    func registerLaunchHandler() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier, using: nil
        ) { task in
            DispatchQueue.main.async { self.run(task) }
        }
    }

    func registerScheduler(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.jeerovan.fife/background_scheduler", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "initialize":
                guard self.registered,
                      let args = call.arguments as? [String: Any],
                      let handle = args["callbackHandle"] as? NSNumber,
                      FlutterCallbackCache.lookupCallbackInformation(handle.int64Value) != nil else {
                    result(FlutterError(code: "BACKGROUND_UNAVAILABLE", message: "Background entrypoint unavailable", details: nil))
                    return
                }
                UserDefaults.standard.set(handle, forKey: self.handleKey)
                result(nil)
            case "schedule":
                do {
                    try self.schedule()
                    UserDefaults.standard.set(true, forKey: self.enabledKey)
                    result(nil)
                } catch {
                    result(FlutterError(code: "SCHEDULE_FAILED", message: "Background request rejected", details: nil))
                }
            case "cancel":
                UserDefaults.standard.set(false, forKey: self.enabledKey)
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
                self.active?.expire(reportImmediately: false)
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    private func schedule() throws {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try BGTaskScheduler.shared.submit(request)
    }

    private func run(_ task: BGTask) {
        guard task is BGAppRefreshTask, active == nil else {
            task.setTaskCompleted(success: false)
            return
        }
        // A callback delivered after disabling/sign-out must not start Dart.
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            task.setTaskCompleted(success: true)
            return
        }
        guard let handle = UserDefaults.standard.object(forKey: handleKey) as? NSNumber,
              let callback = FlutterCallbackCache.lookupCallbackInformation(handle.int64Value) else {
            task.setTaskCompleted(success: false)
            return
        }
        try? schedule()
        let deadline = Date(timeIntervalSinceNow: 20)
        let session = BackgroundSyncSession { success in
            task.setTaskCompleted(success: success)
            NSLog("FiFe background sync completed success=%d", success ? 1 : 0)
        }
        active = session
        session.cancelWork = { [weak self] in
            self?.workerChannel?.invokeMethod("expire", arguments: nil)
        }
        session.cleanup = { [weak self, weak task] in
            task?.expirationHandler = nil
            self?.deadlineTimer?.invalidate()
            self?.deadlineTimer = nil
            self?.workerChannel?.setMethodCallHandler(nil)
            self?.workerChannel = nil
            self?.engine?.destroyContext()
            self?.engine = nil
            self?.active = nil
            NSLog("FiFe background sync resources released")
        }
        task.expirationHandler = {
            DispatchQueue.main.async {
                NSLog("FiFe background sync expired")
                session.expire()
            }
        }
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
            session.expire(reportImmediately: false)
        }
        let engine = FlutterEngine(name: "FiFe.backgroundSync", project: nil, allowHeadlessExecution: true)
        self.engine = engine
        guard engine.run(withEntrypoint: callback.callbackName, libraryURI: callback.callbackLibraryPath) else {
            session.finish(success: false)
            return
        }
        GeneratedPluginRegistrant.register(with: engine)
        SecureStorageManager.register(with: engine.binaryMessenger)
        let worker = FlutterMethodChannel(name: "com.jeerovan.fife/background_worker", binaryMessenger: engine.binaryMessenger)
        workerChannel = worker
        worker.setMethodCallHandler { call, result in
            switch call.method {
            case "ready":
                session.started = true
                result(["deadline": Int64(deadline.timeIntervalSince1970 * 1000), "expired": session.expired])
                NSLog("FiFe background sync started")
            case "finished":
                result(nil)
                // Let the platform reply reach Dart before destroying its engine.
                DispatchQueue.main.async { session.finish(success: call.arguments as? Bool == true) }
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
}

// MARK: - Secure Storage Manager Singleton

class SecureStorageManager: NSObject, UIDocumentPickerDelegate {
    static let shared = SecureStorageManager()

    private struct ActiveAccess {
        let url: URL
        let hasSecurityScope: Bool
        var referenceCount: Int
    }

    private var activeAccesses: [String: ActiveAccess] = [:]
    private let accessLock = NSLock()
    private var pendingResult: FlutterResult?

    private let resolveBookmark: (Data) throws -> (url: URL, isStale: Bool)
    private let startScope: (URL) -> Bool
    private let stopScope: (URL) -> Void
    private let sandboxURL: URL

    init(
        sandboxURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        resolveBookmark: @escaping (Data) throws -> (url: URL, isStale: Bool) = { data in
            var isStale = false
            let url = try URL(resolvingBookmarkData: data,
                              options: [.withoutUI, .withoutImplicitStartAccessing],
                              relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        },
        startScope: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopScope: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.sandboxURL = sandboxURL
        self.resolveBookmark = resolveBookmark
        self.startScope = startScope
        self.stopScope = stopScope
        super.init()
    }
    
    // Static method that can be called from the C-style closure without capturing context
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.jeerovan.fife/channel_storage", binaryMessenger: messenger)
        
        channel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "pickDirectory":
                let args = call.arguments as? [String: Any]
                let initialPath = args?["path"] as? String
                SecureStorageManager.shared.pickDirectory(initialPath: initialPath, result: result)
            case "startAccessing":
                if let args = call.arguments as? [String: Any], let bookmarkBase64 = args["bookmark"] as? String {
                    SecureStorageManager.shared.startAccessing(bookmarkBase64: bookmarkBase64, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing bookmark", details: nil))
                }
            case "stopAccessing":
                if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
                    SecureStorageManager.shared.stopAccessing(path: path, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    // MARK: - Directory Picker Logic
    
    func pickDirectory(initialPath: String?,result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard self.pendingResult == nil else {
                result(FlutterError(code: "PICKER_BUSY", message: "A document picker is already active", details: nil))
                return
            }
            self.pendingResult = result
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            if let path = initialPath {
                documentPicker.directoryURL = URL(fileURLWithPath: path)
            }
            documentPicker.delegate = self
            
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                
                result(FlutterError(code: "UI_ERROR", message: "Cannot present UI from a background headless isolate", details: nil))
                self.pendingResult = nil
                return
            }
            
            rootVC.present(documentPicker, animated: true)
        }
    }
    
    // UIDocumentPickerDelegate Callback
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            pendingResult?(nil)
            pendingResult = nil
            return
        }
        
        guard let accessPath = acquireAccess(to: url) else {
            pendingResult?(FlutterError(code: "ACCESS_DENIED", message: "Failed to access scoped resource", details: nil))
            pendingResult = nil
            return
        }
        defer { _ = releaseAccess(path: accessPath) }

        do {
            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            let base64String = bookmarkData.base64EncodedString()
            pendingResult?(["path": url.path, "bookmark": base64String])
        } catch {
            pendingResult?(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
        }
        pendingResult = nil
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingResult?(nil)
        pendingResult = nil
    }
    
    // MARK: - Background Access Logic
    
    func startAccessing(bookmarkBase64: String, result: FlutterResult) {
        guard let data = Data(base64Encoded: bookmarkBase64) else {
            result(FlutterError(code: "DECODE_ERROR", message: "Invalid Base64", details: nil))
            return
        }
        
        do {
            let (resolvedURL, isStale) = try resolveBookmark(data)
            guard !isStale else {
                result(FlutterError(code: "STALE_BOOKMARK", message: "Folder access must be selected again", details: nil))
                return
            }

            guard let accessPath = acquireAccess(to: resolvedURL) else {
                result(FlutterError(code: "ACCESS_DENIED", message: "Failed to access scoped resource", details: nil))
                return
            }
            result(accessPath)
        } catch {
            result(FlutterError(code: "RESOLVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    func stopAccessing(path: String, result: FlutterResult) {
        result(releaseAccess(path: path))
    }

    private func acquireAccess(to url: URL) -> String? {
        guard url.isFileURL else { return nil }

        accessLock.lock()
        defer { accessLock.unlock() }

        // Security scope belongs to the picker/resolved URL, not a new URL made
        // from its normalized path. Acquire before resolving filesystem aliases.
        let hasSecurityScope = startScope(url)
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        let canonicalPath = canonicalURL.path
        let sandboxComponents = sandboxURL.resolvingSymlinksInPath()
            .standardizedFileURL.pathComponents
        let isInSandbox = canonicalURL.pathComponents.starts(with: sandboxComponents)

        if var activeAccess = activeAccesses[canonicalPath] {
            // Keep one OS scope alive while any foreground/background client
            // holds the root; release this additional successful acquisition.
            if hasSecurityScope { stopScope(url) }
            activeAccess.referenceCount += 1
            activeAccesses[canonicalPath] = activeAccess
            return canonicalPath
        }

        // A bookmark resolving inside this app's sandbox needs no extension.
        // Never fall back to an unscoped persisted path outside that sandbox.
        guard hasSecurityScope || isInSandbox else { return nil }
        activeAccesses[canonicalPath] = ActiveAccess(
            url: url, hasSecurityScope: hasSecurityScope, referenceCount: 1)
        return canonicalPath
    }

    private func releaseAccess(path: String) -> Bool {
        let canonicalPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path

        accessLock.lock()
        defer { accessLock.unlock() }
        guard var activeAccess = activeAccesses[canonicalPath] else {
            return false
        }

        activeAccess.referenceCount -= 1
        if activeAccess.referenceCount == 0 {
            activeAccesses.removeValue(forKey: canonicalPath)
            if activeAccess.hasSecurityScope { stopScope(activeAccess.url) }
        } else {
            activeAccesses[canonicalPath] = activeAccess
        }
        return true
    }
}
