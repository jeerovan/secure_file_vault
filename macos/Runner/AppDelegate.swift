import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      MacOSStorageChannel.register(with: controller.engine.binaryMessenger)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

final class MacOSStorageChannel {
  private static var activeURLs: [String: (url: URL, count: Int)] = [:]

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.jeerovan.fife/channel_storage",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickDirectory":
        let arguments = call.arguments as? [String: Any]
        pickDirectory(initialPath: arguments?["path"] as? String, result: result)
      case "startAccessing":
        guard let arguments = call.arguments as? [String: Any],
              let bookmark = arguments["bookmark"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing bookmark", details: nil))
          return
        }
        startAccessing(bookmarkBase64: bookmark, result: result)
      case "stopAccessing":
        guard let arguments = call.arguments as? [String: Any],
              let path = arguments["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
          return
        }
        stopAccessing(path: path, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func pickDirectory(initialPath: String?, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      if let initialPath = initialPath, !initialPath.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: initialPath)
      }
      panel.begin { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        do {
          let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
          result(["path": url.path, "bookmark": bookmark.base64EncodedString()])
        } catch {
          result(FlutterError(
            code: "BOOKMARK_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private static func startAccessing(bookmarkBase64: String, result: FlutterResult) {
    guard let data = Data(base64Encoded: bookmarkBase64) else {
      result(FlutterError(code: "DECODE_ERROR", message: "Invalid bookmark", details: nil))
      return
    }
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      guard !isStale else {
        result(FlutterError(
          code: "STALE_BOOKMARK",
          message: "Folder access must be selected again",
          details: nil
        ))
        return
      }
      if let active = activeURLs[url.path] {
        activeURLs[url.path] = (active.url, active.count + 1)
        result(url.path)
      } else if url.startAccessingSecurityScopedResource() {
        activeURLs[url.path] = (url, 1)
        result(url.path)
      } else {
        result(FlutterError(code: "ACCESS_DENIED", message: "Folder access denied", details: nil))
      }
    } catch {
      result(FlutterError(code: "RESOLVE_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private static func stopAccessing(path: String, result: FlutterResult) {
    guard let active = activeURLs[path] else {
      result(false)
      return
    }
    if active.count > 1 {
      activeURLs[path] = (active.url, active.count - 1)
    } else {
      active.url.stopAccessingSecurityScopedResource()
      activeURLs.removeValue(forKey: path)
    }
    result(true)
  }
}
