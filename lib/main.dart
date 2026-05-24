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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    debugPrint('[FR.BOOT] Firebase initialized OK');
  } catch (err) {
    debugPrint('[FR.BOOT] Firebase init failed: $err');
  }
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
    );
    debugPrint('[FR.BOOT] AppCheck activated OK');
  } catch (err) {
    debugPrint('[FR.BOOT] AppCheck skipped: $err');
  }

  // Portrait-only — game layout breaks in landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await httpAgent.init();

  final store = DataStore();
  await store.init();

  final netChecker = NetChecker();
  final tracker = AnalyticsTracker();
  final apiClient = ApiClient(store);
  final pushManager = PushManager(store);

  runApp(FeatherRunApp(
    store: store,
    netChecker: netChecker,
    tracker: tracker,
    apiClient: apiClient,
    pushManager: pushManager,
  ));
}
