import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../utils/codec.dart';

// ============================================================
// HTTP CLIENT — Real device User-Agent injection
// ============================================================
// PURPOSE: Make all outgoing HTTP requests look like they come
// from a real mobile browser (Chrome on Android / Safari on iOS).
//
// WHY: Backend and attribution networks fingerprint requests by
// User-Agent. A generic Dart/Flutter UA would be anomalous and
// could cause attribution failures or server-side blocking.
//
// HOW:
//   - Reads actual device model, brand, SDK version via DeviceInfoPlugin
//   - Builds a UA string matching Chrome (Android) or Safari (iOS) format
//   - Injected as a default header on every HTTP request
//   - Also set on the WebViewController (see content_screen.dart)
//
// The Chrome/WebKit version fragments are XOR-encoded in the binary
// so they don't appear as obvious version strings in static analysis.
// TODO: Re-encode these after changing the codec seed.
// ============================================================

// XOR-encoded Chrome version fragment (e.g. "130.0.0.0")
// TODO: Re-encode after changing codec seed in codec.dart
String get _fallbackCv => d(const <int>[
      // TODO: encode your Chrome version string
    ]);

// XOR-encoded WebKit version fragment (e.g. "537.36")
// TODO: Re-encode after changing codec seed in codec.dart
String get _sv => d(const <int>[
      // TODO: encode your WebKit version string
    ]);

class AppHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _userAgent;

  /// Call once in main() before runApp().
  /// Reads real device info to build an accurate User-Agent string.
  Future<void> init() async {
    // TODO: This implementation is complete — do not change the logic.
    // Only update _fallbackCv and _sv byte arrays after re-encoding.
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final sdk = a.version.sdkInt;
        final model = a.model;
        final brand = a.brand;
        final build = a.display.isNotEmpty ? a.display : a.id;

        final cv = _fallbackCv.isNotEmpty ? _fallbackCv : '130.0.0.0';
        _userAgent = 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
            'Build/$build) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/$cv Mobile Safari/537.36';
      } else {
        final i = await info.iosInfo;
        final ver = i.systemVersion.replaceAll('.', '_');
        final sv = _sv.isNotEmpty ? _sv : '537.36';
        _userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$sv (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$sv';
      }
    } catch (_) {
      final cv = _fallbackCv.isNotEmpty ? _fallbackCv : '130.0.0.0';
      final sv = _sv.isNotEmpty ? _sv : '537.36';
      _userAgent = Platform.isAndroid
          ? 'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/$cv Mobile Safari/537.36'
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/$sv (KHTML, like Gecko) '
              'Version/17.0 Mobile/15E148 Safari/$sv';
    }
  }

  String get userAgent => _userAgent ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Global singleton HTTP client.
/// Used by all services: RemoteService, AppsFlyerService (GCD), PushNotificationService.
final appHttpClient = AppHttpClient();
