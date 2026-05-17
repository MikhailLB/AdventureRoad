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

Future<void> prepareContentEngine() async {}

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
  String? _lastRedirectUrl;
  int _redirectRetryCount = 0;

  void _applySystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applySystemUI();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applySystemUI();

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
            if (request.isMainFrame) {
              _lastRedirectUrl = request.url;
            }
            return NavigationDecision.navigate;
          }

          _launchExternal(uri);
          return NavigationDecision.prevent;
        },
      ))
      ..enableZoom(false);

    _configurePlatform();
    _controller.loadRequest(Uri.parse(widget.url));

    widget.pushService.onNotificationUrl = (url) {
      if (mounted) {
        _controller.loadRequest(Uri.parse(url));
      }
    };

    _connectivitySub =
        widget.connectivity.onConnectivityChanged.listen((results) {
      final lost = results.every((r) => r == ConnectivityResult.none);
      if (lost) _checkAndShowNoInternet();
    });
  }

  Future<void> _checkAndShowNoInternet() async {
    if (_showingNoInternet) return;
    final hasInternet = await widget.connectivity.hasInternet();
    if (hasInternet || !mounted) return;
    _showingNoInternet = true;

    final currentUrl =
        await _controller.currentUrl() ?? widget.url;

    if (!mounted) return;
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

  void _configurePlatform() {
    if (Platform.isAndroid &&
        _controller.platform is AndroidWebViewController) {
      final androidController =
          _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);

      androidController.setOnShowFileSelector(_handleFileSelector);

      final cookieManager = AndroidWebViewCookieManager(
        AndroidWebViewCookieManagerCreationParams
            .fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        ),
      );
      cookieManager.setAcceptThirdPartyCookies(androidController, true);
    }
  }

  Future<List<String>> _handleFileSelector(
      FileSelectorParams params) async {
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
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    } else {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  document.addEventListener('focusin', function(e) {
    if (isInput(e.target)) {
      setTimeout(doScroll, 250);
      setTimeout(doScroll, 500);
      setTimeout(doScroll, 800);
    }
  });

  if (window.visualViewport) {
    var prevH = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < prevH) {
        setTimeout(doScroll, 80);
        setTimeout(doScroll, 300);
      }
      prevH = h;
    });
  }
})();
''');
  }

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
    // Fix viewport meta only if needed
    var m = document.querySelector('meta[name="viewport"]');
    if (m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content') || '')) {
      var c = (m.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      m.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    // Inject/update style
    var s = document.getElementById(CSS_ID);
    if (!s) {
      s = document.createElement('style');
      s.id = CSS_ID;
      head.appendChild(s);
    }
    if (s.textContent !== CSS_TEXT) s.textContent = CSS_TEXT;
    // Keep as last style so specificity wins
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  apply();

  // Re-apply on SPA route change (Vue/Nuxt uses history API)
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

  // Safety net every 2.5s — no loop risk since setInterval is not reactive
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
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
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
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
