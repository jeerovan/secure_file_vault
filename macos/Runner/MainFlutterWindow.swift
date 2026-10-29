import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    MacOSStorageChannel.register(with: messenger)
    MacOSAppPrivacy.shared.register(window: self, messenger: messenger)
    MacOSRecoveryPhraseExport.shared.register(window: self, messenger: messenger)
    MacOSDesktop.shared.register(window: self, messenger: messenger)

    super.awakeFromNib()
  }

  override func close() {
    MacOSAppPrivacy.shared.windowClosing()
    orderOut(nil)
    MacOSAppPrivacy.shared.refresh()
  }
}
