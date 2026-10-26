import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testAppBundleDeclaresItsRequiredPrivacyReasons() throws {
    let url = try XCTUnwrap(Bundle(for: AppDelegate.self)
      .url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    let manifest = try XCTUnwrap(try PropertyListSerialization.propertyList(
      from: Data(contentsOf: url), options: [], format: nil) as? [String: Any])
    let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    let defaults = try XCTUnwrap(entries.first {
      $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
    })
    let reasons = try XCTUnwrap(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String])
    XCTAssertTrue(reasons.contains("CA92.1"))
    let files = try XCTUnwrap(entries.first {
      $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
    })
    let fileReasons = try XCTUnwrap(files["NSPrivacyAccessedAPITypeReasons"] as? [String])
    XCTAssertTrue(fileReasons.contains("C617.1"))
    XCTAssertTrue(fileReasons.contains("3B52.1"))
  }

  func testBackgroundTraceIsOptInAndRemovesPreviousReceiptsWhenDisabled() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let trace = BackgroundTestTrace(url: url)
    trace.record(.submitted)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    trace.setEnabled(true)
    trace.record(.queue, value: 101)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    trace.setEnabled(false)
    trace.record(.delivered)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testBackgroundTraceRetainsBoundedReceiptsAcrossProcessRecreation() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let trace = BackgroundTestTrace(url: url, enabled: true, limit: 3)
    trace.record(.submitted)
    trace.record(.ready)
    trace.record(.expired)
    BackgroundTestTrace(url: url, enabled: true, limit: 3).record(.completed, value: 0)
    let receipts = try JSONDecoder().decode([BackgroundTestTrace.Receipt].self,
                                            from: Data(contentsOf: url))
    XCTAssertEqual(receipts.map { $0.event }, [.ready, .expired, .completed])
    XCTAssertEqual(receipts.last?.value, 0)
    XCTAssertTrue(receipts.allSatisfy { $0.time > 0 })
  }

  func testBackgroundTraceRecoversFromCorruptDataWithoutStoppingWork() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("invalid".utf8).write(to: url)
    BackgroundTestTrace(url: url, enabled: true).record(.released)
    let receipts = try JSONDecoder().decode([BackgroundTestTrace.Receipt].self,
                                            from: Data(contentsOf: url))
    XCTAssertEqual(receipts.map { $0.event }, [.released])
  }

  func testExpirationReportsFailureAndCleansOnlyAfterDartAcknowledges() {
    var results: [Bool] = []
    var cancels = 0
    var cleanups = 0
    let session = BackgroundSyncSession { results.append($0) }
    session.started = true
    session.cancelWork = { cancels += 1 }
    session.cleanup = { cleanups += 1 }
    session.expire()
    session.expire()
    XCTAssertEqual(results, [false])
    XCTAssertEqual(cancels, 1)
    XCTAssertEqual(cleanups, 0)
    session.finish(success: true)
    session.finish(success: true)
    session.expire()
    XCTAssertEqual(results, [false])
    XCTAssertEqual(cleanups, 1)
    XCTAssertEqual(cancels, 1)
  }

  func testExpirationBeforeDartStartsCleansEngineWithoutExecutingWork() {
    var results: [Bool] = []
    var cleanups = 0
    let session = BackgroundSyncSession { results.append($0) }
    session.cleanup = { cleanups += 1 }
    session.expire()
    XCTAssertEqual(results, [false])
    XCTAssertEqual(cleanups, 1)
    XCTAssertTrue(session.finished)
  }

  func testBudgetDeadlineWaitsForCleanupAndCannotReportSuccess() {
    var results: [Bool] = []
    let session = BackgroundSyncSession { results.append($0) }
    session.started = true
    session.expire(reportImmediately: false)
    XCTAssertEqual(results, [])
    session.finish(success: true)
    XCTAssertEqual(results, [false])
  }

  func testSuccessfulTaskReleasesResourcesBeforeReportingCompletion() {
    var released = false
    var results: [Bool] = []
    let session = BackgroundSyncSession { success in
      XCTAssertTrue(released, "Resources must be released before the task is completed")
      results.append(success)
    }
    session.cleanup = { released = true }
    session.finish(success: true)
    session.finish(success: false)
    XCTAssertEqual(results, [true])
  }

  func testDeadlineFailureReleasesResourcesBeforeReportingCompletion() {
    var released = false
    var results: [Bool] = []
    let session = BackgroundSyncSession { success in
      XCTAssertTrue(released, "Cancellation cleanup must precede task completion")
      results.append(success)
    }
    session.started = true
    session.cleanup = { released = true }
    session.expire(reportImmediately: false)
    XCTAssertFalse(released)
    XCTAssertTrue(results.isEmpty)
    session.finish(success: true)
    session.finish(success: true)
    XCTAssertEqual(results, [false])
  }

  func testExpirationBeforeStartReleasesResourcesBeforeReportingCompletion() {
    var released = false
    var results: [Bool] = []
    let session = BackgroundSyncSession { success in
      XCTAssertTrue(released, "An unstarted engine must be released before task completion")
      results.append(success)
    }
    session.cleanup = { released = true }
    session.expire()
    session.expire()
    XCTAssertEqual(results, [false])
  }

  func testSuccessfulCompletionCannotBeChangedByLateExpiration() {
    var results: [Bool] = []
    let session = BackgroundSyncSession { results.append($0) }
    session.finish(success: true)
    session.expire()
    XCTAssertEqual(results, [true])
  }

  private let bookmark = Data([1]).base64EncodedString()

  func testAccessUsesResolvedURLAndBalancesRepeatedAcquisition() {
    let original = URL(fileURLWithPath: "/external/parent/../fixture")
    var starts: [URL] = []
    var stops: [URL] = []
    let manager = SecureStorageManager(
      resolveBookmark: { _ in (original, false) },
      startScope: { url in
        starts.append(url)
        // A URL reconstructed from the canonical path has no scope token.
        return url.absoluteString == original.absoluteString
      },
      stopScope: { stops.append($0) }
    )
    let canonicalPath = original.resolvingSymlinksInPath().standardizedFileURL.path
    for _ in 0..<2 {
      manager.startAccessing(bookmarkBase64: bookmark) { result in
        XCTAssertEqual(result as? String, canonicalPath)
      }
    }
    XCTAssertEqual(starts.count, 2)
    XCTAssertEqual(stops.count, 1)
    manager.stopAccessing(path: canonicalPath) { XCTAssertEqual($0 as? Bool, true) }
    XCTAssertEqual(stops.count, 1)
    manager.stopAccessing(path: canonicalPath) { XCTAssertEqual($0 as? Bool, true) }
    XCTAssertEqual(stops.map(\.absoluteString), Array(repeating: original.absoluteString, count: 2))
    manager.stopAccessing(path: canonicalPath) { XCTAssertEqual($0 as? Bool, false) }
    XCTAssertEqual(stops.count, 2)
  }

  func testSandboxFolderDoesNotRequireSecurityScope() {
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    let folder = root.appendingPathComponent("Documents/fixture", isDirectory: true)
    var stops = 0
    let manager = SecureStorageManager(
      sandboxURL: root,
      resolveBookmark: { _ in (folder, false) },
      startScope: { _ in false },
      stopScope: { _ in stops += 1 }
    )
    let canonicalPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual($0 as? String, canonicalPath)
    }
    manager.stopAccessing(path: canonicalPath) { XCTAssertEqual($0 as? Bool, true) }
    XCTAssertEqual(stops, 0)
  }

  func testDeniedExternalFolderDoesNotFallBackToItsPath() {
    let manager = SecureStorageManager(
      sandboxURL: URL(fileURLWithPath: "/sandbox/app"),
      resolveBookmark: { _ in (URL(fileURLWithPath: "/external/fixture"), false) },
      startScope: { _ in false },
      stopScope: { _ in XCTFail("Denied access must not be released") }
    )
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "ACCESS_DENIED")
    }
    manager.stopAccessing(path: "/external/fixture") { XCTAssertEqual($0 as? Bool, false) }
  }

  func testSandboxPathPrefixDoesNotGrantSiblingContainerAccess() {
    let manager = SecureStorageManager(
      sandboxURL: URL(fileURLWithPath: "/sandbox/app"),
      resolveBookmark: { _ in (URL(fileURLWithPath: "/sandbox/app-other/fixture"), false) },
      startScope: { _ in false }
    )
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "ACCESS_DENIED")
    }
  }

  func testSandboxSymlinkCannotGrantUnscopedExternalAccess() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sandbox = base.appendingPathComponent("sandbox")
    let external = base.appendingPathComponent("external")
    try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let link = sandbox.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
    let manager = SecureStorageManager(
      sandboxURL: sandbox,
      resolveBookmark: { _ in (link, false) },
      startScope: { _ in false }
    )
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "ACCESS_DENIED")
    }
  }

  func testInvalidAndStaleBookmarksNeverStartAccess() {
    var resolutions = 0
    let manager = SecureStorageManager(
      resolveBookmark: { _ in
        resolutions += 1
        return (URL(fileURLWithPath: NSHomeDirectory()), true)
      },
      startScope: { _ in XCTFail("Invalid/stale bookmark must not acquire access"); return true }
    )
    manager.startAccessing(bookmarkBase64: "not-base64!") {
      XCTAssertEqual(($0 as? FlutterError)?.code, "DECODE_ERROR")
    }
    XCTAssertEqual(resolutions, 0)
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "STALE_BOOKMARK")
    }
    XCTAssertEqual(resolutions, 1)
  }

  func testUnresolvableBookmarkNeverStartsAccess() {
    let manager = SecureStorageManager(
      resolveBookmark: { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError) },
      startScope: { _ in XCTFail("Unresolvable bookmark must not acquire access"); return true }
    )
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "RESOLVE_ERROR")
    }
  }

  func testNonFileURLIsDenied() {
    let manager = SecureStorageManager(
      resolveBookmark: { _ in (URL(string: "https://example.com/fixture")!, false) },
      startScope: { _ in XCTFail("Non-file URL must not acquire access"); return true }
    )
    manager.startAccessing(bookmarkBase64: bookmark) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "ACCESS_DENIED")
    }
  }

  func testRealSandboxBookmarkRestoresAndReleases() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let data = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    let manager = SecureStorageManager()
    var accessPath: String?
    manager.startAccessing(bookmarkBase64: data.base64EncodedString()) { accessPath = $0 as? String }
    XCTAssertNotNil(accessPath)
    guard let path = accessPath else { return }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path), [])
    manager.stopAccessing(path: path) { XCTAssertEqual($0 as? Bool, true) }
    manager.stopAccessing(path: path) { XCTAssertEqual($0 as? Bool, false) }
  }

  func testConcurrentClientsKeepAccessUntilLastRelease() {
    let folder = URL(fileURLWithPath: "/external/fixture")
    var starts = 0
    var stops = 0
    let manager = SecureStorageManager(
      resolveBookmark: { _ in (folder, false) },
      startScope: { _ in starts += 1; return true },
      stopScope: { _ in stops += 1 }
    )
    DispatchQueue.concurrentPerform(iterations: 32) { _ in
      manager.startAccessing(bookmarkBase64: bookmark) { XCTAssertEqual($0 as? String, folder.path) }
    }
    XCTAssertEqual(starts, 32)
    XCTAssertEqual(stops, 31)
    DispatchQueue.concurrentPerform(iterations: 32) { _ in
      manager.stopAccessing(path: folder.path) { XCTAssertEqual($0 as? Bool, true) }
    }
    XCTAssertEqual(stops, 32)
    manager.stopAccessing(path: folder.path) { XCTAssertEqual($0 as? Bool, false) }
  }

}

