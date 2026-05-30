import '../utils/codec.dart';

// ============================================================
// ANALYTICS INFO — Obfuscated AppsFlyer + Firebase credentials
// ============================================================
// All values here are XOR-encoded byte arrays.
// NEVER store plaintext API keys or project IDs as string literals.
//
// HOW TO GENERATE BYTE ARRAYS:
//   1. Fill in your plaintext values in tool/encode_keys.dart
//   2. Run: dart run tool/encode_keys.dart
//   3. Copy the printed arrays into the const lists below
//
// ⚠️ ALWAYS use `dart run`, never PowerShell foreach loops —
//    PowerShell overflows 32-bit integers on Windows, producing
//    wrong byte values. Symptom: HTTP 400 or auth errors.
// ============================================================

/// Returns the decoded AppsFlyer Dev Key.
/// Plaintext source: AppsFlyer dashboard → App Settings → Dev Key
/// TODO: Replace the byte array with your encoded key.
String resolveAnalyticsKey() {
  // TODO: Run tool/encode_keys.dart and paste the output array here.
  // Example placeholder (decodes to garbage — replace!):
  const v = <int>[];
  if (v.isEmpty) return '';
  return d(v);
}

/// Returns the decoded Firebase project number (sender ID).
/// Plaintext source: Firebase Console → Project Settings → General
///   → "Project number" (NOT the project ID string)
/// TODO: Replace the byte array with your encoded project number.
String resolveMessagingProject() {
  // TODO: Run tool/encode_keys.dart and paste the output array here.
  const v = <int>[];
  if (v.isEmpty) return '';
  return d(v);
}

/// Builds the GCD (Get Conversion Data) endpoint URL.
/// Used to retry attribution when AppsFlyer returns Organic on first call.
/// Format: https://gcdsdk.appsflyer.com/install_data/v4.0/{appId}?device_id={deviceId}
/// Auth header: Bearer {analyticsKey}
///
/// Plaintext source: https://dev.appsflyer.com/hc/reference/gcd-get-data
/// TODO: Encode the base host and path using tool/encode_keys.dart.
String resolveGcdEndpoint(String appId, String deviceId) {
  // TODO: Encode the GCD base URL using tool/encode_keys.dart.
  // Split into host and path arrays for extra obfuscation.
  const host = <int>[];
  const path = <int>[];
  if (host.isEmpty) return '';
  return '${d(host)}${d(path)}?app_id=$appId&device_id=$deviceId';
}
