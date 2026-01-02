import 'package:flutter/foundation.dart';

/// Web speech synthesis wrapper (stub for non-web platforms).
class WebSpeechTts {
  bool get isSupported => false;

  Future<void> setLanguage(String language) async {}

  Future<void> setRate(double rate) async {}

  Future<void> speak(
    String text, {
    VoidCallback? onStart,
    VoidCallback? onComplete,
    void Function(String message)? onError,
  }) async {
    onError?.call('Web speech is not supported on this platform.');
  }

  Future<void> stop() async {}
}
