import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core/media_bundle.dart';
import '../data/app_state.dart';
import '../infra/analytics_tracker.dart';
import '../infra/api_client.dart';
import '../infra/cold_start_bridge.dart';
import '../infra/net_checker.dart';
import '../infra/push_manager.dart';
import '../infra/data_store.dart';
import '../core/play_view.dart';
import 'no_signal_page.dart';
import 'notify_page.dart';
import 'web_view_page.dart' deferred as webview;

enum _BarState { empty, threeQuarter, full }

class LaunchPage extends StatefulWidget {
  final DataStore store;
  final NetChecker netChecker;
  final AnalyticsTracker tracker;
  final ApiClient apiClient;
  final PushManager pushManager;

  const LaunchPage({
    super.key,
    required this.store,
    required this.netChecker,
    required this.tracker,
    required this.apiClient,
    required this.pushManager,
  });

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
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
    widget.pushManager.onTokenRefresh = _onPushTokenRefresh;
    await widget.pushManager.init().catchError((_) {});

    // Express lane: if the app was launched by a cold-start push tap,
    // SceneDelegate has already stored the destination URL. Navigate
    // directly without going through attribution / API flow.
    if (Platform.isIOS) {
      final launchUrl = await ColdStartBridge.consumeLaunchUrl();
      if (launchUrl != null) {
        await _navigateToContent(launchUrl);
        return;
      }
    }

    _setBar(_BarState.empty);

    final mode = widget.store.getAppMode();

    switch (mode) {
      case AppState.online:
        _setBar(_BarState.threeQuarter);
        await _handleOnlineMode();
        break;
      case AppState.offline:
        _setBar(_BarState.threeQuarter);
        final restoredOnline = await _tryRestoreOnlineContent();
        if (restoredOnline) return;
        await MediaBundle().loadAll();
        _setBar(_BarState.full);
        await Future.delayed(const Duration(milliseconds: 600));
        _navigateToGame();
        break;
      case AppState.pending:
        await _handleFirstLaunch();
        break;
    }
  }

  @override
  void dispose() {
    widget.pushManager.onTokenRefresh = null;
    _videoController?.dispose();
    super.dispose();
  }

  void _onPushTokenRefresh(String newToken) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.buildRequestBody(
      locale: locale,
      pushToken: newToken,
    );
    widget.apiClient.fetchRemote(body);
  }

  void _setBar(_BarState b) {
    if (mounted) setState(() => _bar = b);
  }

  Future<void> _handleFirstLaunch() async {
    _setBar(_BarState.empty);

    final hasInternet = await widget.netChecker.hasInternet();
    if (!hasInternet) {
      if (!mounted) return;
      _navigateToNoSignal(isFirstLaunch: true);
      return;
    }

    _setBar(_BarState.threeQuarter);
    await widget.tracker.init();
    await Future.wait([
      widget.tracker.waitForAttribution(),
      widget.tracker.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.buildRequestBody(
      locale: locale,
      pushToken: widget.pushManager.token,
    );
    final response = await widget.apiClient.fetchRemote(body);

    if (response.ok && response.url != null) {
      await widget.store.setAppMode(AppState.online);
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToContent(response.url!);
    } else {
      await widget.store.setAppMode(AppState.offline);
      await MediaBundle().loadAll();
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToGame();
    }
  }

  Future<void> _handleOnlineMode() async {
    final hasInternet = await widget.netChecker.hasInternet();

    if (!hasInternet) {
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToNoSignal(isFirstLaunch: false);
      return;
    }

    final pushUrl = await widget.store.consumePushUrl();
    if (pushUrl != null) {
      _setBar(_BarState.full);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _navigateToContent(pushUrl);
      return;
    }

    final savedUrl = await widget.store.getSavedUrl();

    await widget.tracker.init();
    await Future.wait([
      widget.tracker
          .waitForAttribution()
          .timeout(const Duration(seconds: 10), onTimeout: () => {}),
      widget.tracker.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.buildRequestBody(
      locale: locale,
      pushToken: widget.pushManager.token,
    );
    final response = await widget.apiClient.fetchRemote(body);

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
      _navigateToNoSignal(isFirstLaunch: false);
    }
  }

  Future<bool> _tryRestoreOnlineContent() async {
    final hasInternet = await widget.netChecker.hasInternet();
    if (!hasInternet) return false;

    await widget.tracker.init();
    await Future.wait([
      widget.tracker
          .waitForAttribution()
          .timeout(const Duration(seconds: 8), onTimeout: () => {}),
      widget.tracker.waitForDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.buildRequestBody(
      locale: locale,
      pushToken: widget.pushManager.token,
    );
    final response = await widget.apiClient.fetchRemote(body);

    if (!(response.ok && response.url != null)) return false;

    await widget.store.setAppMode(AppState.online);
    _setBar(_BarState.full);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return true;
    _navigateToContent(response.url!);
    return true;
  }

  Future<void> _navigateToContent(String url) async {
    if (_navigated) return;
    _navigated = true;

    await webview.loadLibrary();
    await webview.prepareContentEngine();
    if (!mounted) return;

    if (widget.store.shouldShowNotificationScreen()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => NotifyPage(
            store: widget.store,
            pushManager: widget.pushManager,
            netChecker: widget.netChecker,
            contentUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => webview.WebViewPage(
            url: url,
            store: widget.store,
            pushManager: widget.pushManager,
            netChecker: widget.netChecker,
          ),
        ),
      );
    }
  }

  void _navigateToNoSignal({required bool isFirstLaunch}) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NoSignalPage(
          retryScreenBuilder: (_) => LaunchPage(
            store: widget.store,
            netChecker: widget.netChecker,
            tracker: widget.tracker,
            apiClient: widget.apiClient,
            pushManager: widget.pushManager,
          ),
        ),
      ),
    );
  }

  void _navigateToGame() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlayView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barAsset = switch (_bar) {
      _BarState.empty => 'assets/bar_empty.webp',
      _BarState.threeQuarter => 'assets/bar_3_4.webp',
      _BarState.full => 'assets/loading_bar_full.webp',
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
                  width: MediaQuery.of(context).size.width * 0.55,
                  height: 48,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Image.asset(
                      barAsset,
                      key: ValueKey(barAsset),
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stack) =>
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
