import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../services/connectivity_service.dart';
import '../services/http_client.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import 'no_internet_screen.dart';

// ============================================================
// CONTENT SCREEN — Full-screen WebView shell (gray mode UI)
// ============================================================
// PURPOSE: Display the URL received from the config endpoint
// inside a full-screen WebView. This is the main "gray" screen.
//
// FEATURES:
//   - Full-screen immersive mode (hides status bar + nav bar)
//   - Both portrait and landscape orientations supported
//   - Back press navigates within WebView history (never exits app)
//   - Connectivity monitoring — shows NoInternetScreen if connection drops
//   - Push URL redirect — ContentScreen listens for push notification URLs
//     and loads them live without restarting the app
//   - File upload support via FilePicker (for photo/document upload in WebView)
//   - Third-party cookie support (required for most affiliate sites)
//   - Video autoplay enabled (no user gesture required)
//   - JavaScript injections:
//       _injectSiteAreaKill() — removes safe-area insets to prevent layout gaps
//       _injectKeyboardScrollFix() — scrolls focused inputs above keyboard
//
// NAVIGATION RULES:
//   - http/https/about/data/blob → WebView handles internally
//   - intent://, tel://, market:// → launch via external app (url_launcher)
//   - Back button → WebView goBack() if canGoBack(), otherwise no-op (never exit)
//
// TOO MANY REDIRECTS:
//   Some affiliate chains produce redirect loops. Detect errorCode -1007/-9
//   or description containing "too_many_redirects" and retry up to 3 times
//   from the last known good URL.
// ============================================================

/// Pre-warms the WebView engine before navigation.
/// Called via `content.loadLibrary()` + `content.prepareContentEngine()`.
/// The deferred import in splash_screen.dart delays this until gray mode confirmed.
Future<void> prepareContentEngine() async {
  // TODO: optionally pre-warm WebViewPlatform here if needed
}

class ContentScreen extends StatefulWidget {
  final String url;
  final StorageService storage;
  final PushNotificationService pushService;
  final ConnectivityService connectivity;

  const ContentScreen({
    super.key,
    required this.url,
    required this.storage,
    required this.pushService,
    required this.connectivity,
  });

  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _showingNoInternet = false;

  // Track last navigated URL for too-many-redirects retry
  String? _lastRedirectUrl;
  int _redirectRetryCount = 0;

  void _applySystemUI() {
    // Full immersive — hides both status bar and navigation bar.
    // Re-applied on app resume (lifecycle observer) since Android
    // can reset system UI after permission dialogs or other overlays.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applySystemUI();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // WebView must support both orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applySystemUI();

    // TODO: Build WebViewController with these settings:
    //   - setJavaScriptMode(JavaScriptMode.unrestricted)
    //   - setUserAgent(appHttpClient.userAgent) — real device UA
    //   - setBackgroundColor(Colors.black)
    //   - NavigationDelegate with:
    //       onPageStarted: setState _isLoading = true
    //       onPageFinished: setState _isLoading = false, reset retry counter,
    //                       call _injectSiteAreaKill(), _injectKeyboardScrollFix()
    //       onWebResourceError: detect redirect loop, call _checkAndShowNoInternet()
    //       onNavigationRequest: allow http/https/about/data/blob,
    //                            launch external for other schemes
    //   - enableZoom(false)
    //   - For Android: call _configurePlatform() after building controller
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(appHttpClient.userAgent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
          _redirectRetryCount = 0;
          _injectSiteAreaKill();
          _injectKeyboardScrollFix();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != true) return;

          final desc = error.description.toLowerCase();
          final isTooManyRedirects = desc.contains('too_many_redirects') ||
              desc.contains('too many redirects') ||
              error.errorCode == -1007 ||
              error.errorCode == -9;

          if (isTooManyRedirects &&
              _lastRedirectUrl != null &&
              _redirectRetryCount < 3) {
            _redirectRetryCount++;
            _controller.loadRequest(Uri.parse(_lastRedirectUrl!));
            return;
          }

          _checkAndShowNoInternet();
        },
        onHttpError: (_) {},
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;

          final scheme = uri.scheme;
          if (scheme == 'http' ||
              scheme == 'https' ||
              scheme == 'about' ||
              scheme == 'data' ||
              scheme == 'blob') {
            if (request.isMainFrame) _lastRedirectUrl = request.url;
            return NavigationDecision.navigate;
          }

