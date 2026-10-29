import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// Writes only to an explicitly confirmed destination; no plaintext temp file.
/// A reservation and epoch prevent a canceled/obsolete sheet from publishing.
final class MacOSRecoveryPhraseExport {
  static let shared = MacOSRecoveryPhraseExport()
  private weak var window: NSWindow?
  private var epoch = UUID().uuidString
  private var activeReservation: String?
  private var panel: NSSavePanel?
  private var completion: FlutterResult?
  private var bytes: Data?

  func register(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    let channel = FlutterMethodChannel(name: "com.jeerovan.fife/recovery_export", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "clear": self.clear(); result(nil)
      case "release":
        if let token = call.arguments as? String,
           token == self.epoch || token == self.activeReservation { self.clear() }
        result(nil)
      case "reserve":
        guard self.panel == nil, MacOSAppPrivacy.shared.allowsRecoveryExport else { result(self.failure()); return }
        self.epoch = UUID().uuidString; result(self.epoch)
      case "save": self.save(call.arguments, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func failure() -> FlutterError {
    FlutterError(code: "RECOVERY_EXPORT_UNAVAILABLE", message: "Protected export unavailable", details: nil)
  }

  private func save(_ arguments: Any?, result: @escaping FlutterResult) {
    guard panel == nil, MacOSAppPrivacy.shared.allowsRecoveryExport,
          let window = window, let args = arguments as? [String: Any],
          let token = args["reservation"] as? String, token == epoch,
          let text = args["text"] as? String, text.split(separator: " ").count == 24 else {
      result(failure()); return
    }
    epoch = UUID().uuidString
    activeReservation = token
    bytes = Data(text.utf8)
    completion = result
    let dialog = NSSavePanel()
    dialog.nameFieldStringValue = "fife_recovery_phrase.txt"
    dialog.allowedContentTypes = [.plainText]
    dialog.canCreateDirectories = true
    dialog.title = args["title"] as? String ?? "FiFe"
    panel = dialog
    dialog.beginSheetModal(for: window) { [weak self, weak dialog] response in
      guard let self = self, let dialog = dialog,
            self.panel === dialog, self.activeReservation == token else { return }
      var saved = false
      if response == .OK, let url = dialog.url, let data = self.bytes {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try data.write(to: url, options: .atomic); saved = true }
        catch { self.finish(self.failure()); return }
      }
      self.finish(saved)
    }
  }

  func clear() {
    epoch = UUID().uuidString
    let previous = panel
    finish(false)
    if let previous = previous {
      window?.endSheet(previous, returnCode: .cancel)
      previous.orderOut(nil)
    }
  }

  private func finish(_ value: Any) {
    let reply = completion
    completion = nil; panel = nil; activeReservation = nil
    if let count = bytes?.count { bytes?.resetBytes(in: 0..<count) }
    bytes = nil
    reply?(value)
  }
}
