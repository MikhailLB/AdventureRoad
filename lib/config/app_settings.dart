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

  // iOS App Store numeric ID (без префикса `id`). Замени на реальный из App Store Connect.
  // Пока приложение не опубликовано/не зарегистрировано — оставляй placeholder,
  // probabilistic attribution продолжит работать.
  static const String iosAppStoreId = '6762850008';

  static String get analyticsAppId =>
      Platform.isIOS ? iosAppStoreId : bundleId;

  static const String bundleId = 'com.chicktripgsgame.chickentrip2';
  static String get storeId =>
      Platform.isIOS ? 'id$iosAppStoreId' : bundleId;
  static const String appName = 'Chicken Trip 2';

  static const int notificationRetryDelaySeconds = 259200;
  static const int syncRetrySeconds = 5;
}