/// UIKit's presentation decisions are controlled here. The separate physical
/// Flutter test exercises the default channel and actual system viewer.
final class FileViewerTests: XCTestCase {
  @MainActor
  private func withFile(_ body: (URL, UIViewController) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("viewer-test.txt")
    try Data("Synthetic viewer test".utf8).write(to: file)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    let host = UIViewController()
    window.frame = scene.coordinateSpace.bounds
    window.rootViewController = host
    window.isHidden = false
    host.loadViewIfNeeded()
    defer { window.isHidden = true }
    try body(file, host)
  }

  @MainActor
  func testUnsupportedFileCompletesWhenBothPresentationOptionsDecline() throws {
    try withFile { file, host in
      for previewable in [false, true] {
        let document = TestFileDocument(file)
        let viewer = IosFileViewer(makeDocument: { _ in document }, canPreview: { _ in previewable },
                                   presentingController: { host })
        var results: [String] = []
        viewer.open(path: file.path) { results.append($0 as! String) }
        XCTAssertEqual(results, ["unsupported"])
        XCTAssertEqual(document.previews, previewable ? 1 : 0)
        XCTAssertEqual(document.menus, 1)
        XCTAssertNil(document.delegate)
        // Declining a presentation must not leave the next request busy.
        viewer.open(path: file.path) { results.append($0 as! String) }
        XCTAssertEqual(results, ["unsupported", "unsupported"])
      }
    }
  }

