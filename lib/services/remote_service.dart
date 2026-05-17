import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../models/remote_response.dart';
import 'http_client.dart';
import 'storage_service.dart';

class RemoteService {
  final StorageService _storage;

  RemoteService(this._storage);

  Future<RemoteResponse> fetchRemote(Map<String, dynamic> body) async {
    if (AppSettings.apiEndpoint.isEmpty) {
      return RemoteResponse.error('Endpoint not set');
    }

    try {
      final uri = Uri.parse(AppSettings.apiEndpoint);
      if (kDebugMode) {
        debugPrint('[Config] request endpoint=${uri.toString()}');
        debugPrint('[Config] request body=${jsonEncode(body)}');
      }
      final response = await appHttpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        debugPrint('[Config] response status=${response.statusCode}');
        debugPrint('[Config] response body=${response.body}');
      }

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = RemoteResponse.fromJson(json);

        if (kDebugMode) {
          debugPrint('[Config] parsed ok=${result.ok}, '
              'url=${result.url}, expires=${result.expires}, '
              'message=${result.message}');
        }

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
      if (kDebugMode) {
        debugPrint('[Config] request error: $e');
      }
      return RemoteResponse.error(e.toString());
    }
  }

  Future<String?> getContentUrl() async {
    final savedUrl = await _storage.getSavedUrl();
    if (savedUrl != null && !_storage.isUrlExpired()) {
      return savedUrl;
    }
    return savedUrl;
  }
}
