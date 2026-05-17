import 'package:flutter/material.dart';
import 'pages/launch_page.dart';
import 'infra/analytics_tracker.dart';
import 'infra/api_client.dart';
import 'infra/net_checker.dart';
import 'infra/push_manager.dart';
import 'infra/data_store.dart';

class StreetSurgeApp extends StatelessWidget {
  final DataStore store;
  final NetChecker netChecker;
  final AnalyticsTracker tracker;
  final ApiClient apiClient;
  final PushManager pushManager;

  const StreetSurgeApp({
    super.key,
    required this.store,
    required this.netChecker,
    required this.tracker,
    required this.apiClient,
    required this.pushManager,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adventure Road',
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
      home: LaunchPage(
        store: store,
        netChecker: netChecker,
        tracker: tracker,
        apiClient: apiClient,
        pushManager: pushManager,
      ),
    );
  }
}
