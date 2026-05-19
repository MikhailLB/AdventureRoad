import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../helpers/cipher.dart';

String get _fallbackCv => xd(const [39, 164, 178, 67, 146, 29, 199, 88, 222, 188, 50, 19, 202]);
String get _sv => xd(const [32, 167, 177, 67, 147, 29, 193, 92]);

class HttpAgent extends http.BaseClient {
  final http.Client _inner = http.Client();
  String? _userAgent;

  Future<void> init() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final sdk = a.version.sdkInt;
        final model = a.model;
        final brand = a.brand;
        final build = a.display.isNotEmpty ? a.display : a.id;
        _userAgent = 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
            'Build/$build) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/$_fallbackCv Mobile Safari/537.36';
      } else {
        final i = await info.iosInfo;
        final ver = i.systemVersion.replaceAll('.', '_');
        _userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$_sv (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$_sv';
      }
    } catch (_) {
      _userAgent = Platform.isAndroid
          ? 'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/$_fallbackCv Mobile Safari/537.36'
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/$_sv (KHTML, like Gecko) '
              'Version/17.0 Mobile/15E148 Safari/$_sv';
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

final httpAgent = HttpAgent();
