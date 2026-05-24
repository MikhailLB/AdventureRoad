import '../helpers/cipher.dart';

String getTrackerKey() {
  const v = [116, 240, 240, 38, 232, 5, 128, 8, 132, 194, 82, 16, 180, 194, 105, 204, 114, 224, 227, 42, 224, 100];
  return xd(v);
}

String getProjectRef() {
  const v = [35, 174, 188, 89, 147, 2, 200, 88, 223, 188, 45, 29];
  return xd(v);
}
