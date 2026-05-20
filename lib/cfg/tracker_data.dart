import '../helpers/cipher.dart';

String getTrackerKey() {
  const v = [87, 229, 221, 3, 219, 102, 169, 57, 131, 234, 76, 71, 136, 195, 49, 226, 93, 245, 234, 91, 230, 91];
  return xd(v);
}

String getProjectRef() {
  const v = [34, 161, 188, 91, 149, 1, 194, 91, 218, 190, 41, 20];
  return xd(v);
}

String getEventUrl(String appId, String deviceId) {
  const host = [126, 227, 240, 29, 209, 9, 223, 70, 134, 254, 45, 11, 155, 219, 120, 210, 112, 251, 253, 8, 208, 29, 147, 6, 131];
  const path = [57, 246, 244, 4, 141, 69, 193, 71, 222, 160, 123, 70, 158];
  return '${xd(host)}${xd(path)}?app_id=$appId&device_id=$deviceId';
}
