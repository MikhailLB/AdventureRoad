import '../helpers/cipher.dart';

/// ════════════════════════════════════════════════════════════
/// ⚠️  TEMPLATE — encode your AppsFlyer & Firebase credentials
/// ════════════════════════════════════════════════════════════
///
/// HOW TO ENCODE:
///   Run:  dart run tool/encode_keys.dart
///   Then paste the printed byte arrays below.
///
/// getTrackerKey()   → AppsFlyer Dev Key
///                     Dashboard: appsflyer.com → App Settings → Dev Key
///                     Looks like: "HGNdz9XMHJpFih6eHdMDFL"
///
/// getProjectRef()   → Firebase Project Number (NOT project ID string)
///                     google-services.json → "project_number": "123456789"
///                     OR Firebase console → Project Settings → General
///
/// getEventUrl()     → AppsFlyer Get Conversion Data (GCD) endpoint
///                     Used for organic-install attribution retry.
///                     Format: https://gcdsdk.appsflyer.com/install_data/v4.0/{appid}?app_id={}&device_id={}
///                     host part = "https://gcdsdk.appsflyer.com"
///                     path part = "/install_data/v4.0/"

// TODO: replace v with your encoded AppsFlyer dev key bytes
String getTrackerKey() {
  const v = <int>[];             // ⚠️ Placeholder
  if (v.isEmpty) return '';      // TODO: remove after encoding
  return xd(v);
}

// TODO: replace v with your encoded Firebase project number bytes
String getProjectRef() {
  const v = <int>[];             // ⚠️ Placeholder
  if (v.isEmpty) return '';      // TODO: remove after encoding
  return xd(v);
}

// TODO: replace host/path with your encoded GCD endpoint bytes
String getEventUrl(String appId, String deviceId) {
  const host = <int>[];          // ⚠️ Placeholder
  const path = <int>[];          // ⚠️ Placeholder
  if (host.isEmpty) return '';   // TODO: remove after encoding
  return '${xd(host)}${xd(path)}?app_id=$appId&device_id=$deviceId';
}
