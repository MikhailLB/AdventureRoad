import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import '../config/app_settings.dart';
import '../config/analytics_info.dart';
import 'http_client.dart';

// ============================================================
// APPSFLYER SERVICE — Attribution + deep link handling
// ============================================================
// PURPOSE: Initialize AppsFlyer SDK, collect install attribution
// and deep link data, then build the POST body for the config
// endpoint. The backend uses this data to decide whether the
// user should see the WebView or the game.
//
// FLOW:
//   1. init() — register all SDK callbacks, then call initSdk()
//   2. waitForAttribution() — waits up to 30s for onInstallConversionData
//      ⚠️ If af_status == "Organic", retry with GCD after 5s
//         (AppsFlyer sometimes returns false-organic on first callback)
//   3. waitForDeepLink() — waits up to 5s for onDeepLinking callback
//   4. buildRequestBody() — merges attribution + deepLink + device info
//      into the POST body dict. Deep link fields use putIfAbsent so
//      they don't overwrite attribution fields with the same key.
//
// ORGANIC FALSE-POSITIVE (CRITICAL):
//   AppsFlyer sometimes fires onInstallConversionData with
//   af_status="Organic" even for paid installs. This is a known SDK bug.
//   Fix: if af_status == "Organic", wait syncRetrySeconds (5s), then
//   call GCD API directly to get the real conversion data.
//   GCD endpoint: https://dev.appsflyer.com/hc/reference/gcd-get-data
//   Auth: Bearer {analyticsKey}
//   Use the LAST successfully received data for all further decisions.
//
// IMPORTANT (per TZ):
//   - Do NOT modify the attribution data fields — send them as-is
//   - The number of fields per install varies by source — that is normal
//   - af_id = AppsFlyerUID (getAppsFlyerUID())
//   - bundle_id = AppSettings.bundleId
//   - os = "Android" or "iOS"
//   - store_id = AppSettings.storeId
//   - locale = Platform.localeName (RFC 3066 format, e.g. "en_US")
//   - push_token = FCM token (from PushNotificationService)
//   - firebase_project_id = AppSettings.messagingProjectId
// ============================================================

class AppsFlyerService {
  AppsflyerSdk? _sdk;

  // Attribution data from onInstallConversionData callback
  Map<String, dynamic>? _attributionData;

  // Deep link data from onDeepLinking callback (UDL)
  Map<String, dynamic>? _deepLinkData;

  // App-open attribution data from onAppOpenAttribution
  Map<String, dynamic>? _appOpenAttributionData;

  // Completes when attribution data is first received
  final Completer<Map<String, dynamic>> _attributionCompleter = Completer();

  // Completes when deep link result arrives (or times out)
  final Completer<void> _deepLinkCompleter = Completer();

  bool _initialized = false;

  /// Initialize AppsFlyer SDK and register all callbacks.
  ///
  /// TODO: Implement this method.
  ///
  /// IMPLEMENTATION STEPS:
  ///   1. Guard: if (_initialized) return; _initialized = true;
  ///
  ///   2. Build AppsFlyerOptions:
  ///      - afDevKey: AppSettings.analyticsKey
  ///      - appId: AppSettings.analyticsAppId (empty for Android)
  ///      - showDebug: kDebugMode only
  ///      - timeToWaitForATTUserAuthorization: 10 (iOS ATT timeout)
  ///
  ///   3. Register onInstallConversionData callback:
  ///      - Extract payload from data['payload'] or data itself
  ///      - If payload['af_status'] == 'Organic':
  ///          await Future.delayed(Duration(seconds: AppSettings.syncRetrySeconds))
  ///          final retryData = await _refreshAttribution()
  ///          _attributionData = retryData ?? payload
  ///      - Else: _attributionData = payload
  ///      - Complete _attributionCompleter if not already completed
  ///
  ///   4. Register onAppOpenAttribution callback:
  ///      - Extract payload, store in _appOpenAttributionData
  ///
  ///   5. Register onDeepLinking callback:
  ///      - If result.deepLink != null, store result.deepLink!.clickEvent in _deepLinkData
  ///      - Complete _deepLinkCompleter if not already completed
  ///
  ///   6. Call _sdk!.initSdk(
  ///        registerConversionDataCallback: true,
  ///        registerOnAppOpenAttributionCallback: true,
  ///        registerOnDeepLinkingCallback: true,
  ///      )
  Future<void> init() async {
    // TODO: implement
    if (_initialized) return;
    _initialized = true;
  }

