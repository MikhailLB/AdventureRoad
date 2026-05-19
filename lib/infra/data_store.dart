import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_state.dart';

class DataStore {
  static const _keyAppMode = 'app_mode';
  static const _keySavedUrl = 'sv_u';
  static const _keyUrlExpires = 'url_expires';
  static const _keyNotificationSkipUntil = 'notification_skip_until';
  static const _keyNotificationGranted = 'notification_granted';
  static const _keyNotificationSystemDenied = 'notification_system_denied';
  static const _keyPushUrl = 'psh_u';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  AppState getAppMode() {
    return AppState.fromString(_prefs.getString(_keyAppMode));
  }

  Future<void> setAppMode(AppState mode) async {
    await _prefs.setString(_keyAppMode, mode.toStorageString());
  }

  Future<String?> getSavedUrl() async {
    return _secure.read(key: _keySavedUrl);
  }

  Future<void> setSavedUrl(String url) async {
    await _secure.write(key: _keySavedUrl, value: url);
  }

  int? getUrlExpires() => _prefs.getInt(_keyUrlExpires);

  Future<void> setUrlExpires(int expires) async {
    await _prefs.setInt(_keyUrlExpires, expires);
  }

  bool isUrlExpired() {
    final expires = getUrlExpires();
    if (expires == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= expires;
  }

  bool isNotificationGranted() =>
      _prefs.getBool(_keyNotificationGranted) ?? false;

  Future<void> setNotificationGranted(bool granted) async {
    await _prefs.setBool(_keyNotificationGranted, granted);
  }

  bool isNotificationSystemDenied() =>
      _prefs.getBool(_keyNotificationSystemDenied) ?? false;

  Future<void> setNotificationSystemDenied(bool denied) async {
    await _prefs.setBool(_keyNotificationSystemDenied, denied);
  }

  int? getNotificationSkipUntil() => _prefs.getInt(_keyNotificationSkipUntil);

  Future<void> setNotificationSkipUntil(int timestamp) async {
    await _prefs.setInt(_keyNotificationSkipUntil, timestamp);
  }

  bool shouldShowNotificationScreen() {
    if (isNotificationSystemDenied()) return false;
    if (isNotificationGranted()) return false;
    final skipUntil = getNotificationSkipUntil();
    if (skipUntil == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= skipUntil;
  }

  Future<String?> getPushUrl() async {
    return _secure.read(key: _keyPushUrl);
  }

  Future<void> setPushUrl(String? url) async {
    if (url == null) {
      await _secure.delete(key: _keyPushUrl);
    } else {
      await _secure.write(key: _keyPushUrl, value: url);
    }
  }

  Future<String?> consumePushUrl() async {
    final url = await getPushUrl();
    if (url != null) {
      await _secure.delete(key: _keyPushUrl);
    }
    return url;
  }
}