  @MainActor
  func testPreviewHoldsRequestUntilDismissalAndCompletesOnlyOnce() throws {
    try withFile { file, host in
      let document = TestFileDocument(file)
      document.previewSucceeds = true
      let viewer = IosFileViewer(makeDocument: { _ in document }, canPreview: { _ in true },
                                 presentingController: { host })
      var results: [String] = []
      viewer.open(path: file.path) { results.append($0 as! String) }
      XCTAssertTrue(results.isEmpty)
      XCTAssertTrue(document.delegate === viewer)
      XCTAssertEqual(document.menus, 0)
      viewer.documentInteractionControllerDidEndPreview(document.interactionController)
      viewer.documentInteractionControllerDidEndPreview(document.interactionController)
      XCTAssertEqual(results, ["opened"])
      XCTAssertNil(document.delegate)
    }
  }

  @MainActor
  func testOpenInWaitsForDismissalAndBusyRequestCannotReplaceIt() throws {
    try withFile { file, host in
      let document = TestFileDocument(file)
      document.menuSucceeds = true
      let viewer = IosFileViewer(makeDocument: { _ in document }, canPreview: { _ in false },
                                 presentingController: { host })
      var results: [String] = []
      viewer.open(path: file.path) { results.append($0 as! String) }
      viewer.open(path: file.path) { results.append($0 as! String) }
      XCTAssertEqual(results, ["cancelled"])
      XCTAssertTrue(document.delegate === viewer)
      viewer.documentInteractionControllerDidDismissOpenInMenu(document.interactionController)
      XCTAssertEqual(results, ["cancelled", "opened"])
    }
  }

