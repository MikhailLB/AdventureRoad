import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../game/game_assets.dart';
import '../models/app_mode.dart';
import '../services/appsflyer_service.dart';
import '../services/remote_service.dart';
import '../services/connectivity_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import '../game/game_screen.dart';
import 'no_internet_screen.dart';
import 'notification_permission_screen.dart';
import 'content_screen.dart' deferred as content;

// ============================================================
// SPLASH SCREEN — Gray/white routing orchestrator + loading UI
// ============================================================
// PURPOSE: Entry screen. Plays the loading video animation,
// runs the gray flow logic, and navigates to either:
//   → ContentScreen (WebView) — if backend returns ok+url
//   → GameScreen (white game)  — if offline or backend says no
//
// ⚠️ DEFERRED IMPORT: content_screen.dart is imported deferred.
// This delays loading the WebView engine until gray mode is confirmed,
// reducing startup time for organic (game) users.
//
// LOADING BAR STATES (3 asset images):
//   _BarState.empty       → assets/bar_empty.png  (0% loaded)
//   _BarState.threeQuarter → assets/bar_3_4.png   (75% loaded)
//   _BarState.full        → assets/bar_full.png   (100% loaded)
// Set bar state at key points to give visual feedback during attribution wait.
//
// VIDEO ASSETS:
//   Portrait:  assets/Wait.mp4
//   Landscape: assets/loading_horizontal.mp4
// Video switches automatically when orientation changes (didChangeDependencies).
//
// ─────────────────────────────────────────────────────
// GRAY FLOW STATE MACHINE (implement in _run()):
// ─────────────────────────────────────────────────────
//
// AppMode.pending (FIRST LAUNCH):
//   1. Check internet → if none → NoInternetScreen(isFirstLaunch: true)
//   2. setBar(threeQuarter)
//   3. appsFlyer.init()
//   4. await Future.wait([waitForAttribution(), waitForDeepLink()])
//   5. locale = Platform.localeName.replaceAll('-', '_')
//   6. body = await appsFlyer.buildRequestBody(locale, pushToken)
//   7. response = await remoteApi.fetchRemote(body)
//   8. If response.ok && url != null:
//      → storage.setAppMode(online)
//      → setBar(full) → delay 400ms
//      → _navigateToContent(url)
//   9. Else:
//      → storage.setAppMode(offline)
//      → await GameAssets().loadAll()
//      → setBar(full) → delay 400ms
//      → _navigateToGame()
//
// AppMode.online (RETURNING USER, WAS WEBVIEW):
//   1. Check internet → if none → setBar(full) → NoInternetScreen(isFirstLaunch: false)
//   2. consumePushUrl() → if url → setBar(full) → _navigateToContent(pushUrl) [PRIORITY]
//   3. appsFlyer.init()
//   4. await Future.wait([
//        waitForAttribution().timeout(10s, onTimeout: {}),
//        waitForDeepLink()
//      ])
//   5. body = await appsFlyer.buildRequestBody(locale, pushToken)
//   6. response = await remoteApi.fetchRemote(body)
//   7. setBar(full) → delay 400ms
//   8. If response.ok && url → _navigateToContent(url)
//   9. Else if savedUrl != null → _navigateToContent(savedUrl)
//  10. Else → _navigateToNoInternet(isFirstLaunch: false)
//
// AppMode.offline (RETURNING USER, WAS GAME):
//   1. setBar(threeQuarter)
//   2. await GameAssets().loadAll()
//   3. setBar(full) → delay 600ms
//   4. _navigateToGame()
//
// TOKEN REFRESH:
//   Register pushService.onTokenRefresh = _onPushTokenRefresh in _run().
//   When FCM rotates the token, re-POST to config endpoint with new token.
// ─────────────────────────────────────────────────────

enum _BarState { empty, threeQuarter, full }

class SplashScreen extends StatefulWidget {
  final StorageService storage;
  final ConnectivityService connectivity;
  final AppsFlyerService appsFlyer;
  final RemoteService remoteApi;
  final PushNotificationService pushService;

  const SplashScreen({
    super.key,
    required this.storage,
    required this.connectivity,
    required this.appsFlyer,
    required this.remoteApi,
    required this.pushService,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  _BarState _bar = _BarState.empty;
  bool _navigated = false;
  Orientation? _currentOrientation;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (orientation != _currentOrientation) {
      _currentOrientation = orientation;
      _switchVideo(orientation);
    }
  }

  /// Switches the loading video when orientation changes.
  /// Initializes new controller, plays it, then disposes the old one.
  Future<void> _switchVideo(Orientation orientation) async {
    final asset = orientation == Orientation.landscape
        ? 'assets/loading_horizontal.mp4'
        : 'assets/Wait.mp4';

    final oldController = _videoController;
    final newController = VideoPlayerController.asset(asset);

    try {
      await newController.initialize();
      newController.setLooping(true);
      newController.setVolume(0);
      newController.play();

      if (!mounted) {
        newController.dispose();
        return;
      }

      setState(() {
        _videoController = newController;
        _videoReady = true;
      });

      oldController?.dispose();
    } catch (_) {
      newController.dispose();
    }
  }

  /// Main routing logic. Called from initState().
  ///
  /// TODO: Implement the full gray flow state machine described in the
  /// header comment above. The flow reads appMode from storage and
  /// branches into _handleFirstLaunch(), _handleOnlineMode(), or game navigation.
  ///
  /// Register pushService.onTokenRefresh = _onPushTokenRefresh FIRST
  /// before any async work, so token rotations are captured even if
  /// the attribution flow is still running.
  Future<void> _run() async {
    widget.pushService.onTokenRefresh = _onPushTokenRefresh;
    await widget.pushService.init().catchError((_) {});

    _setBar(_BarState.empty);

    final mode = widget.storage.getAppMode();

    // TODO: Implement the full routing switch:
    switch (mode) {
      case AppMode.online:
        _setBar(_BarState.threeQuarter);
        await _handleOnlineMode();
        break;
      case AppMode.offline:
        _setBar(_BarState.threeQuarter);
        await GameAssets().loadAll();
        _setBar(_BarState.full);
        await Future.delayed(const Duration(milliseconds: 600));
        _navigateToGame();
        break;
      case AppMode.pending:
        await _handleFirstLaunch();
        break;
    }
  }

  @override
  void dispose() {
    widget.pushService.onTokenRefresh = null;
    _videoController?.dispose();
    super.dispose();
  }

  /// Called when FCM token rotates.
  /// Re-POST to config endpoint to keep push_token fresh on the backend.
  void _onPushTokenRefresh(String newToken) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.appsFlyer.buildRequestBody(
      locale: locale,
      pushToken: newToken,
    );
    widget.remoteApi.fetchRemote(body);
  }

