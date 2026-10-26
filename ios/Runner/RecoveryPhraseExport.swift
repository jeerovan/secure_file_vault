import Flutter
import UIKit

/// A tiny, exclusively owned export, serialized on the main platform thread.
/// A cleanup from any Flutter engine invalidates reserved late publications.
final class IosRecoveryPhraseExport: NSObject, UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate {
    static let shared = IosRecoveryPhraseExport()
    private let root: URL
    private let canExport: () -> Bool
    private let presenter: () -> UIViewController?
    private var epoch = UUID().uuidString
    private var completion: FlutterResult?
    private var picker: UIDocumentPickerViewController?
    private var activeReservation: String?
    private var finishing = false

    init(root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FiFeRecoveryExports", isDirectory: true),
         canExport: @escaping () -> Bool = { AppLockPrivacy.shared.allowsRecoveryExport },
         presentingController: (() -> UIViewController?)? = nil) {
        self.root = root
        self.canExport = canExport
        self.presenter = presentingController ?? Self.activePresenter
        super.init()
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.jeerovan.fife/recovery_export",
                                          binaryMessenger: messenger)
        channel.setMethodCallHandler { [self] call, result in
            DispatchQueue.main.async {
                self.handle(call, result: result)
            }
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
                switch call.method {
                case "clear":
                    self.clear(result: result)
                case "release":
                    // An old Dart future must never cancel a newer export.
                    if let token = call.arguments as? String,
                       token == self.activeReservation || token == self.epoch {
                        self.clear(result: result)
                    } else { result(nil) }
                case "reserve":
                    guard self.canExport(),
                          self.completion == nil, !self.finishing else { result(self.failure()); return }
                    self.epoch = UUID().uuidString
                    result(self.epoch)
                case "save":
                    self.save(call.arguments, result: result)
                default: result(FlutterMethodNotImplemented)
                }
    }

    private func save(_ arguments: Any?, result: @escaping FlutterResult) {
        guard completion == nil, !finishing, canExport(),
              let args = arguments as? [String: Any],
              let reservation = args["reservation"] as? String, reservation == epoch,
              let text = args["text"] as? String, text.split(separator: " ").count == 24,
              let presenter = presenter() else { result(failure()); return }
        epoch = UUID().uuidString // A reservation authorizes one publication only.
        activeReservation = reservation
        completion = result
        do {
            try clearFiles()
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            let file = directory.appendingPathComponent("fife_recovery_phrase.txt")
            try Data(text.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            let dialog = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
            dialog.title = args["title"] as? String
            dialog.delegate = self
            dialog.presentationController?.delegate = self
            picker = dialog
            presenter.present(dialog, animated: true) {
                dialog.presentationController?.delegate = self
                if dialog.presentingViewController == nil { self.finish(saved: false) }
            }
        } catch {
            finish(saved: false, failed: true)
        }
    }

    private static func activePresenter() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
        var current = windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let next = current?.presentedViewController, !next.isBeingDismissed { current = next }
        return current
    }

    private func clearFiles() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func failure() -> FlutterError {
        FlutterError(code: "RECOVERY_EXPORT_UNAVAILABLE",
            message: "Protected export unavailable", details: nil)
    }

    private func clear(result: @escaping FlutterResult) {
        epoch = UUID().uuidString
        finish(saved: false)
        do { try clearFiles(); result(nil) } catch { result(failure()) }
    }

    private func finish(saved: Bool, failed: Bool = false) {
        guard let reply = completion else { return }
        let dialog = picker
        completion = nil
        picker = nil
        activeReservation = nil
        dialog?.delegate = nil
        dialog?.presentationController?.delegate = nil
        finishing = true
        let value: Any
        do {
            try clearFiles()
            value = failed ? failure() : saved
        } catch { value = failure() }
        var responded = false
        let respond = { [self] in
            guard !responded else { return }
            responded = true
            self.finishing = false
            reply(value)
        }
        if let dialog = dialog, dialog.presentingViewController != nil {
            dialog.dismiss(animated: false, completion: respond)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: respond)
        } else { respond() }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard controller === picker else { return }
        finish(saved: false)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard controller === picker else { return }
        finish(saved: !urls.isEmpty)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === picker else { return }
        finish(saved: false)
    }
}