  @MainActor
  func testCancelReleasesPresentationAndLateCallbackCannotFinishNextRequest() throws {
    try withFile { file, host in
      let first = TestFileDocument(file)
      let second = TestFileDocument(file)
      first.previewSucceeds = true
      second.previewSucceeds = true
      var documents = [first, second]
      let viewer = IosFileViewer(makeDocument: { _ in documents.removeFirst() }, canPreview: { _ in true },
                                 presentingController: { host })
      var results: [String] = []
      viewer.open(path: file.path) { results.append($0 as! String) }
      viewer.cancel()
      viewer.cancel()
      XCTAssertEqual(results, ["cancelled"])
      XCTAssertEqual(first.closes, 1)
      XCTAssertNil(first.delegate)
      viewer.open(path: file.path) { results.append($0 as! String) }
      viewer.documentInteractionControllerDidEndPreview(first.interactionController)
      XCTAssertEqual(results, ["cancelled"])
      XCTAssertTrue(second.delegate === viewer)
      viewer.documentInteractionControllerDidEndPreview(second.interactionController)
      XCTAssertEqual(results, ["cancelled", "opened"])
    }
  }

  @MainActor
  func testApplicationHandoffRetainsRequestUntilBothHandoffAndPresentationEnd() throws {
    try withFile { file, host in
      for preview in [false, true] {
        for handoffFirst in [false, true] {
          let document = TestFileDocument(file)
          document.previewSucceeds = preview
          document.menuSucceeds = !preview
          let viewer = IosFileViewer(makeDocument: { _ in document }, canPreview: { _ in preview },
                                     presentingController: { host })
          var results: [String] = []
          viewer.open(path: file.path) { results.append($0 as! String) }
          document.delegate?.documentInteractionController?(document.interactionController,
              willBeginSendingToApplication: "test.synthetic.viewer")
          func endPresentation() {
            if preview {
              viewer.documentInteractionControllerDidEndPreview(document.interactionController)
            } else {
              viewer.documentInteractionControllerDidDismissOpenInMenu(document.interactionController)
            }
          }
          func endHandoff() {
            document.delegate?.documentInteractionController?(document.interactionController,
                didEndSendingToApplication: "test.synthetic.viewer")
          }
          if handoffFirst { endHandoff() } else { endPresentation() }
          XCTAssertTrue(results.isEmpty, "The source bookmark must outlive both presentation and handoff")
          XCTAssertTrue(document.delegate === viewer)
          if handoffFirst { endPresentation() } else { endHandoff() }
          XCTAssertEqual(results, ["opened"])
          XCTAssertNil(document.delegate)
        }
      }
    }
  }