  /// Calls the GCD (Get Conversion Data) API to get fresh attribution.
  /// Used when onInstallConversionData first returns af_status="Organic".
  ///
  /// TODO: Implement this method.
  ///
  /// IMPLEMENTATION:
  ///   1. Get UID: final uid = await getAnalyticsUID()
  ///   2. Build URL via resolveGcdEndpoint(appId, uid)
  ///      appId = Platform.isIOS ? AppSettings.analyticsAppId : AppSettings.bundleId
  ///   3. GET request with header 'authorization': 'Bearer ${AppSettings.analyticsKey}'
  ///      timeout: 10 seconds
  ///   4. If status 200: return jsonDecode(response.body) as Map<String, dynamic>
  ///   5. Any exception or non-200: return null
  Future<Map<String, dynamic>?> _refreshAttribution() async {
    // TODO: implement GCD retry
    return null;
  }

  /// Waits for the attribution callback, with 30s timeout.
  /// Returns empty map on timeout (app proceeds without attribution).
  Future<Map<String, dynamic>> waitForAttribution() async {
    return _attributionCompleter.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => <String, dynamic>{},
    );
  }

  /// Gets the AppsFlyer UID (unique install identifier).
  /// Returns null if SDK not initialized or getAppsFlyerUID() throws.
  Future<String?> getAnalyticsUID() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Waits for the deep link callback, with 5s timeout.
  Future<void> waitForDeepLink() async {
    await _deepLinkCompleter.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// Builds the full POST body for the config endpoint.
  ///
  /// TODO: Implement this method.
  ///
  /// IMPLEMENTATION (per TZ — order matters):
  ///   1. Start with empty Map<String, dynamic> body
  ///   2. Add ALL attribution data fields as-is: body.addAll(_attributionData ?? {})
  ///   3. Merge deep link data (putIfAbsent — don't overwrite attribution):
  ///      _deepLinkData?.forEach((k, v) => body.putIfAbsent(k, () => v))
  ///   4. Merge app-open attribution data (putIfAbsent):
  ///      _appOpenAttributionData?.forEach((k, v) => body.putIfAbsent(k, () => v))
  ///   5. Add device-side fields (ALWAYS add these, overwrite if duplicate):
  ///      body['af_id']    = await getAnalyticsUID() ?? ''
  ///      body['bundle_id'] = AppSettings.bundleId
  ///      body['os']       = Platform.isAndroid ? 'Android' : 'iOS'
  ///      body['store_id'] = AppSettings.storeId
  ///      body['locale']   = locale (passed as parameter)
  ///   6. If pushToken != null && not empty:
  ///      body['push_token'] = pushToken
  ///   7. If AppSettings.messagingProjectId not empty:
  ///      body['firebase_project_id'] = AppSettings.messagingProjectId
  ///   8. Debug: debugPrint the full body (only in kDebugMode)
  ///   9. Return body
  ///
  /// ⚠️ NEVER modify or filter the attribution fields from AppsFlyer.
  ///    Send them all as received — the backend depends on the full set.
  Future<Map<String, dynamic>> buildRequestBody({
    required String locale,
    String? pushToken,
  }) async {
    // TODO: implement body builder
    final body = <String, dynamic>{};

    final uid = await getAnalyticsUID();
    body['af_id'] = uid ?? '';
    body['bundle_id'] = AppSettings.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = AppSettings.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (AppSettings.messagingProjectId.isNotEmpty) {
      body['firebase_project_id'] = AppSettings.messagingProjectId;
    }

    if (kDebugMode) {
      debugPrint('[AppsFlyerService] Request body: ${jsonEncode(body)}');
    }

    return body;
  }
}
