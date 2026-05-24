import 'dart:io';
import 'net_info.dart';
import 'analytics_info.dart';
import 'game_endpoints.dart';

class AppSettings {
  static String get apiEndpoint => resolveEndpoint();
  static String get analyticsKey => resolveAnalyticsKey();
  static String get messagingProjectId => resolveMessagingProject();
  static String get privacyPolicyUrl => privacyPolicyPageUrl;
  static String get supportUrl => supportPageUrl;

  static const String iosAppStoreId = '6771792818';

  static String get analyticsAppId =>
      Platform.isIOS ? iosAppStoreId : bundleId;

  static const String bundleId = 'com.feather.run.app';
  static String get storeId =>
      Platform.isIOS ? 'id$iosAppStoreId' : bundleId;
  static const String appName = 'Feather Run';

  static const int notificationRetryDelaySeconds = 259200;
  static const int syncRetrySeconds = 5;
}
