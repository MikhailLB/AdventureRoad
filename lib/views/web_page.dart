import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WebPage extends StatefulWidget {
  final String title;
  final String url;

  const WebPage({super.key, required this.title, required this.url});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  bool _opening = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _openExternal();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (opened) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _opening = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Center(
        child: _opening
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
              )
            : _failed
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Unable to open this link.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}