  @MainActor
  func testCancellationDuringHandoffClosesUIButRetainsSourceUntilHandoffEnds() throws {
    try withFile { file, host in
      let document = TestFileDocument(file)
      document.menuSucceeds = true
      let viewer = IosFileViewer(makeDocument: { _ in document }, canPreview: { _ in false },
                                 presentingController: { host })
      var results: [String] = []
      viewer.open(path: file.path) { results.append($0 as! String) }
      document.delegate?.documentInteractionController?(document.interactionController,
          willBeginSendingToApplication: "test.synthetic.viewer")
      viewer.cancel()
      viewer.cancel()
      XCTAssertEqual(document.closes, 1)
      XCTAssertTrue(results.isEmpty, "An in-flight handoff still owns the source")
      XCTAssertTrue(document.delegate === viewer)
      viewer.documentInteractionControllerDidDismissOpenInMenu(document.interactionController)
      XCTAssertTrue(results.isEmpty)
      document.delegate?.documentInteractionController?(document.interactionController,
          didEndSendingToApplication: "test.synthetic.viewer")
      XCTAssertEqual(results, ["cancelled"])
      XCTAssertNil(document.delegate)
    }
  }

  @MainActor
  func testUnknownTypeDoesNotOfferEmptyNativeViewer() throws {
    try withFile { file, host in
      let unknown = file.deletingPathExtension().appendingPathExtension("fifeunsupported")
      try Data((0..<4096).map { UInt8(($0 * 173 + $0 / 7) % 256) }).write(to: unknown)
      let document = TestFileDocument(unknown)
      document.previewSucceeds = true
      document.menuSucceeds = true
      let viewer = IosFileViewer(makeDocument: { _ in document }, presentingController: { host })
      defer { viewer.cancel() }
      var results: [String] = []
      viewer.open(path: unknown.path) { results.append($0 as! String) }
      XCTAssertEqual(document.previews, 0, "An unknown binary must not open an empty native viewer")
      XCTAssertEqual(document.menus, 0, "A generic Open In screen is not a viewer for an unknown format")
      XCTAssertEqual(results, ["unsupported"])
    }
  }