          _launchExternal(uri);
          return NavigationDecision.prevent;
        },
      ))
      ..enableZoom(false);

    _configurePlatform();
    _controller.loadRequest(Uri.parse(widget.url));

    // Push warm redirect — ContentScreen handles it live
    widget.pushService.onNotificationUrl = (url) {
      if (mounted) _controller.loadRequest(Uri.parse(url));
    };

    // Connectivity drop → NoInternetScreen
    _connectivitySub =
        widget.connectivity.onConnectivityChanged.listen((results) {
      if (results.every((r) => r == ConnectivityResult.none)) {
        _checkAndShowNoInternet();
      }
    });
  }

  Future<void> _checkAndShowNoInternet() async {
    if (_showingNoInternet) return;
    final hasInternet = await widget.connectivity.hasInternet();
    if (hasInternet || !mounted) return;
    _showingNoInternet = true;

    final currentUrl = await _controller.currentUrl() ?? widget.url;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NoInternetScreen(
          retryScreenBuilder: (_) => ContentScreen(
            url: currentUrl,
            storage: widget.storage,
            pushService: widget.pushService,
            connectivity: widget.connectivity,
          ),
        ),
      ),
    );
  }

  /// Configure Android-specific WebView settings.
  /// TODO: Verify third-party cookie handling works with your target sites.
  void _configurePlatform() {
    if (Platform.isAndroid &&
        _controller.platform is AndroidWebViewController) {
      final ctrl = _controller.platform as AndroidWebViewController;

      // Video autoplay — no user gesture required
      ctrl.setMediaPlaybackRequiresUserGesture(false);

      // File upload support (photo picker, document picker)
      ctrl.setOnShowFileSelector(_handleFileSelector);

      // Third-party cookies — required by most affiliate/casino sites
      final cookieManager = AndroidWebViewCookieManager(
        AndroidWebViewCookieManagerCreationParams
            .fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        ),
      );
      cookieManager.setAcceptThirdPartyCookies(ctrl, true);
    }
  }

  Future<List<String>> _handleFileSelector(FileSelectorParams params) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Injects JS to scroll focused inputs above the keyboard.
  ///
  /// IMPORTANT: Use behavior:'auto' NOT behavior:'smooth'.
  /// On Android, smooth scroll conflicts with keyboard animation
  /// and causes the keyboard to visibly jump.
  /// Single setTimeout at 350ms — not multiple at 250/500/800ms.
  void _injectKeyboardScrollFix() {
    _controller.runJavaScript('''
(function() {
  if (window.__kbScrollFixApplied) return;
  window.__kbScrollFixApplied = true;

  function isInput(el) {
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  }

  function doScroll() {
    var el = document.activeElement;
    if (!isInput(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var rect = el.getBoundingClientRect();
      var vpBottom = vp.offsetTop + vp.height;
      if (rect.bottom > vpBottom - 20 || rect.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(e) {
    if (isInput(e.target)) {
      setTimeout(doScroll, 350);
    }
  });

  if (window.visualViewport) {
    var prevH = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < prevH) { setTimeout(doScroll, 120); }
      prevH = h;
    });
  }
})();
''');
  }

  /// Injects CSS to remove safe-area insets and fixes viewport-fit.
  /// Prevents white bars at top/bottom on notched Android devices.
  /// Also re-applies on SPA route changes (Vue/Nuxt pushState).
  void _injectSiteAreaKill() {
    _controller.runJavaScript(r'''
(function() {
  if (window.__flsaRunning) return;
  window.__flsaRunning = true;

  var CSS_ID = '__flsa';
  var CSS_TEXT =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}' +
    'html,body,#__nuxt,#__layout,#app,#root,' +
    '.gameview-mobile-header{' +
      'padding-top:0!important;' +
      'padding-left:0!important;' +
      'padding-right:0!important;' +
      'margin-top:0!important;' +
    '}';

  function apply() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var m = document.querySelector('meta[name="viewport"]');
    if (m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content') || '')) {
      var c = (m.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      m.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(CSS_ID);
    if (!s) {
      s = document.createElement('style');
      s.id = CSS_ID;
      head.appendChild(s);
    }
    if (s.textContent !== CSS_TEXT) s.textContent = CSS_TEXT;
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  apply();

  ['pushState', 'replaceState'].forEach(function(fn) {
    var orig = history[fn];
    history[fn] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    widget.pushService.onNotificationUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    // Never let back button exit the app — navigate within WebView history
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false, // CRITICAL: must be false for keyboard fix
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              // Apply status bar height in portrait; none in landscape (immersive)
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).orientation == Orientation.landscape
                    ? 0
                    : MediaQuery.of(context).viewPadding.top,
              ),
              child: WebViewWidget(controller: _controller),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
