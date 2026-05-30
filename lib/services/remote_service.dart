import 'dart:convert';
import '../config/app_settings.dart';
import '../models/remote_response.dart';
import 'http_client.dart';
import 'storage_service.dart';

// ============================================================
// REMOTE SERVICE — Config endpoint POST request
// ============================================================
// PURPOSE: Send the attribution body to the backend config
// endpoint and receive a decision: show WebView (ok=true, url=...)
// or show game (ok=false).
//
// BEHAVIOR (per TZ):
//   Success (HTTP 200, ok=true, url present):
//     → Save url and expires to StorageService (secure storage)
//     → Return RemoteResponse with ok=true
//
//   Success but ok=false (HTTP 200, ok=false):
//     → Return RemoteResponse with ok=false
//     → Caller sets app mode to offline, shows game
//     → No further config requests in this install (per TZ)
//
//   HTTP error (non-200):
//     → Return RemoteResponse.error(...)
//     → Caller falls back to savedUrl if it exists
//
//   Network timeout (>15s):
//     → Return RemoteResponse.error(...)
//     → Caller falls back to savedUrl if it exists
//
//   No endpoint configured:
//     → Return RemoteResponse.error('Endpoint not set') immediately
//
// URL EXPIRY:
//   The `expires` field is a Unix timestamp. On returning visits,
//   check isUrlExpired(). If expired, re-fetch from server.
//   If fetch fails but savedUrl exists, still use the saved URL.
//   (Expired URLs are shown — they're preferable to no content)
// ============================================================

class RemoteService {
  final StorageService _storage;

  RemoteService(this._storage);

  /// POST attribution body to config endpoint, return server decision.
  ///
  /// TODO: This implementation is mostly complete.
  /// Verify the timeout (15s), Content-Type header, and error handling
  /// match the TZ before deploying.
  Future<RemoteResponse> fetchRemote(Map<String, dynamic> body) async {
    if (AppSettings.apiEndpoint.isEmpty) {
      return RemoteResponse.error('Endpoint not set');
    }

    try {
      final uri = Uri.parse(AppSettings.apiEndpoint);
      final response = await appHttpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = RemoteResponse.fromJson(json);

        // Save url+expires on success so they're available on next launch
        if (result.ok && result.url != null) {
          await _storage.setSavedUrl(result.url!);
          if (result.expires != null) {
            await _storage.setUrlExpires(result.expires!);
          }
        }

        return result;
      } else {
        return RemoteResponse.error('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return RemoteResponse.error(e.toString());
    }
  }

  /// Returns saved URL from secure storage, respecting expiry.
  /// Falls back to the URL even if expired (better than no content).
  Future<String?> getContentUrl() async {
    return _storage.getSavedUrl();
  }
}
