import Cocoa
import FlutterMacOS

/// Owns one menu-bar item and the existing Flutter window/engine for its lifetime.
final class MacOSDesktop: NSObject {
  static let shared = MacOSDesktop()
  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var item: NSStatusItem?
  private let openItem = NSMenuItem(title: "Open", action: #selector(openWindow), keyEquivalent: "")
  private let syncItem = NSMenuItem(title: "Sync", action: #selector(sync), keyEquivalent: "")
  private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")

  func register(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    let channel = FlutterMethodChannel(name: "com.jeerovan.fife/desktop", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      guard call.method == "updateMenu", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented); return
      }
      self.openItem.title = args["open"] as? String ?? "Open"
      self.quitItem.title = args["quit"] as? String ?? "Quit"
      let busy = args["busy"] as? Bool == true
      self.syncItem.title = args[busy ? "syncing" : "sync"] as? String ?? "Sync"
      self.syncItem.isEnabled = args["syncEnabled"] as? Bool == true && !busy
      result(nil)
    }
    guard item == nil else { return }
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "lock", accessibilityDescription: "FiFe")
    image?.size = NSSize(width: 18, height: 18)
    image?.isTemplate = true
    status.button?.image = image
    status.button?.toolTip = "FiFe"
    status.button?.setAccessibilityLabel("FiFe")
    let menu = NSMenu()
    menu.autoenablesItems = false
    for entry in [openItem, syncItem, quitItem] { entry.target = self }
    syncItem.isEnabled = false
    menu.addItem(openItem)
    menu.addItem(syncItem)
    menu.addItem(.separator())
    menu.addItem(quitItem)
    status.menu = menu
    item = status
  }

  @objc func openWindow() {
    guard let window = window else { return }
    // Never expose the last rendered private frame while Dart handles resume.
    MacOSAppPrivacy.shared.prepareToShow()
    if window.isMiniaturized { window.deminiaturize(nil) }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    MacOSAppPrivacy.shared.refresh()
  }

  @objc private func sync() {
    guard syncItem.isEnabled else { return }
    syncItem.isEnabled = false
    channel?.invokeMethod("sync", arguments: nil)
  }

  @objc private func quit() { NSApp.terminate(nil) }
}

/// Native cover closes the gap before Flutter paints its lock/safe frame.
/// Sheets and system authentication may change the key window without the app
/// actually leaving the foreground, so key-window status is deliberately unused.
final class MacOSAppPrivacy: NSObject {
  static let shared = MacOSAppPrivacy()
  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var cover: NSView?
  private var enabled = UserDefaults.standard.bool(forKey: "fife.appLock.privacy")
  private var active = false
  private var revision = 0
  private var screenUnavailable = false
  private var readyFrame = false
  private var observers: [NSObjectProtocol] = []
  private var clipboardCount: Int?

  var applicationActive: Bool {
    guard let window = window else { return false }
    return NSApp.isActive && !NSApp.isHidden && window.isVisible &&
      !window.isMiniaturized && !screenUnavailable
  }
  var allowsRecoveryExport: Bool { enabled && applicationActive && readyFrame }
  private var state: [String: Any] { ["active": active, "revision": revision] }

  func register(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    let channel = FlutterMethodChannel(name: "com.jeerovan.fife/app_lock_privacy", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "observeLifecycle": self.refresh(); result(self.state)
      case "setEnabled":
        self.enabled = call.arguments as? Bool == true
        UserDefaults.standard.set(self.enabled, forKey: "fife.appLock.privacy")
        if !self.enabled { self.removeCover() }
        else if !self.applicationActive { self.conceal() }
        result(nil)
      case "frameReady":
        if self.applicationActive {
          self.readyFrame = (call.arguments as? [String: Any])?["allowNativeDocuments"] as? Bool == true
          self.removeCover()
        }
        result(nil)
      case "copyRecoveryPhrase":
        guard self.allowsRecoveryExport, let text = call.arguments as? String,
              text.split(separator: " ").count == 24 else {
          result(FlutterError(code: "RECOVERY_COPY_UNAVAILABLE", message: "Protected copy unavailable", details: nil)); return
        }
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        board.setString(text, forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let count = board.changeCount
        self.clipboardCount = count
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
          self?.clearClipboard(expected: count)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    guard observers.isEmpty else { refresh(); return }
    let center = NotificationCenter.default
    for name in [NSApplication.didBecomeActiveNotification, NSApplication.didUnhideNotification,
                 NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
    }
    for name in [NSApplication.willResignActiveNotification, NSApplication.didHideNotification,
                 NSWindow.willMiniaturizeNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
        if event.name == NSWindow.willMiniaturizeNotification,
           let changed = event.object as? NSWindow, changed !== self?.window { return }
        self?.conceal()
      })
    }
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                 NSWorkspace.willSleepNotification] {
      observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.screenUnavailable = true; self?.conceal()
      })
    }
    for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                 NSWorkspace.didWakeNotification] {
      observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.screenUnavailable = false; self?.refresh()
      })
    }
    observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
      MacOSRecoveryPhraseExport.shared.clear()
      self?.clearClipboard()
    })
    if enabled { addCover() }
    refresh()
  }

  func windowClosing() {
    conceal()
    MacOSRecoveryPhraseExport.shared.clear()
  }

  func prepareToShow() {
    // Opening an already visible, active window must not leave a cover waiting
    // for a resume event that will never occur.
    if enabled && !applicationActive { readyFrame = false; addCover() }
  }

  func refresh() {
    let next = applicationActive
    if !next { conceal(); return }
    updateLifecycle(true)
  }

  private func conceal() {
    readyFrame = false
    if enabled { addCover() }
    updateLifecycle(false)
  }

  private func updateLifecycle(_ next: Bool) {
    guard active != next else { return }
    active = next; revision += 1
    channel?.invokeMethod("lifecycle", arguments: state)
  }

  private func addCover() {
    guard cover == nil, let content = window?.contentView else { return }
    let view = NSView(frame: content.bounds)
    view.autoresizingMask = [.width, .height]
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    content.addSubview(view)
    cover = view
  }

  private func removeCover() { cover?.removeFromSuperview(); cover = nil }

  func clearClipboard(expected: Int? = nil) {
    guard let owned = clipboardCount, expected == nil || expected == owned else { return }
    if NSPasteboard.general.changeCount == owned { NSPasteboard.general.clearContents() }
    clipboardCount = nil
  }
}
