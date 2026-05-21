import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'bootstrap.dart';
import 'infra/data_store.dart';
import 'infra/net_checker.dart';
import 'infra/analytics_tracker.dart';
import 'infra/api_client.dart';
import 'infra/push_manager.dart';
import 'infra/http_agent.dart';

/// ════════════════════════════════════════════════════════════
/// main() — entry point
/// ════════════════════════════════════════════════════════════
///
/// ⚠️  TEMPLATE TODOs (in order):
///
///   1. Add android/app/google-services.json       (Firebase Android)
///   2. Add ios/Runner/GoogleService-Info.plist    (Firebase iOS)
///   3. Fill credentials in lib/cfg/              (see TEMPLATE notes)
///   4. Run:  dart run tool/encode_keys.dart       (encode secrets)
///   5. Update bundle IDs in build.gradle.kts and project.pbxproj
///   6. Replace WhitePartPlaceholder in lib/core/white_part.dart
///
/// ORDER MATTERS:
///   Firebase.initializeApp() → FirebaseAppCheck.activate()
///       → HttpAgent.init() → DataStore.init() → runApp()
///   Never call Firebase.initializeApp() again elsewhere!
/// ════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase (must be first) ─────────────────────────────
  // Requires google-services.json (Android) and
  // GoogleService-Info.plist (iOS) in the correct directories.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.deviceCheck,
    );
  } catch (_) {}

  // ── Screen orientation ───────────────────────────────────
  // Allow all orientations at root so loading video can be
  // landscape or portrait. Individual screens lock as needed.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // ── HTTP agent (builds real device User-Agent) ───────────
  await httpAgent.init();

  // ── Services ─────────────────────────────────────────────
  final store       = DataStore();
  await store.init();

  final netChecker  = NetChecker();
  final tracker     = AnalyticsTracker();
  final apiClient   = ApiClient(store);
  final pushManager = PushManager(store);

  runApp(StreetSurgeApp(
    store: store,
    netChecker: netChecker,
    tracker: tracker,
    apiClient: apiClient,
    pushManager: pushManager,
  ));
}