  void _setBar(_BarState b) {
    if (mounted) setState(() => _bar = b);
  }

  /// First launch flow (AppMode.pending).
  ///
  /// TODO: Implement following the state machine in the header comment.
  /// Key points:
  ///   - Check internet FIRST, show NoInternetScreen if offline
  ///   - Init AppsFlyer, wait for both attribution AND deep link
  ///   - Build body, fetch remote, set app mode based on response
  ///   - For game mode: preload GameAssets before navigating
  Future<void> _handleFirstLaunch() async {
    _setBar(_BarState.empty);

    final hasInternet = await widget.connectivity.hasInternet();
    if (!hasInternet) {
      if (!mounted) return;
      _navigateToNoInternet(isFirstLaunch: true);
      return;
    }

    _setBar(_BarState.threeQuarter);
    await widget.appsFlyer.init();
    await Future.wait([
      widget.appsFlyer.waitForAttribution(),
      widget.appsFlyer.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.appsFlyer.buildRequestBody(
      locale: locale,
      pushToken: widget.pushService.token,
    );
    final response = await widget.remoteApi.fetchRemote(body);

    if (response.ok && response.url != null) {
      await widget.storage.setAppMode(AppMode.online);
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToContent(response.url!);
    } else {
      await widget.storage.setAppMode(AppMode.offline);
      await GameAssets().loadAll();
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToGame();
    }
  }

  /// Returning online user flow (AppMode.online).
  ///
  /// TODO: Implement following the state machine in the header comment.
  /// Key points:
  ///   - consumePushUrl() takes PRIORITY over everything else
  ///   - Attribution timeout is 10s (not 30s) for returning users
  ///   - Fall back to savedUrl if API fails
  Future<void> _handleOnlineMode() async {
    final hasInternet = await widget.connectivity.hasInternet();

    if (!hasInternet) {
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToNoInternet(isFirstLaunch: false);
      return;
    }

    // Push URL takes priority over everything
    final pushUrl = await widget.storage.consumePushUrl();
    if (pushUrl != null) {
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToContent(pushUrl);
      return;
    }

    final savedUrl = await widget.storage.getSavedUrl();

    await widget.appsFlyer.init();
    await Future.wait([
      widget.appsFlyer
          .waitForAttribution()
          .timeout(const Duration(seconds: 10), onTimeout: () => {}),
      widget.appsFlyer.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.appsFlyer.buildRequestBody(
      locale: locale,
      pushToken: widget.pushService.token,
    );
    final response = await widget.remoteApi.fetchRemote(body);

    _setBar(_BarState.full);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    if (response.ok && response.url != null) {
      _navigateToContent(response.url!);
      return;
    }

    if (savedUrl != null) {
      _navigateToContent(savedUrl);
    } else {
      _navigateToNoInternet(isFirstLaunch: false);
    }
  }

  /// Navigate to ContentScreen (WebView gray mode).
  /// Checks shouldShowNotificationScreen() — if true, shows the promo first.
  ///
  /// Uses deferred import to load the WebView engine only when needed.
  Future<void> _navigateToContent(String url) async {
    if (_navigated) return;
    _navigated = true;

    await content.loadLibrary();
    await content.prepareContentEngine();
    if (!mounted) return;

    if (widget.storage.shouldShowNotificationScreen()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => NotificationPermissionScreen(
            storage: widget.storage,
            pushService: widget.pushService,
            connectivity: widget.connectivity,
            contentUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => content.ContentScreen(
            url: url,
            storage: widget.storage,
            pushService: widget.pushService,
            connectivity: widget.connectivity,
          ),
        ),
      );
    }
  }

  void _navigateToNoInternet({required bool isFirstLaunch}) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NoInternetScreen(
          retryScreenBuilder: (_) => SplashScreen(
            storage: widget.storage,
            connectivity: widget.connectivity,
            appsFlyer: widget.appsFlyer,
            remoteApi: widget.remoteApi,
            pushService: widget.pushService,
          ),
        ),
      ),
    );
  }

  void _navigateToGame() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barAsset = switch (_bar) {
      _BarState.empty => 'assets/bar_empty.png',
      _BarState.threeQuarter => 'assets/bar_3_4.png',
      _BarState.full => 'assets/bar_full.png',
    };

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF1A1A2E)),
          AnimatedOpacity(
            opacity: _videoReady ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: _videoController != null && _videoReady
                ? SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (_videoReady)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.7,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Image.asset(
                      barAsset,
                      key: ValueKey(barAsset),
                      fit: BoxFit.fitWidth,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(height: 30),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
