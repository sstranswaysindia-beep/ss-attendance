import 'package:flutter_tts/flutter_tts.dart';

class TtsLanguageHelper {
  static bool _isAvailableFlag(dynamic value) {
    return value == true || value == 1 || value == '1';
  }

  static String _normalizeLocale(String raw) {
    return raw.trim().replaceAll('_', '-').toLowerCase();
  }

  static Iterable<String> _variants(String locale) sync* {
    final trimmed = locale.trim();
    if (trimmed.isEmpty) return;
    yield trimmed;
    if (trimmed.contains('-')) yield trimmed.replaceAll('-', '_');
    if (trimmed.contains('_')) yield trimmed.replaceAll('_', '-');
  }

  static bool _isHindiLocale(String raw) {
    final n = _normalizeLocale(raw);
    return n == 'hi' || n.startsWith('hi-');
  }

  static bool _isExactHindiIndia(String raw) {
    final n = _normalizeLocale(raw);
    return n == 'hi-in';
  }

  /// Hindi-first selection for Android.
  /// Returns locale selected (e.g. "hi-IN") or null if no Hindi voice/lang is installed.
  static Future<String?> configure(
    FlutterTts tts, {
    List<String> preferred = const ['hi-IN', 'hi'],
  }) async {
    // 1) Prefer an installed VOICE (most reliable)
    try {
      final rawVoices = await tts.getVoices;
      if (rawVoices is List) {
        final voices = rawVoices
            .whereType<Map>()
            .map((m) => m.cast<dynamic, dynamic>())
            .toList(growable: false);

        String? getLocale(Map<dynamic, dynamic> v) =>
            v['locale']?.toString() ??
            v['language']?.toString() ??
            v['lang']?.toString();

        String? getName(Map<dynamic, dynamic> v) =>
            v['name']?.toString() ?? v['voice']?.toString();

        final hindiVoices = voices
            .where((v) {
              final loc = getLocale(v);
              return loc != null && _isHindiLocale(loc);
            })
            .toList(growable: false);

        if (hindiVoices.isNotEmpty) {
          final chosen = hindiVoices.firstWhere((v) {
            final loc = getLocale(v);
            return loc != null && _isExactHindiIndia(loc);
          }, orElse: () => hindiVoices.first);

          final chosenLoc = getLocale(chosen);
          final chosenName = getName(chosen);

          if (chosenLoc != null && chosenLoc.trim().isNotEmpty) {
            // Best: setVoice
            try {
              if (chosenName != null && chosenName.trim().isNotEmpty) {
                await tts.setVoice({'name': chosenName, 'locale': chosenLoc});
                return chosenLoc;
              }
            } catch (_) {}

            // Fallback: setLanguage
            try {
              await tts.setLanguage(chosenLoc);
              return chosenLoc;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 2) Locale-based selection via isLanguageAvailable (Hindi only)
    final tried = <String>{};

    for (final pref in preferred) {
      for (final candidate in _variants(pref)) {
        final key = _normalizeLocale(candidate);
        if (!tried.add(key)) continue;
        if (!_isHindiLocale(candidate)) continue;

        try {
          final availability = await tts.isLanguageAvailable(candidate);
          if (!_isAvailableFlag(availability)) continue;
          await tts.setLanguage(candidate);
          return candidate;
        } catch (_) {}
      }
    }

    // 3) Fallback: pick any installed Hindi language
    List<String> installed = const [];
    try {
      final raw = await tts.getLanguages;
      if (raw is List) {
        installed = raw
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      installed = const [];
    }

    if (installed.isEmpty) return null;

    final hiIn = installed.firstWhere(
      (l) => _isExactHindiIndia(l),
      orElse: () => '',
    );
    if (hiIn.isNotEmpty) {
      try {
        await tts.setLanguage(hiIn);
        return hiIn;
      } catch (_) {}
    }

    final anyHi = installed.firstWhere(
      (l) => _isHindiLocale(l),
      orElse: () => '',
    );
    if (anyHi.isNotEmpty) {
      try {
        await tts.setLanguage(anyHi);
        return anyHi;
      } catch (_) {}
    }

    return null;
  }

  static Future<String?> configureLanguage(
    FlutterTts tts, {
    List<String> preferred = const ['hi-IN', 'hi'],
  }) {
    return configure(tts, preferred: preferred);
  }
}
