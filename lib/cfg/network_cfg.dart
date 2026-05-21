import '../helpers/cipher.dart';

/// ════════════════════════════════════════════════════════════
/// ⚠️  TEMPLATE — encode your config endpoint URL
/// ════════════════════════════════════════════════════════════
///
/// HOW TO ENCODE:
///   1. Make sure lib/helpers/cipher.dart has YOUR seed bytes.
///   2. Run:  dart run tool/encode_keys.dart
///   3. Copy the printed byte array for your URL and paste below.
///
/// WHY: Prevents the URL from appearing in plaintext when the
/// binary is inspected with `strings` or a decompiler.
///
/// URL FORMAT:  https://yourdomain.com/config.php
/// The URL is split into host + path parts for extra obfuscation.
///
/// EXAMPLE (do NOT use these bytes — they are for illustration only):
///   const h = [0x00, 0x01, 0x02, ...];  // encoded host part
///   const p = [0x00, 0x01, ...];         // encoded path part
///   return xd(h) + xd(p);

// TODO: replace h and p with your own encoded byte arrays
String getBaseUrl() {
  // ⚠️ Placeholder — returns empty string, app will use offline mode
  const h = <int>[];
  const p = <int>[];
  if (h.isEmpty) return '';          // TODO: remove this guard after encoding
  return xd(h) + xd(p);
}
