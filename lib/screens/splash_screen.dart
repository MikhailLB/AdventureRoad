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

  Future<void> _run() async {
    widget.pushService.onTokenRefresh = _onPushTokenRefresh;
    await widget.pushService.init().catchError((_) {});

    _setBar(_BarState.empty);

    final mode = widget.storage.getAppMode();

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

  Future<void> _handleOnlineMode() async {
    final hasInternet = await widget.connectivity.hasInternet();

    if (!hasInternet) {
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToNoInternet(isFirstLaunch: false);
      return;
    }

    // One-time push URL takes priority
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
                      errorBuilder: (_, __, ___) => const SizedBox(height: 30),
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
