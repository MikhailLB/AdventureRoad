import 'package:flutter/material.dart';
import 'pages/launch_page.dart';
import 'infra/analytics_tracker.dart';
import 'infra/api_client.dart';
import 'infra/net_checker.dart';
import 'infra/push_manager.dart';
import 'infra/data_store.dart';

/// ════════════════════════════════════════════════════════════
/// Root widget — wires services into the gray flow
/// ════════════════════════════════════════════════════════════
///
/// ⚠️  TODO:
///   1. Rename [StreetSurgeApp] to match your app (e.g. MyGameApp).
///   2. Update [title] to your app name.
///   3. Adjust [scaffoldBackgroundColor] to match your splash color.
///   4. Update main.dart to call runApp(YourApp(...)).
/// ════════════════════════════════════════════════════════════
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
      // TODO: Set your app title
      title: 'TODO_APP_NAME',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // TODO: Match your splash/loading screen background color
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
