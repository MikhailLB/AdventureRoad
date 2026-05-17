class RemoteResponse {
  final bool ok;
  final String? url;
  final String? message;
  final int? expires;

  RemoteResponse({
    required this.ok,
    this.url,
    this.message,
    this.expires,
  });

  factory RemoteResponse.fromJson(Map<String, dynamic> json) {
    return RemoteResponse(
      ok: json['ok'] as bool? ?? false,
      url: json['url'] as String?,
      message: json['message'] as String?,
      expires: json['expires'] as int?,
    );
  }

  factory RemoteResponse.error(String message) {
    return RemoteResponse(ok: false, message: message);
  }
}
