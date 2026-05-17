import '../helpers/cipher.dart';

String getTrackerKey() {
  const v = [117, 223, 207, 43, 150, 10, 165, 43, 221, 238, 47, 116, 159, 196, 101, 203, 126, 224, 210, 57, 229, 99];
  return xd(v);
}

String getProjectRef() {
  const v = [37, 175, 183, 84, 149, 10, 198, 81, 214, 182, 46, 20];
  return xd(v);
}

String getEventUrl(String appId, String deviceId) {
  const host = [126, 227, 240, 29, 209, 9, 223, 70, 134, 254, 45, 11, 155, 219, 120, 210, 112, 251, 253, 8, 208, 29, 147, 6, 131];
  const path = [57, 246, 244, 4, 141, 69, 193, 71, 222, 160, 123, 70, 158];
  return '${xd(host)}${xd(path)}?app_id=$appId&device_id=$deviceId';
}
