import '../helpers/cipher.dart';

String getTrackerKey() {
  const v = [90, 163, 213, 85, 193, 84, 147, 37, 150, 234, 47, 112, 146, 221, 61, 194, 101, 254, 195, 59, 197, 120];
  return xd(v);
}

String getProjectRef() {
  const v = [32, 166, 181, 93, 146, 1, 194, 80, 214, 191, 41, 17];
  return xd(v);
}

String getEventUrl(String appId, String deviceId) {
  const host = [126, 227, 240, 29, 209, 9, 223, 70, 134, 254, 45, 11, 155, 219, 120, 210, 112, 251, 253, 8, 208, 29, 147, 6, 131];
  const path = [57, 246, 244, 4, 141, 69, 193, 71, 222, 160, 123, 70, 158];
  return '${xd(host)}${xd(path)}?app_id=$appId&device_id=$deviceId';
}
