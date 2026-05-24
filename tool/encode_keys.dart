// ignore_for_file: avoid_print
import 'dart:typed_data';

// ── Cipher (must match lib/helpers/cipher.dart exactly) ──────────────────────
const _seedBytes = [0x63, 0x68, 0x69, 0x63, 0x6B, 0x74, 0x72, 0x69, 0x70]; // "chicktrip"

Uint8List _buildKey() {
  final s = _seedBytes.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final kb = Uint8List(16);
  var v = s;
  for (var i = 0; i < kb.length; i++) {
    v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    kb[i] = v & 0xFF;
  }
  return kb;
}

final _bk = _buildKey();

List<int> encode(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i++) {
    out.add(s.codeUnitAt(i) ^ _bk[i % _bk.length]);
  }
  return out;
}

String decode(List<int> v) {
  final out = Uint8List(v.length);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] ^ _bk[i % _bk.length];
  }
  return String.fromCharCodes(out);
}

String fmt(List<int> v) => '[${v.join(', ')}]';

void main() {
  // ── Feather Run credentials ───────────────────────────────────────────────
  const configUrl    = 'https://feattherrun.com/config.php';
  const afKey        = 'bgtKJ6pajMN5NiamdwgGBW';
  const fbProjectNum = '598411811318';
  const privacyUrl   = 'https://feattherrun.com/privacy-policy.html';
  const supportUrl   = 'https://feattherrun.com/support.html';
  const gcdHost      = 'https://gcdsdk.appsflyer.com/install_data/v4.0/';

  final configHostParts = configUrl.split('/config.php');
  final configHost = configHostParts[0];
  final configPath = '/config.php';

  final hBytes  = encode(configHost);
  final pBytes  = encode(configPath);
  final afBytes = encode(afKey);
  final fbBytes = encode(fbProjectNum);
  final privBytes = encode(privacyUrl);
  final suppBytes = encode(supportUrl);
  final gcdBytes  = encode(gcdHost);

  print('══ BYTE ARRAYS ══');
  print('configHost : ${fmt(hBytes)}');
  print('configPath : ${fmt(pBytes)}');
  print('afKey      : ${fmt(afBytes)}');
  print('fbNumber   : ${fmt(fbBytes)}');
  print('privacyUrl : ${fmt(privBytes)}');
  print('supportUrl : ${fmt(suppBytes)}');
  print('gcdHost    : ${fmt(gcdBytes)}');

  print('\n══ VERIFY ══');
  print('configUrl  : ${decode(hBytes)}${decode(pBytes)}');
  print('afKey      : ${decode(afBytes)}');
  print('fbNumber   : ${decode(fbBytes)}');
  print('privacyUrl : ${decode(privBytes)}');
  print('supportUrl : ${decode(suppBytes)}');
  print('gcdHost    : ${decode(gcdBytes)}');
}
