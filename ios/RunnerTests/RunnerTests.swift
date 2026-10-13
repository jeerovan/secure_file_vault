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
