import Flutter
import QuickLook
import UIKit
import UniformTypeIdentifiers

protocol FileDocumentPresenting: AnyObject {
    var interactionController: UIDocumentInteractionController { get }
    var delegate: UIDocumentInteractionControllerDelegate? { get set }
    func showPreview() -> Bool
    func showOpenIn(from rect: CGRect, in view: UIView) -> Bool
    func closePresentation()
}

extension UIDocumentInteractionController: FileDocumentPresenting {
    var interactionController: UIDocumentInteractionController { self }
    func showPreview() -> Bool { presentPreview(animated: true) }
    func showOpenIn(from rect: CGRect, in view: UIView) -> Bool {
        presentOpenInMenu(from: rect, in: view, animated: true)
    }
    func closePresentation() {
        dismissPreview(animated: false)
        dismissMenu(animated: false)
    }
}

/// Resolves every request, including UIKit declining both preview and Open In.
/// Dart retains the source bookmark until presentation ends or is cancelled.
final class IosFileViewer: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = IosFileViewer()
    private let makeDocument: (URL) -> FileDocumentPresenting
    private let canPreview: (URL) -> Bool
    private let presentingController: () -> UIViewController?
    private var document: FileDocumentPresenting?
    private weak var presenter: UIViewController?
    private var completion: FlutterResult?
    private var sendingToApplication = false
    private var presentationEnded = false
    private var cancellationRequested = false

    init(
        makeDocument: @escaping (URL) -> FileDocumentPresenting = {
            UIDocumentInteractionController(url: $0)
        },
        canPreview: @escaping (URL) -> Bool = {
            QLPreviewController.canPreview($0 as NSURL)
        },
        presentingController: @escaping () -> UIViewController? = {
            guard UIApplication.shared.applicationState == .active else { return nil }
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap { $0.windows }
            var current = windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let next = current?.presentedViewController, !next.isBeingDismissed {
                current = next
            }
            return current
        }
    ) {
        self.makeDocument = makeDocument
        self.canPreview = canPreview
        self.presentingController = presentingController
        super.init()
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.jeerovan.fife/file_viewer",
                                          binaryMessenger: messenger)
        channel.setMethodCallHandler { [self] call, result in
            DispatchQueue.main.async {
                switch call.method {
                case "open":
                    guard let args = call.arguments as? [String: Any],
                          let path = args["path"] as? String, path.hasPrefix("/") else {
                        result("failed")
                        return
                    }
                    self.open(path: path, result: result)
                case "cancel":
                    self.cancel()
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }
    }

    func open(path: String, result: @escaping FlutterResult) {
        guard completion == nil else { result("cancelled"); return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else {
            result("missing")
            return
        }
        guard !directory.boolValue, FileManager.default.isReadableFile(atPath: path) else {
            result("denied")
            return
        }
        let url = URL(fileURLWithPath: path)
        let type: UTType?
        do {
            type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        } catch {
            result("failed")
            return
        }
        // A dynamic/generic byte-stream type has no declared document format.
        // UIKit can still offer an empty generic Open In screen for it.
        guard let type = type, type.isDeclared,
              type != .data, type != .item, type != .content else {
            result("unsupported")
            return
        }
        guard let host = presentingController(), host.view.window != nil,
              !host.isBeingDismissed, !host.isBeingPresented,
              host.view.bounds.width > 0, host.view.bounds.height > 0 else {
            result("failed")
            return
        }
        let controller = makeDocument(url)
        document = controller
        presenter = host
        completion = result
        sendingToApplication = false
        presentationEnded = false
        cancellationRequested = false
        controller.delegate = self
        if canPreview(url) && controller.showPreview() { return }
        let bounds = host.view.bounds
        let anchor = CGRect(x: bounds.midX,
                            y: max(bounds.minY, bounds.maxY - host.view.safeAreaInsets.bottom - 1),
                            width: 1, height: 1)
        if controller.showOpenIn(from: anchor, in: host.view) { return }
        finish("unsupported")
    }

    func cancel() {
        let active = document
        guard !cancellationRequested else { return }
        if sendingToApplication {
            // Close private UI now, but don't release the scoped source while
            // UIKit is still handing it to another application.
            cancellationRequested = true
            presentationEnded = true
            active?.closePresentation()
            return
        }
        active?.delegate = nil
        finish("cancelled")
        active?.closePresentation()
    }

    private func finish(_ status: String) {
        let callback = completion
        completion = nil
        document?.delegate = nil
        document = nil
        presenter = nil
        sendingToApplication = false
        presentationEnded = false
        cancellationRequested = false
        callback?(status)
    }

    func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        presenter ?? UIViewController()
    }

    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        presentationDidEnd(controller)
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        presentationDidEnd(controller)
    }

    private func presentationDidEnd(_ controller: UIDocumentInteractionController) {
        guard document?.interactionController === controller else { return }
        presentationEnded = true
        if !sendingToApplication { finish(cancellationRequested ? "cancelled" : "opened") }
    }

    func documentInteractionController(_ controller: UIDocumentInteractionController,
                                       willBeginSendingToApplication application: String?) {
        guard document?.interactionController === controller else { return }
        sendingToApplication = true
    }

    func documentInteractionController(_ controller: UIDocumentInteractionController,
                                       didEndSendingToApplication application: String?) {
        guard document?.interactionController === controller else { return }
        sendingToApplication = false
        if presentationEnded { finish(cancellationRequested ? "cancelled" : "opened") }
    }
}
