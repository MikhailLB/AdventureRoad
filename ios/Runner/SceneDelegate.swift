import Flutter
import UIKit
import UserNotifications

/// Scene-based iOS apps (UIApplicationSceneManifest in Info.plist) do NOT
/// receive cold-start notification responses through the traditional
/// application(_:didFinishLaunchingWithOptions:) path that Firebase Messaging
/// swizzle relies on. When the user taps a push while the app is killed, iOS
/// delivers the tap via scene(_:willConnectTo:options:) instead.
///
/// Because Firebase swizzle never sees this response,
/// FirebaseMessaging.instance.getInitialMessage() returns nil for scene-based
/// apps on cold-start tap (firebase/flutterfire#8896).
///
/// Fix: capture the notification URL here, persist it to UserDefaults under a
/// flutter.-prefixed key, and let the Dart ColdStartBridge read it via
/// SharedPreferences on bootstrap without any MethodChannel timing dance.
class SceneDelegate: FlutterSceneDelegate {

  /// UserDefaults key read by lib/infra/cold_start_bridge.dart.
  /// The "flutter." prefix is mandatory — the Flutter shared_preferences
  /// plugin namespaces all keys with "flutter." on iOS.
  static let launchUrlKey = "flutter.fr_cold_start_url"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Cold-start notification tap (process was killed).
    if let response = connectionOptions.notificationResponse,
       let url = SceneDelegate.extractDestinationUrl(
         from: response.notification.request.content.userInfo
       )
    {
      SceneDelegate.storeUrl(url, source: "cold-start")
    }
  }

  /// Scans the push payload for a destination URL using the same key set
  /// that the Dart push_manager uses, so a payload that works in
  /// foreground/background also works on cold start.
  static func extractDestinationUrl(from userInfo: [AnyHashable: Any]) -> String? {
    let candidates = ["url", "link", "target", "deeplink", "deep_link"]

    func scan(_ map: [AnyHashable: Any]) -> String? {
      for key in candidates {
        if let raw = map[key] as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }
      return nil
    }

    if let direct = scan(userInfo) { return direct }
    if let nested = userInfo["payload"] as? [AnyHashable: Any] {
      return scan(nested)
    }
    return nil
  }

  static func storeUrl(_ url: String, source: String) {
    NSLog("[FR.NATIVE] cold-start url (\(source)) -> \(url)")
    let defaults = UserDefaults.standard
    defaults.set(url, forKey: launchUrlKey)
    defaults.synchronize()
  }
}
