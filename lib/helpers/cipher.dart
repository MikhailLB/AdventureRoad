import 'dart:typed_data';

/// ════════════════════════════════════════════════════════════
/// XOR Cipher — obfuscates sensitive strings in byte arrays
/// ════════════════════════════════════════════════════════════
///
/// ⚠️  TEMPLATE: Change _seedBytes to a unique value per app.
///
/// The seed drives a linear-congruential generator (LCG) that
/// produces a 16-byte repeating XOR key.  All byte arrays in
/// lib/cfg/ are encoded with this key — if you change the seed
/// you MUST re-encode every byte array using:
///
///   dart run tool/encode_keys.dart
///
/// RULES:
///   • Use 6–12 bytes.  Mix printable ASCII and raw bytes.
///   • Never commit the seed in comments — treat it as a secret.
///   • Use a different seed for each app in your portfolio.
///
/// CURRENT SEED (ASCII):  "chicktrip"
/// TODO: replace _seedBytes with your own seed before release.
Uint8List _buildKey() {
  // TODO: Change these bytes to your own app-specific seed.
  // Current value decodes to "chicktrip" — change before release!
  const seedBytes = [0x63, 0x68, 0x69, 0x63, 0x6B, 0x74, 0x72, 0x69, 0x70];
  final s = seedBytes.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final kb = Uint8List(16);
  var v = s;
  for (var i = 0; i < kb.length; i++) {
    v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    kb[i] = v & 0xFF;
  }
  return kb;
}

final _bk = _buildKey();

/// Decode [data] from an XOR-encoded byte array back to a String.
/// Use tool/encode_keys.dart to produce byte arrays for new strings.
String xd(List<int> data) {
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    out[i] = data[i] ^ _bk[i % _bk.length];
  }
  return String.fromCharCodes(out);
}
