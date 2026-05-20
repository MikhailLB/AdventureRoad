import FirebaseMessaging
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register Flutter plugins (including firebase_messaging) eagerly so FCM
    // can install its UNUserNotificationCenterDelegate swizzle before any
    // notification taps are delivered.
    GeneratedPluginRegistrant.register(with: self)

    // FirebaseAppDelegateProxyEnabled=YES in Info.plist handles FirebaseApp
    // configuration and APNs token forwarding automatically — no manual
    // FirebaseApp.configure() call needed.

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
