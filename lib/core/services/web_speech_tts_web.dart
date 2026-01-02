import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Web speech synthesis wrapper using the browser SpeechSynthesis API.
class WebSpeechTts {
  String _language = 'hi-IN';
  double _rate = 0.8;

  bool get isSupported => html.window.speechSynthesis != null;

  Future<void> setLanguage(String language) async {
    _language = language.trim().isEmpty ? 'hi-IN' : language.trim();
  }

  Future<void> setRate(double rate) async {
    // Web Speech API typical range: 0.1..10.0
    _rate = rate.clamp(0.1, 2.0);
  }

  Future<void> speak(
    String text, {
    VoidCallback? onStart,
    VoidCallback? onComplete,
    void Function(String message)? onError,
  }) async {
    final synthesis = html.window.speechSynthesis;
    if (synthesis == null) {
      onError?.call('Speech synthesis is not available in this browser.');
      return;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      onComplete?.call();
      return;
    }

    synthesis.cancel();

    final utterance = html.SpeechSynthesisUtterance(trimmed)
      ..lang = _language
      ..rate = _rate;

    utterance.onStart.listen((_) => onStart?.call());
    utterance.onEnd.listen((_) => onComplete?.call());
    utterance.onError.listen((event) {
      onError?.call('Web TTS error.');
    });

    synthesis.speak(utterance);
  }

  Future<void> stop() async {
    html.window.speechSynthesis?.cancel();
  }
}
