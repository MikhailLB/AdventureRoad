import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
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

  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      await _initLocalNotifications();

      _token = await _messaging!.getToken();

      _messaging!.onTokenRefresh.listen((newToken) {
        _token = newToken;
        onTokenRefresh?.call(newToken);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedFromBackground);

      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedFromColdStart(initialMessage);
      }

      _initialized = true;
    } catch (_) {}
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
      settings,
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
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  void _handleOpenedFromColdStart(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _store.setPushUrl(url);
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
