import UIKit
import Flutter
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        WorkmanagerPlugin.registerPeriodicTask(
          withIdentifier: "com.jeerovan.fife.data_sync",
          frequency: NSNumber(value: 16 * 60)
        )
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
            if let flutterEngine = registry as? FlutterEngine {
                // Background MethodChannel binding
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
    
    // Singleton instance to hold state securely across the app lifecycle
    static let shared = SecureStorageManager()
    
    var activeUrls: [String: URL] = [:]
    var pendingResult: FlutterResult? // Temporarily holds the Flutter result while picker is open
    
    // Static method that can be called from the C-style closure without capturing context
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.jeerovan.fife/channel_storage", binaryMessenger: messenger)
        
        channel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "pickDirectory":
                SecureStorageManager.shared.pickDirectory(result: result)
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
    
    func pickDirectory(result: @escaping FlutterResult) {
        // Must run on main thread since it's a UI operation
        DispatchQueue.main.async {
            self.pendingResult = result
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            documentPicker.delegate = self
            
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                rootVC.present(documentPicker, animated: true)
            } else {
                result(FlutterError(code: "UI_ERROR", message: "No root view controller found", details: nil))
            }
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
            let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                activeUrls[url.path] = url
                result(url.path)
            } else {
                result(FlutterError(code: "ACCESS_DENIED", message: "Failed to access scoped resource", details: nil))
            }
        } catch {
            result(FlutterError(code: "RESOLVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    func stopAccessing(path: String, result: FlutterResult) {
        if let url = activeUrls[path] {
            url.stopAccessingSecurityScopedResource()
            activeUrls.removeValue(forKey: path)
            result(true)
        } else {
            result(false) // Was not actively accessing
        }
    }
}