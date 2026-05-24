import 'dart:io';
import 'network_cfg.dart';
import 'tracker_data.dart';
import 'remote_paths.dart';

class AppConfig {
  static String get apiEndpoint        => getBaseUrl();
  static String get analyticsKey       => getTrackerKey();
  static String get messagingProjectId => getProjectRef();
  static String get privacyPolicyUrl   => policyPageUrl;
  static String get supportUrl         => helpPageUrl;

  static const String iosAppStoreId = '6771792818';

  static String get analyticsAppId =>
      Platform.isIOS ? iosAppStoreId : bundleId;

  static const String bundleId = 'com.feather.run.app';
  static String get storeId =>
      Platform.isIOS ? 'id$iosAppStoreId' : bundleId;
  static const String appName = 'Feather Run';

  static const int notificationRetryDelaySeconds = 259200; // 3 days
  static const int syncRetrySeconds = 5;
}
