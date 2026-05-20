import 'dart:io';
import 'network_cfg.dart';
import 'tracker_data.dart';
import 'remote_paths.dart';

class AppConfig {
  static String get apiEndpoint => getBaseUrl();
  static String get analyticsKey => getTrackerKey();
  static String get messagingProjectId => getProjectRef();
  static String get privacyPolicyUrl => policyPageUrl;
  static String get supportUrl => helpPageUrl;

  static const String iosAppStoreId = '6770700971';

  static String get analyticsAppId =>
      Platform.isIOS ? iosAppStoreId : bundleId;

  static const String bundleId = 'com.adventix.adventureroad';
  static String get storeId =>
      Platform.isIOS ? 'id$iosAppStoreId' : bundleId;
  static const String appName = 'Adventure Road';

  static const int notificationRetryDelaySeconds = 259200;
  static const int syncRetrySeconds = 5;
}
