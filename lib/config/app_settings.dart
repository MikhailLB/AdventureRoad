import 'net_info.dart';
import 'analytics_info.dart';
import 'game_endpoints.dart';

// ============================================================
// APP SETTINGS — Central config facade
// ============================================================
// Single source of truth for all app-level constants.
// Credentials resolve lazily via encoded functions in
// analytics_info.dart and net_info.dart.
//
// SETUP CHECKLIST (fill these before first build):
//   □ bundleId    — must match android/app/build.gradle.kts applicationId
//   □ storeId     — same as bundleId for Android (Play Store package name)
//   □ appName     — display name shown in notifications and app drawer
//   □ analyticsAppId — leave empty for Android (iOS only, App Store ID)
//   □ net_info.dart → resolveEndpoint() — config endpoint URL
//   □ analytics_info.dart → resolveAnalyticsKey() — AppsFlyer Dev Key
//   □ analytics_info.dart → resolveMessagingProject() — Firebase project #
// ============================================================

class AppSettings {
  // TODO: Update to match your project's bundle ID
  static const String bundleId = 'com.example.yourapp';

  // TODO: Same as bundleId for Android
  static const String storeId = 'com.example.yourapp';

  // TODO: App display name (shown in notifications, app drawer)
  static const String appName = 'Your App Name';

  // iOS only — App Store numeric ID (leave empty for Android projects)
  static const String analyticsAppId = '';

  /// Full config endpoint URL — decoded from net_info.dart
  static String get apiEndpoint => resolveEndpoint();

  /// AppsFlyer Dev Key — decoded from analytics_info.dart
  static String get analyticsKey => resolveAnalyticsKey();

  /// Firebase project number — decoded from analytics_info.dart
  static String get messagingProjectId => resolveMessagingProject();

  /// Privacy policy URL (shown in game menu and WebView info screen)
  static String get privacyPolicyUrl => privacyPolicyPageUrl;

  /// Support/help URL
  static String get supportUrl => supportPageUrl;

  // Push permission retry delay = 3 days (per TZ requirement)
  // If user taps "Skip" on the notification promo screen,
  // the screen is shown again after this many seconds.
  static const int notificationRetryDelaySeconds = 259200; // 3 * 24 * 60 * 60

  // GCD retry delay (seconds) when AppsFlyer returns Organic on first callback.
  // After this delay, a fresh GCD request is made to resolve the true status.
  // See: https://dev.appsflyer.com/hc/reference/gcd-get-data
  static const int syncRetrySeconds = 5;
}
