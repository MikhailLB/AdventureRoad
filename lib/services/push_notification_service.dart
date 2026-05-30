import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'http_client.dart';
import 'storage_service.dart';

// ============================================================
// PUSH NOTIFICATION SERVICE — Firebase Messaging + local display
// ============================================================
// PURPOSE: Initialize Firebase Messaging, obtain FCM token,
// handle incoming push notifications, and show them with
// the custom notification icon and optional big picture.
//
// PUSH URL BEHAVIOR (per TZ — CRITICAL):
//   Push notifications may contain a `url` field in the data payload.
//   - User taps push while app is KILLED (cold start):
//     → Firebase fires getInitialMessage() at app boot
//     → SAVE the URL to storage (setPushUrl)
//     → SplashScreen reads it on boot via consumePushUrl() and opens it
//   - User taps push while app is BACKGROUNDED/FOREGROUNDED (warm):
//     → Firebase fires onMessageOpenedApp (background) or
//       onMessage + local notification tap (foreground)
//     → Call onNotificationUrl callback — DO NOT save to storage
//     → ContentScreen handles it live via WebViewController.loadRequest
//     → The url is one-time: do NOT persist (next launch uses config URL)
//
// NOTIFICATION CHANNEL (Android):
//   Must match AndroidManifest.xml meta-data:
//   <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id"
//              android:value="high_importance_channel" />
//
// CUSTOM ICON (Android):
//   Notification icon is @drawable/ic_notification (monochrome PNG).
//   Place it at android/app/src/main/res/drawable/ic_notification.png
//   See TZ: must be a separate monochrome icon, not the launcher icon.
//
// IMAGES IN NOTIFICATIONS:
//   Big picture images are downloaded from the URL in notification.android.imageUrl
//   and shown via BigPictureStyleInformation.
//   TODO: Verify this works on Android 13+ with the current implementation.
//
// FIREBASE SERVICE ACCOUNT (per TZ):
//   Add marla-export@marfa-290610.iam.gserviceaccount.com to the Firebase
//   project as Owner via Google Cloud Platform → IAM. Without this, the
//   push notification system cannot send messages to users.
// ============================================================

// Background message handler — must be top-level function (vm:entry-point).
// Keep it minimal — no UI access in background isolate.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled by the OS — no action needed here.
  // The notification tap is handled when app resumes via onMessageOpenedApp
  // or getInitialMessage() on cold start.
}

class PushNotificationService {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StorageService _storage;
  FirebaseMessaging? _messaging;
  String? _token;
  bool _initialized = false;

  /// Callback: called when user taps a push notification while app is warm.
  /// ContentScreen registers this to load the push URL into the WebView.
  /// ⚠️ Do NOT persist this URL — it's one-time only.
  Function(String url)? onNotificationUrl;

  /// Callback: called when FCM token is refreshed.
  /// SplashScreen registers this to re-POST to config endpoint with new token.
  Function(String newToken)? onTokenRefresh;

  PushNotificationService(this._storage);

  String? get token => _token;

  /// Initialize Firebase Messaging, local notifications plugin,
  /// and register all message handlers.
  ///
  /// TODO: This implementation is mostly complete.
  /// Verify the notification channel ID matches AndroidManifest.xml.
  /// If Firebase is not configured, this method fails silently —
  /// the app continues to work without push notifications (per TZ).
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      await _initLocalNotifications();

      // Get current FCM token — may be null if Firebase not configured
      _token = await _messaging!.getToken();

      // Listen for token rotation — re-POST to config endpoint
      _messaging!.onTokenRefresh.listen((newToken) {
        _token = newToken;
        onTokenRefresh?.call(newToken);
      });

      // Foreground message — show local notification (Android only)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Warm background tap — user taps notification, app resumes
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedFromBackground);

      // Cold start tap — app was killed, user taps notification
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedFromColdStart(initialMessage);
      }

      _initialized = true;
    } catch (_) {
      // Firebase not configured — push disabled, app continues normally
    }
  }

  /// Initialize local notifications plugin and create Android channel.
  ///
  /// TODO: Verify '@drawable/ic_notification' exists in
  /// android/app/src/main/res/drawable/ic_notification.png
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification', // TODO: ensure this drawable exists
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (response) {
        // Foreground notification tap — extract and deliver URL
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            final url = data['url'] as String?;
            if (url != null && url.isNotEmpty) {
              onNotificationUrl?.call(url);
            }
          } catch (_) {}
        }
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'high_importance_channel', // TODO: must match AndroidManifest meta-data
          'High Importance Notifications',
          description: 'Channel for push notifications',
          importance: Importance.high,
        ),
      );
    }
  }

  /// Request notification permission from the user.
  /// Called from NotificationPermissionScreen when user taps "Accept".
  ///
  /// On Android 13+ (API 33+), this shows the system permission dialog.
  /// On Android < 13, permission is granted automatically.
  /// Stores the grant result in StorageService for future checks.
  Future<bool> requestPermission() async {
    if (_messaging == null) return false;
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    await _storage.setNotificationGranted(granted);
    return granted;
  }

  /// Show a local notification for a foreground Firebase message (Android only).
  /// iOS system shows banners automatically — do NOT call this on iOS.
  ///
  /// Supports big picture: downloads image from notification.android.imageUrl
  /// and displays via BigPictureStyleInformation.
  void _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    if (!Platform.isAndroid) return; // iOS handles its own banners

    String? bigPictureUrl = message.notification?.android?.imageUrl;
    AndroidNotificationDetails? androidDetails;

    if (bigPictureUrl != null && bigPictureUrl.isNotEmpty) {
      final bigPicture = await _downloadImage(bigPictureUrl);
      if (bigPicture != null) {
        androidDetails = AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bigPicture),
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    androidDetails ??= const AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  /// Cold start: app was killed. User taps push. Firebase delivers via getInitialMessage().
  /// SAVE the URL to storage — SplashScreen will read it on next boot via consumePushUrl().
  void _handleOpenedFromColdStart(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _storage.setPushUrl(url);
    }
  }

  /// Warm resume: app was backgrounded. Firebase fires onMessageOpenedApp.
  /// DELIVER the URL via callback — do NOT save to storage (one-time rule).
  /// ContentScreen handles it live by loading URL into the WebView.
  void _handleOpenedFromBackground(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onNotificationUrl?.call(url);
    }
  }

  /// Download image bytes from URL for big picture notifications.
  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final response = await appHttpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
