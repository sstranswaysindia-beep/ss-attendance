import 'dart:async';

/// Simple global session events (currently only logout).
class SessionEventBus {
  static final StreamController<void> _logoutController =
      StreamController<void>.broadcast();

  static Stream<void> get onLogoutRequested => _logoutController.stream;

  static void requestLogout() {
    if (_logoutController.isClosed) return;
    _logoutController.add(null);
  }

  static Future<void> dispose() async {
    await _logoutController.close();
  }
}
