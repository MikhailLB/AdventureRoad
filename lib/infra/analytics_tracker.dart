import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import '../cfg/app_config.dart';
import '../cfg/tracker_data.dart';
import 'http_agent.dart';

class AnalyticsTracker {
  AppsflyerSdk? _sdk;
  Map<String, dynamic>? _attributionData;
  Map<String, dynamic>? _deepLinkData;
  Map<String, dynamic>? _appOpenAttributionData;
  final Completer<Map<String, dynamic>> _attributionCompleter = Completer();
  final Completer<void> _deepLinkCompleter = Completer();
  bool _initialized = false;

  Future<void> _requestTrackPermission() async {
    if (!Platform.isIOS) return;
    try {
      // Fast path: status already decided on previous launches — no UI to show.
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      debugPrint('[Tracker] ATT status before prompt=$status');
      if (status != TrackingStatus.notDetermined) return;

      // Wait for the first frame so the app is visually active before showing
      // the system dialog. iOS silently drops the request if the app state is
      // not UIApplicationStateActive.
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 300));
      final after = await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('[Tracker] ATT status after prompt=$after');
    } catch (err) {
      debugPrint('[Tracker] ATT skipped: $err');
    }
  }

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

    if (Platform.isIOS) {
      await _requestTrackPermission();
    }

    final options = AppsFlyerOptions(
      afDevKey: AppConfig.analyticsKey,
      appId: AppConfig.analyticsAppId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 4,
    );

    if (kDebugMode) {
      debugPrint('[Tracker] init start');
      debugPrint('[Tracker] config: '
          'devKey=${_maskSecret(AppConfig.analyticsKey)}, '
          'appId=${AppConfig.analyticsAppId}, '
          'bundleId=${AppConfig.bundleId}, '
          'storeId=${AppConfig.storeId}, '
          'platform=${Platform.isAndroid ? 'Android' : 'iOS'}');
    }

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final rawData = Map<String, dynamic>.from(data);
      final payload = rawData['payload'] != null
          ? Map<String, dynamic>.from(rawData['payload'] as Map)
          : rawData;

      if (kDebugMode) {
        debugPrint('[Tracker] onInstallConversionData: ${jsonEncode(payload)}');
      }

      if (!_looksLikeConversionData(payload)) {
        if (kDebugMode) {
          debugPrint('[Tracker] conversion payload is not valid attribution data, skip.');
        }
        _attributionData = <String, dynamic>{};
        if (!_attributionCompleter.isCompleted) {
          _attributionCompleter.complete(_attributionData);
        }
        return;
      }

      if (payload['af_status'] == 'Organic') {
        await Future.delayed(
          Duration(seconds: AppConfig.syncRetrySeconds),
        );
        final retryData = await _refreshAttribution();
        if (kDebugMode && retryData != null) {
          debugPrint('[Tracker] GCD retry data: ${jsonEncode(retryData)}');
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
        debugPrint('[Tracker] onAppOpenAttribution: ${jsonEncode(payload)}');
      }

      _appOpenAttributionData = payload;
    });

    _sdk!.onDeepLinking((result) {
      if (kDebugMode) {
        debugPrint('[Tracker] onDeepLinking status=${result.status}, '
            'deepLink=${result.deepLink}, error=${result.error}');
        if (result.deepLink != null) {
          debugPrint('[Tracker] deepLink clickEvent: '
              '${jsonEncode(result.deepLink!.clickEvent)}');
          debugPrint('[Tracker] deepLink value: ${result.deepLink!.deepLinkValue}');
          debugPrint('[Tracker] deepLink isDeferred: ${result.deepLink!.isDeferred}');
        }
      }
      if (result.deepLink != null) {
        final clickEvent = Map<String, dynamic>.from(result.deepLink!.clickEvent);
        final dlValue = result.deepLink!.deepLinkValue;
        if (dlValue != null && dlValue.isNotEmpty) {
          clickEvent['deep_link_value'] = dlValue;
        }
        clickEvent['is_deferred'] = result.deepLink!.isDeferred ?? false;
        _deepLinkData = clickEvent;
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
      debugPrint('[Tracker] initSdk completed');
    }
  }

  Future<Map<String, dynamic>?> _refreshAttribution() async {
    try {
      final uid = await getAnalyticsUID();
      if (uid == null) return null;

      final appId = Platform.isIOS
          ? AppConfig.analyticsAppId
          : AppConfig.bundleId;
      final url = Uri.parse(getEventUrl(appId, uid));
      if (kDebugMode) {
        debugPrint('[Tracker] GCD request url=$url');
      }
      final response = await httpAgent.get(url, headers: {
        'authorization': 'Bearer ${AppConfig.analyticsKey}',
      }).timeout(const Duration(seconds: 10));

      if (kDebugMode) {
        debugPrint('[Tracker] GCD response status=${response.statusCode}');
        debugPrint('[Tracker] GCD response body=${response.body}');
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Tracker] GCD request error: $e');
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
        .timeout(const Duration(seconds: 12), onTimeout: () {});
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

    if (Platform.isIOS) {
      try {
        // Only read IDFA when the user explicitly authorized tracking via ATT.
        // Apple privacy review flags unconditional calls as a policy violation
        // even though iOS returns zeros when denied.
        final attStatus = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (attStatus == TrackingStatus.authorized) {
          final idfa = await AppTrackingTransparency.getAdvertisingIdentifier();
          if (idfa.isNotEmpty && !idfa.startsWith('00000000-')) {
            body.putIfAbsent('sub_id_10', () => idfa);
          }
        }
      } catch (_) {}
    }

    body['bundle_id'] = AppConfig.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = AppConfig.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }

    if (AppConfig.messagingProjectId.isNotEmpty) {
      body['firebase_project_id'] = AppConfig.messagingProjectId;
    }

    if (kDebugMode) {
      debugPrint('[Tracker] conversion keys=${_attributionData?.keys.toList() ?? []}');
      debugPrint('[Tracker] deepLink keys=${_deepLinkData?.keys.toList() ?? []}');
      debugPrint('[Tracker] appOpen keys=${_appOpenAttributionData?.keys.toList() ?? []}');
      debugPrint('[Tracker] Request body: ${jsonEncode(body)}');
    }

    return body;
  }
}
