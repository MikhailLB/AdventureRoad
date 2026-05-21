import 'dart:io';
import 'network_cfg.dart';
import 'tracker_data.dart';
import 'remote_paths.dart';

/// ════════════════════════════════════════════════════════════
/// ⚠️  TEMPLATE — fill every TODO before building
/// ════════════════════════════════════════════════════════════
class AppConfig {
  // ── iOS App Store numeric ID (e.g. '6770700971') ──────────
  // TODO: replace with your App Store app ID
  static const String iosAppStoreId = 'TODO_IOS_APP_STORE_ID';

  // ── Android / iOS bundle / package ID ────────────────────
  // Must match applicationId in android/app/build.gradle.kts
  // and PRODUCT_BUNDLE_IDENTIFIER in ios/Runner.xcodeproj
  // TODO: replace with your bundle ID, e.g. 'com.example.myapp'
  static const String bundleId = 'TODO_BUNDLE_ID';

  // ── Display name shown in logs / debug ───────────────────
  // TODO: replace with your app name
  static const String appName = 'TODO_APP_NAME';

  // ── Timing constants ─────────────────────────────────────
  /// Seconds before the notification permission screen is shown again
  /// after the user taps "Skip".  Default = 3 days (259 200 s).
  static const int notificationRetryDelaySeconds = 259200;

  /// Seconds to wait before retrying AppsFlyer attribution GCD call
  /// when the first result is Organic.
  static const int syncRetrySeconds = 5;

  // ── Derived — do not edit ────────────────────────────────
  static String get apiEndpoint       => getBaseUrl();
  static String get analyticsKey      => getTrackerKey();
  static String get messagingProjectId => getProjectRef();
  static String get privacyPolicyUrl  => policyPageUrl;
  static String get supportUrl        => helpPageUrl;
  static String get analyticsAppId    =>
      Platform.isIOS ? iosAppStoreId : bundleId;
  static String get storeId           =>
      Platform.isIOS ? 'id$iosAppStoreId' : bundleId;
}
