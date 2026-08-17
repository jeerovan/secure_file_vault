import UIKit
import Flutter
import UniformTypeIdentifiers
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        WorkmanagerPlugin.registerPeriodicTask(
            withIdentifier: "com.jeerovan.fife.data_sync",
            earliestBeginInSeconds: NSNumber(value: 15 * 60)
        )
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
            if let flutterEngine = registry as? FlutterEngine {
                SecureStorageManager.register(with: flutterEngine.binaryMessenger)
            }
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
      GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
      SecureStorageManager.register(with: engineBridge.applicationRegistrar.messenger())
    }
}

// MARK: - Secure Storage Manager Singleton

class SecureStorageManager: NSObject, UIDocumentPickerDelegate {
    static let shared = SecureStorageManager()

    private struct ActiveAccess {
        let url: URL
        var referenceCount: Int
    }

    private var activeAccesses: [String: ActiveAccess] = [:]
    private let accessLock = NSLock()
    private var pendingResult: FlutterResult?
    
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
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard !isStale else {
                result(FlutterError(code: "STALE_BOOKMARK", message: "Folder access must be selected again", details: nil))
                return
            }

            let canonicalURL = resolvedURL.resolvingSymlinksInPath().standardizedFileURL
            let canonicalPath = canonicalURL.path

            accessLock.lock()
            if var activeAccess = activeAccesses[canonicalPath] {
                activeAccess.referenceCount += 1
                activeAccesses[canonicalPath] = activeAccess
                accessLock.unlock()
                result(canonicalPath)
                return
            }

            guard canonicalURL.startAccessingSecurityScopedResource() else {
                accessLock.unlock()
                result(FlutterError(code: "ACCESS_DENIED", message: "Failed to access scoped resource", details: nil))
                return
            }
            activeAccesses[canonicalPath] = ActiveAccess(url: canonicalURL, referenceCount: 1)
            accessLock.unlock()
            result(canonicalPath)
        } catch {
            result(FlutterError(code: "RESOLVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    func stopAccessing(path: String, result: FlutterResult) {
        let canonicalPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path

        accessLock.lock()
        guard var activeAccess = activeAccesses[canonicalPath] else {
            accessLock.unlock()
            result(false)
            return
        }

        activeAccess.referenceCount -= 1
        if activeAccess.referenceCount == 0 {
            activeAccesses.removeValue(forKey: canonicalPath)
            activeAccess.url.stopAccessingSecurityScopedResource()
        } else {
            activeAccesses[canonicalPath] = activeAccess
        }
        accessLock.unlock()
        result(true)
    }
}
