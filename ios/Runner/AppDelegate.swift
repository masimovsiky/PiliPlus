import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false // Disable shake to undo
    SceneLog.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PipPlugin") {
      PipPlugin.register(with: registrar)
    }
  }
}

/// Diagnostic: record app / scene lifecycle into Documents/lifecycle.log.
///
/// Tapping the Now Playing entry (lock screen or Dynamic Island) is supposed to
/// ask iOS to foreground the playing app. Recording every activation callback
/// tells us whether iOS ever tried, or whether the app came back and failed to
/// show a window. The log is readable through the Files app because
/// `UIFileSharingEnabled` is set in Info.plist.
enum SceneLog {
  private static let queue = DispatchQueue(label: "com.example.piliplus.lifecycle")

  private static var fileURL: URL? {
    FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent("lifecycle.log")
  }

  static func add(_ name: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(name)\n"
    queue.async {
      guard let url = fileURL else { return }
      if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
      } else {
        try? Data(line.utf8).write(to: url)
      }
    }
  }

  static func install() {
    let events: [(Notification.Name, String)] = [
      (UIApplication.didBecomeActiveNotification, "app.didBecomeActive"),
      (UIApplication.willEnterForegroundNotification, "app.willEnterForeground"),
      (UIApplication.didEnterBackgroundNotification, "app.didEnterBackground"),
      (UIApplication.willResignActiveNotification, "app.willResignActive"),
      (UIScene.willConnectNotification, "scene.willConnect"),
      (UIScene.willEnterForegroundNotification, "scene.willEnterForeground"),
      (UIScene.didActivateNotification, "scene.didActivate"),
      (UIScene.willDeactivateNotification, "scene.willDeactivate"),
      (UIScene.didEnterBackgroundNotification, "scene.didEnterBackground"),
      (UIScene.didDisconnectNotification, "scene.didDisconnect"),
    ]
    for (name, label) in events {
      NotificationCenter.default.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { _ in
        add(label)
      }
    }
    add("launch pid=\(ProcessInfo.processInfo.processIdentifier)")
  }
}
