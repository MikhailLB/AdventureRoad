import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../infra/net_checker.dart';
import '../infra/http_agent.dart';
import '../infra/push_manager.dart';
import '../infra/data_store.dart';
import 'no_signal_page.dart';

Future<void> prepareContentEngine() async {}

class WebViewPage extends StatefulWidget {
  final String url;
  final DataStore store;
  final PushManager pushManager;
  final NetChecker netChecker;
  /// True when opened directly from a cold-start push tap (app was killed).
  final bool coldStartPush;

  const WebViewPage({
    super.key,
    required this.url,
    required this.store,
    required this.pushManager,
    required this.netChecker,
    this.coldStartPush = false,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _showingNoInternet = false;
  String? _lastRedirectUrl;
  int _redirectRetryCount = 0;
  bool _viewportReady = false;
  bool _coldReloadDone = false;

  void _applySystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeMetrics() {
    // Rebuild viewPadding once immersive mode settles (gray_flow_guide §2)
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applySystemUI();
    }
  }

  /// Micro-rotation forces WKWebView to recalculate its native frame.
  Future<void> _nudgeLayout() async {
    if (!Platform.isIOS) return;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initColdStartSurface() async {
    _applySystemUI();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _nudgeLayout();
    await Future.delayed(const Duration(milliseconds: 250));
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

    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(httpAgent.userAgent)
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
          _injectAntiZoom();
          // gray_flow_guide §2 — force viewport recalc after immersive settles.
          Future.delayed(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            setState(() {}); // re-read viewPadding
            _controller.runJavaScript(
              'window.dispatchEvent(new Event("resize"));'
              'if(window.visualViewport)'
              '  window.visualViewport.dispatchEvent(new Event("resize"));',
            );
            _injectSiteAreaKill();
            // On cold-start: reload once so site recalculates with correct UA
            if (widget.coldStartPush && !_coldReloadDone) {
              _coldReloadDone = true;
              _controller.reload();
            }
          });
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

    if (widget.coldStartPush) {
      // Delay mount + load until immersive mode settles (gray_flow_guide §2)
      _initColdStartSurface().then((_) {
        if (!mounted) return;
        setState(() => _viewportReady = true);
        _controller.loadRequest(Uri.parse(widget.url));
      });
    } else {
      _viewportReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySystemUI();
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) _controller.loadRequest(Uri.parse(widget.url));
        });
      });
    }

    widget.pushManager.onNotificationUrl = (url) {
      if (mounted) {
        _controller.loadRequest(Uri.parse(url));
      }
    };

    _connectivitySub =
        widget.netChecker.onConnectivityChanged.listen((results) {
      final lost = results.every((r) => r == ConnectivityResult.none);
      if (lost) _checkAndShowNoInternet();
    });
  }

  Future<void> _checkAndShowNoInternet() async {
    if (_showingNoInternet) return;
    final hasInternet = await widget.netChecker.hasInternet();
    if (hasInternet || !mounted) return;
    _showingNoInternet = true;

    final currentUrl = await _controller.currentUrl() ?? widget.url;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NoSignalPage(
          retryScreenBuilder: (_) => WebViewPage(
            url: currentUrl,
            store: widget.store,
            pushManager: widget.pushManager,
            netChecker: widget.netChecker,
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

  void _injectAntiZoom() {
    if (!Platform.isIOS) return;
    _controller.runJavaScript(r'''
(function(){
  if (window.__arAZ) return;
  window.__arAZ = true;
  var s = document.createElement('style');
  s.id = '__arAZ';
  // iOS auto-zooms when a focused input has font-size < 16px.
  // Setting font-size to at least 16px on focus prevents the zoom
  // without disabling user accessibility zoom entirely.
  s.textContent =
    'input:not([type=range]):not([type=checkbox]):not([type=radio]),' +
    'textarea,select{font-size:max(16px,1em)!important;}';
  (document.head || document.documentElement).appendChild(s);
})();
''');
  }

  void _injectKeyboardScrollFix() {
    _controller.runJavaScript(r'''
(function(){
  if (window.__tfKbFix) return;
  window.__tfKbFix = true;
  function inputLike(n){ return n && (n.tagName==='INPUT' || n.tagName==='TEXTAREA' || n.isContentEditable); }
  function focusRoll(){
    var el = document.activeElement;
    if (!inputLike(el)) return;
    var vp = window.visualViewport;
    if (vp){
      var r = el.getBoundingClientRect();
      if (r.bottom > vp.offsetTop + vp.height - 20 || r.top < vp.offsetTop){
        el.scrollIntoView({ behavior:'smooth', block:'center' });
      }
    } else {
      el.scrollIntoView({ behavior:'smooth', block:'center' });
    }
  }
  document.addEventListener('focusin', function(e){
    if (inputLike(e.target)){
      setTimeout(focusRoll,250);
      setTimeout(focusRoll,500);
      setTimeout(focusRoll,800);
    }
  });
  if (window.visualViewport){
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function(){
      var h = window.visualViewport.height;
      if (h < prev){ setTimeout(focusRoll,80); setTimeout(focusRoll,300); }
      prev = h;
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
    widget.pushManager.onNotificationUrl = null;
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
    // On cold-start: skip viewPadding until surface is ready (stale insets
    // cause black letterboxing — gray_flow_guide §2)
    final safe = widget.coldStartPush
        ? EdgeInsets.zero
        : EdgeInsets.only(
            top: MediaQuery.of(context).viewPadding.top,
            bottom: MediaQuery.of(context).viewPadding.bottom,
            left: MediaQuery.of(context).viewPadding.left,
            right: MediaQuery.of(context).viewPadding.right,
          );

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
            if (_viewportReady)
              Padding(
                padding: safe,
                child: WebViewWidget(controller: _controller),
              )
            else
              const ColoredBox(color: Colors.black),
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
