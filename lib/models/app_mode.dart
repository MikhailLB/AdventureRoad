enum AppMode {
  online,
  offline,
  pending;

  static AppMode fromString(String? value) {
    switch (value) {
      case 'online':
        return AppMode.online;
      case 'offline':
        return AppMode.offline;
      default:
        return AppMode.pending;
    }
  }

  String toStorageString() {
    switch (this) {
      case AppMode.online:
        return 'online';
      case AppMode.offline:
        return 'offline';
      case AppMode.pending:
        return 'pending';
    }
  }
}
