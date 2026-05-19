class ApiResult {
  final bool ok;
  final String? url;
  final String? message;
  final int? expires;

  ApiResult({
    required this.ok,
    this.url,
    this.message,
    this.expires,
  });

  factory ApiResult.fromJson(Map<String, dynamic> json) {
    return ApiResult(
      ok: json['ok'] as bool? ?? false,
      url: json['url'] as String?,
      message: json['message'] as String?,
      expires: json['expires'] as int?,
    );
  }

  factory ApiResult.error(String message) {
    return ApiResult(ok: false, message: message);
  }
}
