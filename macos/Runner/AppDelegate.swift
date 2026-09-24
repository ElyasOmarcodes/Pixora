import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder "Open" / double-click on a `.pixora` file.
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      OpenFileBridge.shared.deliver(url)
    }
  }
}

/// Hands `.pixora` files opened from Finder to Dart over the
/// `pixora/open_file` channel (`getInitialFiles` / `openFile`).
final class OpenFileBridge {
  static let shared = OpenFileBridge()

  private var channel: FlutterMethodChannel?
  private var pending: [[String: Any]] = []
  private var dartReady = false

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pixora/open_file", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getInitialFiles" {
        self.dartReady = true
        result(self.pending)
        self.pending.removeAll()
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func deliver(_ url: URL) {
    guard url.isFileURL else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return }
    let file: [String: Any] = [
      "name": url.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
    ]
    if dartReady, let channel = channel {
      channel.invokeMethod("openFile", arguments: file)
    } else {
      pending.append(file)
    }
  }
}
