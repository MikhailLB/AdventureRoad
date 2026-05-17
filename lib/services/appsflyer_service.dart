import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import '../config/app_settings.dart';
import '../config/analytics_info.dart';
import 'http_client.dart';

class AppsFlyerService {
  AppsflyerSdk? _sdk;
  Map<String, dynamic>? _attributionData;
  Map<String, dynamic>? _deepLinkData;
  Map<String, dynamic>? _appOpenAttributionData;
  final Completer<Map<String, dynamic>> _attributionCompleter = Completer();
  final Completer<void> _deepLinkCompleter = Completer();
  bool _initialized = false;
  
  String _maskSecret(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

  bool _looksLikeConversionData(Map<String, dynamic> payload) {
    return payload.containsKey('af_status') ||
        payload.containsKey('media_source') ||
        payload.containsKey('campaign') ||
        payload.containsKey('is_first_launch') ||
        payload.containsKey('install_time');
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final options = AppsFlyerOptions(
      afDevKey: AppSettings.analyticsKey,
      appId: AppSettings.analyticsAppId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    if (kDebugMode) {
      debugPrint('[AppsFlyer] init start');
      debugPrint('[AppsFlyer] config: '
          'devKey=${_maskSecret(AppSettings.analyticsKey)}, '
          'appId=${AppSettings.analyticsAppId}, '
          'bundleId=${AppSettings.bundleId}, '
          'storeId=${AppSettings.storeId}, '
          'platform=${Platform.isAndroid ? 'Android' : 'iOS'}');
    }

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final rawData = Map<String, dynamic>.from(data);
      final payload = rawData['payload'] != null
          ? Map<String, dynamic>.from(rawData['payload'] as Map)
          : rawData;

      if (kDebugMode) {
        debugPrint('[AppsFlyer] onInstallConversionData: ${jsonEncode(payload)}');
      }

      if (!_looksLikeConversionData(payload)) {
        if (kDebugMode) {
          debugPrint('[AppsFlyer] conversion payload is not valid attribution data, '
              'likely SDK/network failure payload. Skip merge into config body.');
        }
        _attributionData = <String, dynamic>{};
        if (!_attributionCompleter.isCompleted) {
          _attributionCompleter.complete(_attributionData);
        }
        return;
      }

      if (payload['af_status'] == 'Organic') {
        await Future.delayed(
          Duration(seconds: AppSettings.syncRetrySeconds),
        );
        final retryData = await _refreshAttribution();
        if (kDebugMode && retryData != null) {
          debugPrint('[AppsFlyer] GCD retry data: ${jsonEncode(retryData)}');
        }
        _attributionData = retryData ?? payload;
      } else {
        _attributionData = payload;
      }

      if (!_attributionCompleter.isCompleted) {
        _attributionCompleter.complete(_attributionData);
      }
    });

    _sdk!.onAppOpenAttribution((data) {
      final rawData = Map<String, dynamic>.from(data);
      final payload = rawData['payload'] != null
          ? Map<String, dynamic>.from(rawData['payload'] as Map)
          : rawData;

      if (kDebugMode) {
        debugPrint('[AppsFlyer] onAppOpenAttribution: ${jsonEncode(payload)}');
      }

      _appOpenAttributionData = payload;
    });

    _sdk!.onDeepLinking((result) {
      if (kDebugMode) {
        debugPrint('[AppsFlyer] onDeepLinking status=${result.status}, '
            'deepLink=${result.deepLink}, error=${result.error}');
        if (result.deepLink != null) {
          debugPrint('[AppsFlyer] deepLink clickEvent: '
              '${jsonEncode(result.deepLink!.clickEvent)}');
        }
      }
      if (result.deepLink != null) {
        _deepLinkData = result.deepLink!.clickEvent;
      }
      if (!_deepLinkCompleter.isCompleted) {
        _deepLinkCompleter.complete();
      }
    });

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    if (kDebugMode) {
      debugPrint('[AppsFlyer] initSdk completed');
    }
  }

  Future<Map<String, dynamic>?> _refreshAttribution() async {
    try {
      final uid = await getAnalyticsUID();
      if (uid == null) return null;

      final appId = Platform.isIOS
          ? AppSettings.analyticsAppId
          : AppSettings.bundleId;
      final url = Uri.parse(resolveGcdEndpoint(appId, uid));
      if (kDebugMode) {
        debugPrint('[AppsFlyer] GCD request url=$url');
      }
      final response = await appHttpClient.get(url, headers: {
        'authorization': 'Bearer ${AppSettings.analyticsKey}',
      }).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        debugPrint('[AppsFlyer] GCD response status=${response.statusCode}');
        debugPrint('[AppsFlyer] GCD response body=${response.body}');
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppsFlyer] GCD request error: $e');
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> waitForAttribution() async {
    return _attributionCompleter.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<String?> getAnalyticsUID() async {
    if (_sdk == null) return null;
    try {
      final result = await _sdk!.getAppsFlyerUID();
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> waitForDeepLink() async {
    await _deepLinkCompleter.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  Future<Map<String, dynamic>> buildRequestBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    if (_attributionData != null) {
      body.addAll(_attributionData!);
    }

    if (_deepLinkData != null) {
      for (final entry in _deepLinkData!.entries) {
        body.putIfAbsent(entry.key, () => entry.value);
      }
    }

    if (_appOpenAttributionData != null) {
      for (final entry in _appOpenAttributionData!.entries) {
        body.putIfAbsent(entry.key, () => entry.value);
      }
    }

    final uid = await getAnalyticsUID();
    if (uid != null && uid.isNotEmpty) {
      body['af_id'] = uid;
    } else if (!body.containsKey('af_id') ||
        (body['af_id'] as String? ?? '').isEmpty) {
      body['af_id'] = '';
    }
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
      debugPrint('[AppsFlyer] conversion keys=${_attributionData?.keys.toList() ?? []}');
      debugPrint('[AppsFlyer] deepLink keys=${_deepLinkData?.keys.toList() ?? []}');
      debugPrint('[AppsFlyer] appOpen keys=${_appOpenAttributionData?.keys.toList() ?? []}');
      debugPrint('[AppsFlyer] Request body: ${jsonEncode(body)}');
    }

    return body;
  }
}
