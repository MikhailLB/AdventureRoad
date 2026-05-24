import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NoSignalPage extends StatefulWidget {
  final WidgetBuilder retryScreenBuilder;

  const NoSignalPage({super.key, required this.retryScreenBuilder});

  @override
  State<NoSignalPage> createState() => _NoSignalPageState();
}

class _NoSignalPageState extends State<NoSignalPage>
    with SingleTickerProviderStateMixin {
  bool _isRetrying = false;
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRetry() async {
    if (_isRetrying) return;
    HapticFeedback.lightImpact();
    await _pressCtrl.forward();
    await _pressCtrl.reverse();
    setState(() => _isRetrying = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.retryScreenBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    final bgAsset = isLandscape
        ? 'assets/16x9_NoWifi_Screen.webp'
        : 'assets/9x16_NoWifi_Screen.webp';

    final btnBottom = isLandscape ? size.height * 0.07 : size.height * 0.18;
    final btnWidth  = isLandscape
        ? (size.width * 0.24).clamp(200.0, 340.0)
        : (size.width * 0.58).clamp(200.0, 340.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            bgAsset,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) =>
                const ColoredBox(color: Color(0xFF0D1B2A)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: btnBottom,
            child: Center(
              child: ScaleTransition(
                scale: _pressScale,
                child: SizedBox(
                  width: btnWidth,
                  height: 54,
                  child: GestureDetector(
                    onTap: _isRetrying ? null : _onRetry,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _isRetrying
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: _isRetrying
                            ? const Color(0xFF0072FF).withValues(alpha: 0.35)
                            : null,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFF003366),
                          width: 2.5,
                        ),
                        boxShadow: _isRetrying
                            ? []
                            : [
                                BoxShadow(
                                  color: const Color(0xFF0072FF)
                                      .withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Center(
                        child: _isRetrying
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 8),
                                  Text(
                                    'Try Again',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
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
