import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PixoraOpenFile") {
      PixoraOpenFilePlugin.register(with: registrar)
    }
  }
}

/// Hands `.pixora` files opened from Files, Mail, AirDrop or the share
/// sheet to Dart over the `pixora/open_file` channel:
///  - `getInitialFiles` (Dart → native): files that arrived before Dart was
///    ready, e.g. the one that launched the app.
///  - `openFile` (native → Dart): files that arrive while running.
final class PixoraOpenFilePlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let channel: FlutterMethodChannel
  private var pending: [[String: Any]] = []
  private var dartReady = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pixora/open_file", binaryMessenger: registrar.messenger())
    let instance = PixoraOpenFilePlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInitialFiles":
      dartReady = true
      result(pending)
      pending.removeAll()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Apps without scenes.
  @objc(application:openURL:options:)
  func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return deliver(url)
  }

  // Cold launch with a file.
  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    var handled = false
    for context in connectionOptions?.urlContexts ?? [] {
      handled = deliver(context.url) || handled
    }
    return handled
  }

  // A file opened while the app is running.
  @objc(scene:openURLContexts:)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts {
      handled = deliver(context.url) || handled
    }
    return handled
  }

  private func deliver(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return false }
    let file: [String: Any] = [
      "name": url.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
    ]
    if dartReady {
      channel.invokeMethod("openFile", arguments: file)
    } else {
      pending.append(file)
    }
    return true
  }
}
