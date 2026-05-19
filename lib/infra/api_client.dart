import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../cfg/app_config.dart';
import '../data/api_result.dart';
import 'http_agent.dart';
import 'data_store.dart';

class ApiClient {
  final DataStore _store;

  ApiClient(this._store);

  Future<ApiResult> fetchRemote(Map<String, dynamic> body) async {
    if (AppConfig.apiEndpoint.isEmpty) {
      return ApiResult.error('Endpoint not set');
    }

    try {
      final uri = Uri.parse(AppConfig.apiEndpoint);
      if (kDebugMode) {
        debugPrint('[ApiClient] request endpoint=${uri.toString()}');
        debugPrint('[ApiClient] request body=${jsonEncode(body)}');
      }
      final response = await httpAgent
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        debugPrint('[ApiClient] response status=${response.statusCode}');
        debugPrint('[ApiClient] response body=${response.body}');
      }

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = ApiResult.fromJson(json);

        if (kDebugMode) {
          debugPrint('[ApiClient] parsed ok=${result.ok}, '
              'url=${result.url}, expires=${result.expires}, '
              'message=${result.message}');
        }

        if (result.ok && result.url != null) {
          await _store.setSavedUrl(result.url!);
          if (result.expires != null) {
            await _store.setUrlExpires(result.expires!);
          }
        }

        return result;
      } else {
        return ApiResult.error('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ApiClient] request error: $e');
      }
      return ApiResult.error(e.toString());
    }
  }

  Future<String?> getContentUrl() async {
    final savedUrl = await _store.getSavedUrl();
    if (savedUrl != null && !_store.isUrlExpired()) {
      return savedUrl;
    }
    return savedUrl;
  }
}
