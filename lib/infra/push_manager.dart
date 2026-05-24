import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'http_agent.dart';
import 'data_store.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushManager {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final DataStore _store;
  FirebaseMessaging? _messaging;
  String? _token;
  bool _initialized = false;

  Function(String url)? onNotificationUrl;
  Function(String newToken)? onTokenRefresh;

  PushManager(this._store);

  String? get token => _token;

  // Polls for the iOS APNs token before attempting to fetch the FCM token.
  // getToken() returns null if called before APNs has registered — typically
  // 0.5–2.5 s after launch. Mirrors TowerFalls' PulseDispatch._waitForApnsToken.
  static const int _apnsRetries = 5;
  static const Duration _apnsBackoff = Duration(milliseconds: 500);

  Future<void> _waitForApnsToken({
    int retries = _apnsRetries,
    Duration backoff = _apnsBackoff,
  }) async {
    final m = _messaging;
    if (m == null) return;
    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        final apns = await m.getAPNSToken();
        if (apns != null && apns.isNotEmpty) return;
      } catch (_) {}
      await Future.delayed(backoff);
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      // Firebase.initializeApp() is already called in main.dart before runApp.
      // Calling it again here raises [core/duplicate-app] on some firebase_core
      // versions — the catch(_){} would swallow it, leaving _messaging null and
      // silently skipping all onMessage/onMessageOpenedApp registrations.
      _messaging = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      await _initLocalNotifications();

      // iOS: let the system present push banners while the app is in foreground.
      // Without this Firebase calls completionHandler([]) which suppresses the
      // banner, and our flutter_local_notifications fallback can conflict with
      // Firebase's swizzled delegate. With it, the system shows the banner and
      // _handleForegroundMessage skips the local-notification path on iOS.
      if (Platform.isIOS) {
        try {
          await _messaging!.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
        } catch (_) {}
      }

      _messaging!.onTokenRefresh.listen((newToken) {
        _token = newToken;
        onTokenRefresh?.call(newToken);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedFromBackground);

      // Capture cold-start tap BEFORE any slow token work so we never lose
      // the push URL to a timeout race. Awaited so the secure-storage write
      // is complete before init() returns and consumePushUrl() is called.
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        await _handleOpenedFromColdStart(initialMessage);
      }

      // iOS: wait for the APNs token before asking for the FCM token.
      // getToken() returns null until APNs has registered — typically takes
      // 0.5–2.5 s after first launch / permission grant.
      if (Platform.isIOS) {
        await _waitForApnsToken();
      }

      _token = await _messaging!.getToken();

      _initialized = true;
    } catch (_) {}
  }

  // Called explicitly from NotifyPage after the user grants push permission.
  // Uses a longer APNs poll (14 × 700 ms = up to ~10 s) because the APNs
  // registration can be slower immediately after the user taps "Allow".
  Future<String?> refreshTokenAfterConsent() async {
    final m = _messaging;
    if (m == null) return null;
    try {
      if (Platform.isIOS) {
        await _waitForApnsToken(
          retries: 14,
          backoff: const Duration(milliseconds: 700),
        );
      }
      _token = await m.getToken().timeout(const Duration(seconds: 10));
      final fresh = _token;
      if (fresh != null && fresh.isNotEmpty) {
        onTokenRefresh?.call(fresh);
      }
      return fresh;
    } catch (_) {
      return null;
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
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
          'high_importance_channel',
          'High Importance Notifications',
          description: 'Channel for push notifications',
          importance: Importance.high,
        ),
      );
    }
  }

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
    await _store.setNotificationGranted(granted);
    await _store.setNotificationSystemDenied(!granted);
    return granted;
  }

  void _handleForegroundMessage(RemoteMessage message) async {
    // On iOS the system already presents the notification (alert/badge/sound
    // are enabled via setForegroundNotificationPresentationOptions in init).
    // Showing an additional flutter_local_notifications copy would duplicate
    // the banner and break tap routing (Firebase's swizzled delegate handles
    // taps on FCM-displayed notifications via onMessageOpenedApp).
    if (Platform.isIOS) return;

    final notification = message.notification;
    if (notification == null) return;

    String? bigPictureUrl;
    if (Platform.isAndroid) {
      bigPictureUrl = message.notification?.android?.imageUrl;
    } else {
      bigPictureUrl = message.notification?.apple?.imageUrl;
    }

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

    final payload =
        message.data.isNotEmpty ? jsonEncode(message.data) : null;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> _handleOpenedFromColdStart(RemoteMessage message) async {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      await _store.setPushUrl(url);
    }
  }

  void _handleOpenedFromBackground(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onNotificationUrl?.call(url);
    }
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final response =
          await httpAgent.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