  @MainActor
  func testDefaultEligibilityStillAllowsSupportedTextPreview() throws {
    try withFile { file, host in
      let document = TestFileDocument(file)
      document.previewSucceeds = true
      let viewer = IosFileViewer(makeDocument: { _ in document }, presentingController: { host })
      defer { viewer.cancel() }
      viewer.open(path: file.path) { _ in }
      XCTAssertEqual(document.previews, 1)
      XCTAssertEqual(document.menus, 0)
    }
  }

  @MainActor
  func testMissingDirectoryAndUnavailablePresenterDoNotStartPresentation() throws {
    try withFile { file, host in
      var creations = 0
      let viewer = IosFileViewer(makeDocument: { url in
        creations += 1
        return TestFileDocument(url)
      }, presentingController: { host })
      var results: [String] = []
      viewer.open(path: file.appendingPathExtension("missing").path) { results.append($0 as! String) }
      viewer.open(path: file.deletingLastPathComponent().path) { results.append($0 as! String) }
      let noHost = IosFileViewer(presentingController: { nil })
      noHost.open(path: file.path) { results.append($0 as! String) }
      XCTAssertEqual(results, ["missing", "denied", "failed"])
      XCTAssertEqual(creations, 0)
    }
  }
}

private final class TestFileDocument: FileDocumentPresenting {
  let interactionController: UIDocumentInteractionController
  var delegate: UIDocumentInteractionControllerDelegate? {
    get { interactionController.delegate }
    set { interactionController.delegate = newValue }
  }
  var previewSucceeds = false
  var menuSucceeds = false
  var previews = 0
  var menus = 0
  var closes = 0
  init(_ url: URL) { interactionController = UIDocumentInteractionController(url: url) }
  func showPreview() -> Bool { previews += 1; return previewSucceeds }
  func showOpenIn(from rect: CGRect, in view: UIView) -> Bool { menus += 1; return menuSucceeds }
  func closePresentation() { closes += 1 }
}

@MainActor
final class RecoveryPhraseExportTests: XCTestCase {
  private let words = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"

  private func call(_ exporter: IosRecoveryPhraseExport, _ method: String,
                    _ arguments: Any? = nil) -> Any? {
    var response: Any?
    exporter.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { response = $0 }
    return response
  }

