import 'dart:convert';
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

  Future<String?> getContentUrl() async {
    final savedUrl = await _storage.getSavedUrl();
    if (savedUrl != null && !_storage.isUrlExpired()) {
      return savedUrl;
    }
    return savedUrl;
  }
}
