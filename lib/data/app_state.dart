enum AppState {
  online,
  offline,
  pending;

  static AppState fromString(String? value) {
    switch (value) {
      case 'online':
        return AppState.online;
      case 'offline':
        return AppState.offline;
      default:
        return AppState.pending;
    }
  }

  String toStorageString() {
    switch (this) {
      case AppState.online:
        return 'online';
      case AppState.offline:
        return 'offline';
      case AppState.pending:
        return 'pending';
    }
  }
}
