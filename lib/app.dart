import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/appsflyer_service.dart';
import 'services/remote_service.dart';
import 'services/connectivity_service.dart';
import 'services/push_notification_service.dart';
import 'services/storage_service.dart';

class ChickenTripApp extends StatelessWidget {
  final StorageService storage;
  final ConnectivityService connectivity;
  final AppsFlyerService appsFlyer;
  final RemoteService remoteApi;
  final PushNotificationService pushService;

  const ChickenTripApp({
    super.key,
    required this.storage,
    required this.connectivity,
    required this.appsFlyer,
    required this.remoteApi,
    required this.pushService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken Trip 2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.deepOrange,
          surface: Color(0xFF1A1A2E),
        ),
      ),
      home: SplashScreen(
        storage: storage,
        connectivity: connectivity,
        appsFlyer: appsFlyer,
        remoteApi: remoteApi,
        pushService: pushService,
      ),
    );
  }
}
