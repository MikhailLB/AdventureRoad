import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads cold-start push URLs written by SceneDelegate before any Dart code
/// was alive.
///
/// When a user taps a push notification while the app is killed, iOS launches
/// the app and delivers the tap through SceneDelegate.scene(_:willConnectTo:),
/// NOT through Firebase Messaging's swizzled path. SceneDelegate writes the
/// destination URL into UserDefaults under [_prefKey]; this class reads and
/// removes it once so the navigation happens exactly once per cold-start tap.
class ColdStartBridge {
  /// Must match SceneDelegate.launchUrlKey minus the "flutter." prefix that
  /// SharedPreferences adds automatically on iOS.
  static const String _prefKey = 'ar_road_cold_start_url';

  /// Returns and clears the URL stored by SceneDelegate on cold-start tap.
  /// Returns null on non-iOS platforms or when there is no stored URL.
  static Future<String?> consumeLaunchUrl() async {
    if (!Platform.isIOS) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.trim().isEmpty) {
        debugPrint('[AR.BRIDGE] consumeLaunchUrl -> null');
        return null;
      }
      await prefs.remove(_prefKey);
      debugPrint('[AR.BRIDGE] consumeLaunchUrl -> $raw');
      return raw.trim();
    } catch (err) {
      debugPrint('[AR.BRIDGE] consumeLaunchUrl failed: $err');
      return null;
    }
  }
}
