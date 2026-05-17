import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/storage_service.dart';
import 'services/connectivity_service.dart';
import 'services/appsflyer_service.dart';
import 'services/remote_service.dart';
import 'services/push_notification_service.dart';
import 'services/http_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

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

  await appHttpClient.init();

  final storage = StorageService();
  await storage.init();

  final connectivity = ConnectivityService();
  final appsFlyer = AppsFlyerService();
  final remoteApi = RemoteService(storage);
  final pushService = PushNotificationService(storage);

  runApp(ChickenTripApp(
    storage: storage,
    connectivity: connectivity,
    appsFlyer: appsFlyer,
    remoteApi: remoteApi,
    pushService: pushService,
  ));
}
