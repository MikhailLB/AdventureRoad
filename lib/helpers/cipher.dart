import 'dart:typed_data';

Uint8List _buildKey() {
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

String xd(List<int> data) {
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    out[i] = data[i] ^ _bk[i % _bk.length];
  }
  return String.fromCharCodes(out);
}
