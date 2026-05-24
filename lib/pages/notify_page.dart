import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../cfg/app_config.dart';
import '../infra/net_checker.dart';
import '../infra/push_manager.dart';
import '../infra/data_store.dart';
import 'web_view_page.dart' deferred as webview;

class NotifyPage extends StatefulWidget {
  final DataStore store;
  final PushManager pushManager;
  final NetChecker netChecker;
  final String contentUrl;

  const NotifyPage({
    super.key,
    required this.store,
    required this.pushManager,
    required this.netChecker,
    required this.contentUrl,
  });

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  VideoPlayerController? _controller;
  bool _videoReady = false;
  Orientation? _currentOrientation;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (orientation != _currentOrientation) {
      _currentOrientation = orientation;
      _initVideo(orientation);
    }
  }

  Future<void> _initVideo(Orientation orientation) async {
    final asset = orientation == Orientation.landscape
        ? 'assets/notif_h.mp4'
        : 'assets/notif_v.mp4';

    final oldController = _controller;
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
        _controller = newController;
        _videoReady = true;
      });

      oldController?.dispose();
    } catch (_) {
      newController.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onAccept() async {
    final granted = await widget.pushManager.requestPermission();
    if (!mounted) return;
    if (granted) {
      // Explicitly re-fetch the FCM token after permission is granted.
      // On iOS, getToken() in pushManager.init() may have returned null because
      // the APNs token hadn't arrived yet. refreshTokenAfterConsent() polls
      // APNs (up to ~10 s) and then fetches the FCM token, firing onTokenRefresh
      // so the backend receives the production token via the LaunchPage callback.
      await widget.pushManager.refreshTokenAfterConsent();
    } else {
      final skipUntil = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          AppConfig.notificationRetryDelaySeconds;
      await widget.store.setNotificationSkipUntil(skipUntil);
    }
    if (!mounted) return;
    _goToContent();
  }

  void _onSkip() async {
    final skipUntil = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        AppConfig.notificationRetryDelaySeconds;
    await widget.store.setNotificationSkipUntil(skipUntil);
    if (!mounted) return;
    _goToContent();
  }

  Future<void> _goToContent() async {
    await webview.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => webview.WebViewPage(
          url: widget.contentUrl,
          store: widget.store,
          pushManager: widget.pushManager,
          netChecker: widget.netChecker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = _currentOrientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_videoReady && _controller != null)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              )
            else
              Container(color: const Color(0xFF1A1A2E)),

            if (!isLandscape)
              Positioned(
                left: size.width * 0.08,
                right: size.width * 0.08,
                bottom: size.height * 0.07,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _YesButton(onTap: _onAccept),
                    const SizedBox(height: 18),
                    _SkipButton(onTap: _onSkip),
                  ],
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: size.height * 0.06,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width * 0.32,
                      child: _YesButton(onTap: _onAccept, compact: true),
                    ),
                    const SizedBox(height: 8),
                    _SkipButton(onTap: _onSkip, compact: true),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _YesButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _YesButton({required this.onTap, this.compact = false});
  @override
  State<_YesButton> createState() => _YesButtonState();
}

class _YesButtonState extends State<_YesButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (_, _) => AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 12 : 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _pressed
                    ? [const Color(0xFF0093CC), const Color(0xFF004EA8)]
                    : [const Color(0xFF00C6FF), const Color(0xFF0072FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0072FF)
                      .withValues(alpha: _pressed ? 0.2 : _glowAnim.value),
                  blurRadius: _pressed ? 8 : 14 + _glowAnim.value * 18,
                  spreadRadius: _pressed ? 0 : _glowAnim.value * 4,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child:                   Text(
                    'Allow',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 16 : 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _SkipButton({required this.onTap, this.compact = false});
  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.5 : 0.85,
        duration: const Duration(milliseconds: 80),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 8),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 16 : 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                shadows: const [
                  Shadow(
                      color: Colors.black54,
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
