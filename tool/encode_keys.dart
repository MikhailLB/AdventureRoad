// ignore_for_file: avoid_print
// ════════════════════════════════════════════════════════════
// Key Encoder — generates XOR byte arrays for lib/cfg/
// ════════════════════════════════════════════════════════════
///
/// USAGE:
///   dart run tool/encode_keys.dart
///
/// IMPORTANT: Run with Dart, NOT PowerShell scripts.
/// PowerShell truncates large integers (32-bit overflow), producing
/// wrong byte values that cause FormatException in HTTP headers.
///
/// After running, copy the printed arrays into the corresponding
/// lib/cfg/ files.
///
/// The seed in _saltBytes MUST match the seedBytes in
/// lib/helpers/cipher.dart exactly.
/// ════════════════════════════════════════════════════════════

import 'dart:typed_data';

// ⚠️  MUST match seedBytes in lib/helpers/cipher.dart
const _saltBytes = [0x63, 0x68, 0x69, 0x63, 0x6B, 0x74, 0x72, 0x69, 0x70];

// ── Key derivation (same LCG as cipher.dart) ────────────────
Uint8List _buildKey() {
  final s = _saltBytes.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final kb = Uint8List(16);
  var v = s;
  for (var i = 0; i < kb.length; i++) {
    v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    kb[i] = v & 0xFF;
  }
  return kb;
}

List<int> encode(String plaintext) {
  final key = _buildKey();
  final bytes = plaintext.codeUnits;
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    out.add(bytes[i] ^ key[i % key.length]);
  }
  return out;
}

String fmtBytes(List<int> bytes) =>
    '[${bytes.join(', ')}]';

void main() {
  // ════════════════════════════════════════════════════════
  // ⚠️  FILL IN YOUR ACTUAL VALUES BELOW
  // ════════════════════════════════════════════════════════

  // lib/cfg/network_cfg.dart — split URL at domain/path boundary
  // Example: 'https://yoursite.com' and '/config.php'
  const configHost = 'https://TODO_YOUR_DOMAIN.com';   // TODO
  const configPath = '/config.php';                     // TODO

  // lib/cfg/tracker_data.dart
  const appsflyerKey  = 'TODO_APPSFLYER_DEV_KEY';      // TODO
  const firebaseProj  = 'TODO_FIREBASE_PROJECT_NUMBER'; // TODO  (numeric string)

  // AppsFlyer GCD endpoint (do not change unless AF changes it)
  const gcdHost = 'https://gcdsdk.appsflyer.com';
  const gcdPath = '/install_data/v4.0/';

  // lib/infra/http_agent.dart — Chrome version fragment for User-Agent
  // Keep this close to the real current Chrome version
  const chromeFrag = '136.0.0.0';
  // WebKit version for Safari UA
  const webkitFrag = '605.1.15';

  // ════════════════════════════════════════════════════════

  print('// ── network_cfg.dart ───────────────────────────');
  print('const h = ${fmtBytes(encode(configHost))};');
  print('const p = ${fmtBytes(encode(configPath))};');
  print('');
  print('// ── tracker_data.dart — AppsFlyer dev key ──────');
  print('const v = ${fmtBytes(encode(appsflyerKey))};');
  print('');
  print('// ── tracker_data.dart — Firebase project number ');
  print('const v = ${fmtBytes(encode(firebaseProj))};');
  print('');
  print('// ── tracker_data.dart — GCD host ────────────────');
  print('const host = ${fmtBytes(encode(gcdHost))};');
  print('// ── tracker_data.dart — GCD path ────────────────');
  print('const path = ${fmtBytes(encode(gcdPath))};');
  print('');
  print('// ── http_agent.dart — Chrome version fragment ───');
  print('String get _fallbackCv => xd(const ${fmtBytes(encode(chromeFrag))});');
  print('');
  print('// ── http_agent.dart — WebKit version fragment ───');
  print('String get _sv => xd(const ${fmtBytes(encode(webkitFrag))});');

  // Verification
  print('');
  print('// ── VERIFICATION (decoded values) ───────────────');
  print('// configHost: ${configHost}');
  print('// configPath: ${configPath}');
  print('// appsflyerKey: ${appsflyerKey}');
  print('// firebaseProj: ${firebaseProj}');
}
