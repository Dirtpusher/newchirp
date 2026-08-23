import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var methodChannel: FlutterMethodChannel?
  private var undoAvailable = false
  private var redoAvailable = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "newchirp/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setUndoState":
        if let args = call.arguments as? [String: Any] {
          self?.undoAvailable = args["undo"] as? Bool ?? false
          self?.redoAvailable = args["redo"] as? Bool ?? false
        }
        NSApp.mainMenu?.update()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    // AppKit restores this frame on launch and updates it whenever the user
    // moves or resizes the window.
    self.setFrameAutosaveName("NewChirpMainWindow")

    // A saved position may refer to a display that is no longer connected.
    // Keep the restored window reachable when the monitor layout changes.
    if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(self.frame) }) {
      self.center()
    }
  }

  @objc func undo(_ sender: Any?) {
    methodChannel?.invokeMethod("undo", arguments: nil)
  }

  @objc func redo(_ sender: Any?) {
    methodChannel?.invokeMethod("redo", arguments: nil)
  }

  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(undo(_:)):
      return undoAvailable
    case #selector(redo(_:)):
      return redoAvailable
    default:
      return super.validateMenuItem(menuItem)
    }
  }
}