  private func withExporter(_ body: (IosRecoveryPhraseExport, RecoveryTestPresenter, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let host = RecoveryTestPresenter()
    let exporter = IosRecoveryPhraseExport(root: directory.appendingPathComponent("owned"),
        canExport: { true }, presentingController: { host })
    try body(exporter, host, directory)
  }

  func testRejectedOrRetiredReservationCannotCreatePlaintext() throws {
    try withExporter { exporter, _, directory in
      let token = try XCTUnwrap(call(exporter, "reserve") as? String)
      _ = call(exporter, "clear")
      let reply = call(exporter, "save", ["text": words, "reservation": token])
      XCTAssertTrue(reply is FlutterError)
      XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned").path))
    }
  }

  func testCancelRemovesOnlyOwnedProtectedStaging() throws {
    try withExporter { exporter, host, directory in
      let original = directory.appendingPathComponent("external-original.txt")
      try Data("keep external original".utf8).write(to: original)
      let token = try XCTUnwrap(call(exporter, "reserve") as? String)
      var replies: [Any?] = []
      exporter.handle(FlutterMethodCall(methodName: "save", arguments: ["text": words, "reservation": token])) { replies.append($0) }
      let owned = directory.appendingPathComponent("owned")
      let files = FileManager.default.enumerator(at: owned, includingPropertiesForKeys: nil)!.allObjects as! [URL]
      let file = try XCTUnwrap(files.first { $0.lastPathComponent == "fife_recovery_phrase.txt" })
      XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), words)
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
      exporter.documentPickerWasCancelled(try XCTUnwrap(host.dialog))
      XCTAssertEqual(replies.count, 1)
      XCTAssertEqual(replies[0] as? Bool, false)
      XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
      XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "keep external original")
      XCTAssertTrue(call(exporter, "save", ["text": words, "reservation": token]) is FlutterError)
    }
  }

  func testSuccessfulSaveKeepsTheExternalCopyAndRemovesPrivateStaging() throws {
    try withExporter { exporter, host, directory in
      let token = try XCTUnwrap(call(exporter, "reserve") as? String)
      var reply: Any?
      exporter.handle(FlutterMethodCall(methodName: "save", arguments: ["text": words, "reservation": token])) { reply = $0 }
      let owned = directory.appendingPathComponent("owned")
      let files = FileManager.default.enumerator(at: owned, includingPropertiesForKeys: nil)!.allObjects as! [URL]
      let staged = try XCTUnwrap(files.first { $0.lastPathComponent == "fife_recovery_phrase.txt" })
      let destination = directory.appendingPathComponent("saved-copy.txt")
      // Component substitute for the OS picker copying to the selected target.
      try FileManager.default.copyItem(at: staged, to: destination)
      exporter.documentPicker(try XCTUnwrap(host.dialog), didPickDocumentsAt: [destination])
      XCTAssertEqual(reply as? Bool, true)
      XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), words)
      XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
  }

  func testSessionCleanupCancelsAnOpenExportAndInvalidatesLateSaves() throws {
    try withExporter { exporter, host, directory in
      let token = try XCTUnwrap(call(exporter, "reserve") as? String)
      var replies: [Any?] = []
      exporter.handle(FlutterMethodCall(methodName: "save", arguments: ["text": words, "reservation": token])) { replies.append($0) }
      XCTAssertNotNil(host.dialog)
      _ = call(exporter, "clear")
      XCTAssertEqual(replies.count, 1)
      XCTAssertEqual(replies[0] as? Bool, false)
      XCTAssertTrue(call(exporter, "save", ["text": words, "reservation": token]) is FlutterError)
      XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned").path))
    }
  }

  func testDisabledPrivacyRefusesReservationWithoutCreatingFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let exporter = IosRecoveryPhraseExport(root: directory, canExport: { false })
    XCTAssertTrue(call(exporter, "reserve") is FlutterError)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }

  func testLateReleaseAndOldDialogCallbacksPreserveTheNewExport() throws {
    try withExporter { exporter, host, directory in
      let oldToken = try XCTUnwrap(call(exporter, "reserve") as? String)
      exporter.handle(FlutterMethodCall(methodName: "save", arguments: ["text": words, "reservation": oldToken])) { _ in }
      let oldDialog = try XCTUnwrap(host.dialog)
      exporter.documentPickerWasCancelled(oldDialog)
      let newToken = try XCTUnwrap(call(exporter, "reserve") as? String)
      var newReply: Any?
      exporter.handle(FlutterMethodCall(methodName: "save", arguments: ["text": words, "reservation": newToken])) { newReply = $0 }
      let newDialog = try XCTUnwrap(host.dialog)
      _ = call(exporter, "release", oldToken)
      exporter.documentPickerWasCancelled(oldDialog)
      XCTAssertNil(newReply)
      XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned").path))
      exporter.documentPickerWasCancelled(newDialog)
      XCTAssertEqual(newReply as? Bool, false)
      XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("owned").path))
    }
  }
}

@MainActor
private final class RecoveryTestPresenter: UIViewController {
  var dialog: UIDocumentPickerViewController?
  override func present(_ viewController: UIViewController, animated: Bool,
                        completion: (() -> Void)? = nil) {
    dialog = viewController as? UIDocumentPickerViewController
    // No native UI in component tests; the test explicitly supplies completion.
  }
}
