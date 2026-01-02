import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/training_models.dart';
import '../../../core/services/safety_repository.dart';
import '../../../core/services/tts_language_helper.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/app_toast.dart';

class TrainingPlayerScreen extends StatefulWidget {
  const TrainingPlayerScreen({
    required this.user,
    required this.repository,
    required this.module,
    super.key,
  });

  final AppUser user;
  final SafetyRepository repository;
  final TrainingModule module;

  @override
  State<TrainingPlayerScreen> createState() => _TrainingPlayerScreenState();
}

class _TrainingPlayerScreenState extends State<TrainingPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AudioPlayer _player;

  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _loading = true;
  bool _completed = false;

  List<String> _audioSources = const [];
  bool _usingTts = false;

  FlutterTts? _tts;
  bool _ttsReady = false;
  bool _ttsPlaying = false;
  bool _ttsStarting = false;
  bool _ttsHindiMissing = false;
  String? _ttsSelectedLanguage;

  // highlight
  List<String> _ttsWords = const [];
  int _currentWordIndex = 0;

  // estimate (used only for UI)
  double _ttsWordsPerSecond = 0.6;

  final ScrollController _scrollController = ScrollController();

  Timer? _ttsPositionTimer;
  DateTime? _ttsStartTime;
  int _ttsStartWordIndex = 0;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  final RegExp _pauseRegex = RegExp(
    r'\[pause\]|\{pause\}|<pause>|pause_marker',
    caseSensitive: false,
  );

  final RegExp _imageRegex = RegExp(
    r'image\s*:\s*(https?://[^\s\n]+)',
    caseSensitive: false,
  );

  // TTS chunks
  final List<_TtsChunk> _ttsChunks = [];
  int _ttsChunkIndex = 0;
  bool _ttsChunkingActive = false;
  bool _hasStartedTtsOnce = false;

  // ✅ NEW: line anchors for accurate auto-scroll
  final List<_LineAnchor> _lineAnchors = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService().requestBellHide();

    _player = AudioPlayer();

    _tts = FlutterTts();
    _initTts();

    _init();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_ttsPlaying && _usingTts) {
        _stopTts();
      }
    }
  }

  bool _isLanguageMissing(String msg) {
    final m = msg.toLowerCase();
    // ✅ do NOT treat "-8" as language missing (engine can use -8 for other errors)
    return m.contains('not installed') ||
        m.contains('language data') ||
        m.contains('missing data') ||
        m.contains('no voice') ||
        m.contains('is not supported');
  }

  Future<void> _setKeepScreenOn(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> _initTts() async {
    if (_tts == null) return;

    try {
      await _tts!.awaitSpeakCompletion(true);

      try {
        await _tts!.setEngine("com.google.android.tts");
      } catch (_) {}

      final chosen = await TtsLanguageHelper.configureLanguage(
        _tts!,
        preferred: const ['hi-IN', 'hi'],
      );

      if (chosen == null) {
        if (!mounted) return;
        setState(() {
          _ttsReady = false;
          _ttsHindiMissing = true;
          _ttsSelectedLanguage = null;
          _ttsPlaying = false;
        });
        showAppToast(
          context,
          'Hindi TTS voice is not installed.\n\n'
          'Fix:\n'
          'Settings → Language & Input → Text-to-speech output\n'
          'Preferred engine: Speech Services by Google\n'
          'Install voice data: Hindi (India)',
          isError: true,
        );
        return;
      }

      _ttsSelectedLanguage = chosen;
      _ttsHindiMissing = false;

      await _tts!.setSpeechRate(0.38);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);

      _tts!.setStartHandler(() {
        if (!mounted) return;
        setState(() {
          _ttsPlaying = true;
          _ttsReady = true;
        });
      });

      // ✅ Completion: go next chunk, pause 3 seconds when needed
      _tts!.setCompletionHandler(() async {
        _stopTtsPositionTimer();
        if (!mounted) return;

        if (_ttsChunkingActive && _ttsChunkIndex < _ttsChunks.length - 1) {
          final finished = _ttsChunks[_ttsChunkIndex];

          setState(() {
            _ttsPlaying = false;
            _currentWordIndex = finished.endWordIndex.clamp(
              0,
              _ttsWords.length - 1,
            );
          });

          _scrollToCurrentWord(center: true);

          if (finished.pauseAfter) {
            await Future.delayed(const Duration(seconds: 3));
          }

          _ttsChunkIndex++;
          if (!mounted) return;
          await _speakCurrentChunk();
          return;
        }

        setState(() {
          _ttsPlaying = false;
          _completed = true;
        });

        await _setKeepScreenOn(false);
        await _saveTtsProgress(forceComplete: true);
      });

      _tts!.setErrorHandler((msg) async {
        debugPrint('TTS error: $msg');
        _stopTtsPositionTimer();
        if (!mounted) return;

        if (_isLanguageMissing(msg)) {
          setState(() {
            _ttsPlaying = false;
            _ttsReady = false;
            _ttsHindiMissing = true;
            _ttsStarting = false;
          });
          await _setKeepScreenOn(false);
          showAppToast(
            context,
            'Hindi voice data missing for ${_ttsSelectedLanguage ?? 'hi-IN'}.\n\n'
            'Install Hindi (India) voice in phone TTS settings (Google TTS).',
            isError: true,
          );
          return;
        }

        setState(() {
          _ttsPlaying = false;
          _ttsStarting = false;
        });

        try {
          await _tts?.stop();
        } catch (_) {}

        if (_ttsChunkingActive && _ttsChunks.isNotEmpty) {
          showAppToast(context, 'TTS engine error. Retrying…', isError: false);
          await _speakCurrentChunk();
          return;
        }

        await _setKeepScreenOn(false);
        showAppToast(context, 'TTS error: $msg', isError: true);
      });

      // Highlight updates
      _tts!.setProgressHandler((String text, int start, int end, String? word) {
        if (!_ttsPlaying || _ttsWords.isEmpty) return;

        final normalized = _normalizeWord(word ?? '');
        if (normalized.isEmpty) return;

        final found = _findWordIndexImproved(normalized);
        if (found != null && found != _currentWordIndex) {
          setState(() {
            _currentWordIndex = found;
            _ttsStartWordIndex = found;
            _ttsStartTime = DateTime.now();
            final secs = (_currentWordIndex / _ttsWordsPerSecond).floor();
            _position = Duration(seconds: secs);
          });

          // ✅ Accurate auto scroll
          _scrollToCurrentWord(center: true);
        }
      });

      if (!mounted) return;
      setState(() => _ttsReady = true);
    } catch (e) {
      debugPrint('TTS init failed: $e');
      if (!mounted) return;
      setState(() {
        _ttsReady = false;
        _ttsPlaying = false;
        _ttsStarting = false;
      });
    }
  }

  Future<void> _init() async {
    _usingTts = true;
    _audioSources = const [];
    _prepareTtsTranscript();
    if (mounted) setState(() => _loading = false);
  }

  // ✅ NEW: line-by-line parsing -> pause on [pause] OR paragraph breaks (blank lines)
  void _prepareTtsTranscript() {
    final transcript = widget.module.transcript ?? '';
    _ttsChunks.clear();
    _lineAnchors.clear();

    if (transcript.trim().isEmpty) {
      _ttsWords = const [];
      _currentWordIndex = 0;
      _duration = Duration.zero;
      _position = Duration.zero;
      _ttsChunkIndex = 0;
      _ttsChunkingActive = false;
      return;
    }

    // remove image lines entirely
    final rawLines = transcript.split('\n');
    final filtered = <String>[];
    for (final l in rawLines) {
      if (_imageRegex.hasMatch(l.trim())) continue;
      filtered.add(l);
    }

    // Build words + chunks + anchors
    final allWords = <String>[];
    int cursor = 0;
    int anchorIndex = 0;

    for (int i = 0; i < filtered.length; i++) {
      final raw = filtered[i];
      final trimmedRight = raw.trimRight();
      final trimmed = trimmedRight.trim();

      // blank line => paragraph boundary => pause after previous chunk
      if (trimmed.isEmpty) {
        if (_ttsChunks.isNotEmpty) {
          _ttsChunks[_ttsChunks.length - 1] = _ttsChunks.last.copyWith(
            pauseAfter: true,
          );
        }
        continue;
      }

      final hasPause = _pauseRegex.hasMatch(trimmedRight);

      // Speech text: strip pause markers + bullets + markup
      final speechLine = _sanitizeLineForTts(
        trimmedRight.replaceAll(_pauseRegex, ' '),
      );

      // If the line is only [pause], speechLine becomes empty -> treat as paragraph pause
      if (speechLine.trim().isEmpty) {
        if (_ttsChunks.isNotEmpty) {
          _ttsChunks[_ttsChunks.length - 1] = _ttsChunks.last.copyWith(
            pauseAfter: true,
          );
        }
        continue;
      }

      final words = speechLine
          .split(RegExp(r'\s+'))
          .where((w) => w.trim().isNotEmpty)
          .toList();

      if (words.isEmpty) continue;

      final start = cursor;
      final end = cursor + words.length - 1;

      allWords.addAll(words);
      cursor += words.length;

      // paragraph break if next line is blank
      final nextIsBlank =
          (i + 1 < filtered.length) && (filtered[i + 1].trim().isEmpty);

      final pauseAfter = hasPause || nextIsBlank;

      _ttsChunks.add(_TtsChunk(words.join(' '), start, end, pauseAfter));

      // line anchor for accurate scroll (matches word ranges)
      _lineAnchors.add(
        _LineAnchor(
          key: GlobalKey(debugLabel: 'line_$anchorIndex'),
          startWord: start,
          endWord: end,
        ),
      );
      anchorIndex++;
    }

    _ttsWords = allWords;

    final savedSeconds = widget.module.progress.position;
    if (_ttsWords.isNotEmpty && _ttsWordsPerSecond > 0) {
      _currentWordIndex = (savedSeconds * _ttsWordsPerSecond).floor().clamp(
        0,
        _ttsWords.length - 1,
      );
    } else {
      _currentWordIndex = 0;
    }

    final estimatedSeconds = (_ttsWordsPerSecond > 0)
        ? (_ttsWords.length / _ttsWordsPerSecond)
        : _ttsWords.length.toDouble();

    _duration = Duration(seconds: estimatedSeconds.ceil());
    _position = Duration(seconds: savedSeconds);

    _buildChunksFromWord(_currentWordIndex);
  }

  void _buildChunksFromWord(int fromWordIndex) {
    if (_ttsChunks.isEmpty || _ttsWords.isEmpty) return;

    final idx = fromWordIndex.clamp(0, _ttsWords.length - 1);

    int segIndex = 0;
    for (int i = 0; i < _ttsChunks.length; i++) {
      final s = _ttsChunks[i];
      if (idx >= s.startWordIndex && idx <= s.endWordIndex) {
        segIndex = i;
        break;
      }
    }

    final playback = <_TtsChunk>[];

    final first = _ttsChunks[segIndex];
    final offset = idx - first.startWordIndex;

    final firstWords = _ttsWords
        .sublist(first.startWordIndex + offset, first.endWordIndex + 1)
        .join(' ')
        .trim();

    if (firstWords.isNotEmpty) {
      playback.add(
        _TtsChunk(firstWords, idx, first.endWordIndex, first.pauseAfter),
      );
    }

    for (int i = segIndex + 1; i < _ttsChunks.length; i++) {
      playback.add(_ttsChunks[i]);
    }

    _ttsChunks
      ..clear()
      ..addAll(playback);

    _ttsChunkIndex = 0;
    _ttsChunkingActive = true;
  }

  Future<void> _speakCurrentChunk() async {
    if (_tts == null) return;
    if (_ttsChunks.isEmpty) return;
    if (_ttsChunkIndex < 0 || _ttsChunkIndex >= _ttsChunks.length) return;

    final chunk = _ttsChunks[_ttsChunkIndex];

    if (mounted) {
      setState(() {
        _currentWordIndex = chunk.startWordIndex.clamp(0, _ttsWords.length - 1);
        _ttsPlaying = true;
        _ttsStarting = false;
      });
    }

    _scrollToCurrentWord(center: true);

    final res = await _tts!.speak(chunk.text);
    if (!mounted) return;

    if (res == 1 || res == 0) {
      _startTtsPositionTimer();
    } else {
      setState(() {
        _ttsPlaying = false;
        _ttsStarting = false;
      });
      await _setKeepScreenOn(false);
      showAppToast(context, 'Unable to start TTS', isError: true);
    }
  }

  String _normalizeWord(String raw) {
    return raw
        .replaceAll(
          RegExp(r'<[^>]+>', multiLine: true, caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
        .toLowerCase()
        .trim();
  }

  String _sanitizeLineForTts(String line) {
    var cleaned = line;
    cleaned = cleaned.replaceAll(
      RegExp(r'<[^>]+>', multiLine: true, caseSensitive: false),
      '',
    );
    // remove bullets and weird markers (prevents “pause at ●” effect)
    cleaned = cleaned.replaceAll(RegExp(r'[●•▪◦■]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _stripPauseMarkers(String text) {
    return text
        .replaceAll(_pauseRegex, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int? _findWordIndexImproved(String normalizedWord) {
    if (normalizedWord.isEmpty || _ttsWords.isEmpty) return null;

    final start = _currentWordIndex.clamp(0, _ttsWords.length - 1);
    final limit = (start + 12).clamp(0, _ttsWords.length - 1);

    for (int i = start; i <= limit; i++) {
      final w = _normalizeWord(_ttsWords[i]);
      if (w == normalizedWord) return i;
    }

    final backStart = (start - 6).clamp(0, _ttsWords.length - 1);
    for (int i = backStart; i < start; i++) {
      final w = _normalizeWord(_ttsWords[i]);
      if (w == normalizedWord) return i;
    }

    return null;
  }

  void _startTtsPositionTimer() {
    _ttsPositionTimer?.cancel();
    if (!_ttsPlaying || _ttsWords.isEmpty) return;

    _ttsStartTime = DateTime.now();
    _ttsStartWordIndex = _currentWordIndex;

    _ttsPositionTimer = Timer.periodic(const Duration(milliseconds: 140), (
      timer,
    ) {
      if (!_ttsPlaying || _ttsWords.isEmpty) {
        timer.cancel();
        return;
      }

      if (_ttsStartTime != null) {
        final elapsed = DateTime.now().difference(_ttsStartTime!);
        final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
        final wordsElapsed = (elapsedSeconds * _ttsWordsPerSecond).floor();
        final newIndex = (_ttsStartWordIndex + wordsElapsed).clamp(
          0,
          _ttsWords.length - 1,
        );

        if (newIndex != _currentWordIndex) {
          setState(() {
            _currentWordIndex = newIndex;
            _position = Duration(
              seconds: (_currentWordIndex / _ttsWordsPerSecond).floor(),
            );
          });

          _scrollToCurrentWord(center: true);
        }
      }
    });
  }

  void _stopTtsPositionTimer() {
    _ttsPositionTimer?.cancel();
    _ttsPositionTimer = null;
  }

  Future<void> _saveTtsProgress({bool forceComplete = false}) async {
    final durationSec = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (_ttsWords.length / _ttsWordsPerSecond).ceil();
    final positionSec = (_currentWordIndex / _ttsWordsPerSecond).floor();
    final completed =
        forceComplete ||
        (_ttsWords.isNotEmpty && _currentWordIndex >= _ttsWords.length - 1);
    if (completed) _completed = true;

    try {
      await widget.repository.saveTrainingProgress(
        moduleId: widget.module.id,
        positionSeconds: positionSec,
        durationSeconds: durationSec,
        completed: completed,
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _position = Duration(seconds: positionSec);
        if (durationSec > 0) _duration = Duration(seconds: durationSec);
      });
    }
  }

  bool get _isNearCompletion {
    if (_completed) return true;
    if (_ttsWords.isNotEmpty &&
        _currentWordIndex >= (_ttsWords.length * 0.95).floor()) {
      return true;
    }
    return false;
  }

  // ✅ Accurate scroll using line anchors
  void _scrollToCurrentWord({required bool center}) {
    if (!_scrollController.hasClients) return;
    if (_lineAnchors.isEmpty) return;
    if (_ttsWords.isEmpty) return;

    final idx = _currentWordIndex.clamp(0, _ttsWords.length - 1);

    _LineAnchor? anchor;
    for (final a in _lineAnchors) {
      if (idx >= a.startWord && idx <= a.endWord) {
        anchor = a;
        break;
      }
    }
    if (anchor == null) return;

    final ctx = anchor.key.currentContext;
    if (ctx == null) return;

    // Keep near middle
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: center ? 0.45 : 0.25,
    );
  }

  Widget _buildTimeEstimate() {
    final totalWords = _ttsWords.length;
    if (totalWords == 0) return const SizedBox.shrink();

    final totalSeconds = (_ttsWordsPerSecond > 0)
        ? (totalWords / _ttsWordsPerSecond).ceil()
        : totalWords;
    final totalDuration = Duration(seconds: totalSeconds);

    final remainingWords = totalWords - _currentWordIndex;
    final remainingSeconds = (_ttsWordsPerSecond > 0)
        ? (remainingWords / _ttsWordsPerSecond).ceil()
        : remainingWords;
    final remainingDuration = Duration(seconds: remainingSeconds);

    String formatDuration(Duration d) {
      final minutes = d.inMinutes;
      final seconds = d.inSeconds % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.access_time, size: 13, color: Colors.black54),
        const SizedBox(width: 4),
        Text(
          '${formatDuration(remainingDuration)} / ${formatDuration(totalDuration)}',
          style: GoogleFonts.josefinSans(
            fontSize: 11.5,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Seek: only left (rewind) when NOT playing
  Widget _buildTtsSeekBar() {
    final totalWords = _ttsWords.length;
    if (totalWords <= 1) return const SizedBox.shrink();

    final current = _currentWordIndex.clamp(0, totalWords - 1);

    return Slider(
      value: current.toDouble(),
      min: 0,
      max: (totalWords - 1).toDouble(),
      activeColor: const Color(0xFF12355B),
      inactiveColor: const Color(0xFF12355B).withOpacity(0.18),
      onChanged: _ttsPlaying
          ? null
          : (value) {
              final newIndex = value.round().clamp(0, totalWords - 1);
              if (newIndex > _currentWordIndex) return; // block forward
              setState(() => _currentWordIndex = newIndex);
              _scrollToCurrentWord(center: true);
            },
      onChangeEnd: _ttsPlaying
          ? null
          : (value) async {
              final newIndex = value.round().clamp(0, totalWords - 1);
              if (newIndex > _currentWordIndex) return;

              await _tts?.stop();
              _stopTtsPositionTimer();

              setState(() => _currentWordIndex = newIndex);
              _buildChunksFromWord(_currentWordIndex);
            },
    );
  }

  Future<void> _startTts({required bool restartFromTop}) async {
    final transcript = widget.module.transcript ?? '';
    if (transcript.trim().isEmpty) {
      showAppToast(context, 'Transcript not available', isError: true);
      return;
    }
    if (_tts == null) {
      showAppToast(context, 'TTS unavailable on this device', isError: true);
      return;
    }

    if (_ttsStarting) return;
    _ttsStarting = true;

    if (!_ttsReady) {
      await _initTts();
      if (!_ttsReady) {
        _ttsStarting = false;
        return;
      }
    }
    if (_ttsHindiMissing) {
      _ttsStarting = false;
      return;
    }

    await _setKeepScreenOn(true);

    await _tts?.stop();
    _stopTtsPositionTimer();

    if (restartFromTop) {
      setState(() => _currentWordIndex = 0);
      _buildChunksFromWord(0);
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) _scrollController.jumpTo(0);
        });
      }
    } else {
      _buildChunksFromWord(_currentWordIndex);
    }

    if (_ttsChunks.isEmpty) {
      _ttsStarting = false;
      showAppToast(context, 'Nothing to read', isError: true);
      await _setKeepScreenOn(false);
      return;
    }

    _ttsChunkIndex = 0;
    _ttsChunkingActive = true;
    _hasStartedTtsOnce = true;

    await _speakCurrentChunk();
  }

  Future<void> _stopTts() async {
    try {
      await _tts?.stop();
    } catch (_) {}
    _stopTtsPositionTimer();

    if (mounted) {
      setState(() {
        _ttsPlaying = false;
        _ttsStarting = false;
      });
    }

    await _setKeepScreenOn(false);
    _saveTtsProgress();
  }

  Future<void> _markCompleteAndExit() async {
    try {
      await _stopTts();
      await _saveTtsProgress(forceComplete: true);
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService().releaseBellHide();

    _stopTts();
    _positionSub?.cancel();
    _player.dispose();
    _scrollController.dispose();
    _glowController.dispose();

    _tts = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppGradientBackground(
      child: WillPopScope(
        onWillPop: () async {
          if (_usingTts) {
            await _stopTts(); // stop audio + release wakelock
            await _saveTtsProgress(); // save latest word index
          }
          return true;
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: const Color(0xFF12355B),
            foregroundColor: Colors.white,
            elevation: 0,

            // ✅ IMPORTANT: appbar back also stop + save
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () async {
                if (_usingTts) {
                  await _stopTts();
                  await _saveTtsProgress();
                }
                if (mounted) Navigator.of(context).pop(true);
              },
            ),

            title: Text(
              widget.module.title,
              style: GoogleFonts.josefinSans(
                textStyle: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _buildPlayerCard(),
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          physics: const BouncingScrollPhysics(),
                          child: _buildTranscriptText(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_isNearCompletion)
                        _GlowingNextTrainingButton(
                          glowAnimation: _glowAnimation,
                          onPressed: _markCompleteAndExit,
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard() {
    final totalWords = _ttsWords.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C7ED6).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.record_voice_over,
                  color: Color(0xFF1C7ED6),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hindi Training',
                  style: GoogleFonts.josefinSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _ttsPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 30,
                  color: _ttsHindiMissing
                      ? Colors.grey
                      : const Color(0xFF1C7ED6),
                ),
                onPressed: _ttsHindiMissing
                    ? () {
                        showAppToast(
                          context,
                          'Install Hindi (India) voice in phone TTS settings (Google TTS).',
                          isError: true,
                        );
                      }
                    : (_ttsPlaying
                          ? () async => _stopTts()
                          : () async {
                              // ✅ resume if we have progress, otherwise start from top
                              final shouldResume =
                                  _hasStartedTtsOnce && _currentWordIndex > 0;
                              await _startTts(restartFromTop: !shouldResume);
                            }),
              ),
            ],
          ),

          if (totalWords > 0) ...[
            const SizedBox(height: 2),
            _buildTimeEstimate(),
            const SizedBox(height: 0),
            // ✅ tighter slider height
            SizedBox(height: 22, child: _buildTtsSeekBar()),
          ],

          if (_ttsHindiMissing) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hindi voice missing. Install Hindi (India) voice in phone settings.',
                style: GoogleFonts.josefinSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTranscriptText() {
    final transcript = widget.module.transcript ?? 'Transcript not available';
    final lines = transcript.split('\n');

    final widgets = <Widget>[];
    int wordCursor = 0;
    bool headerRendered = false;
    int anchorPtr = 0; // ✅ assign keys in same order

    TextStyle baseStyle(bool highlight, {bool bold = false}) =>
        GoogleFonts.josefinSans(
          fontSize: 16,
          height: 1.42,
          fontWeight: highlight
              ? FontWeight.w800
              : (bold ? FontWeight.w700 : FontWeight.w400),
          color: highlight ? const Color(0xFF1C7ED6) : Colors.black87,
          backgroundColor: highlight
              ? const Color(0x332077D6)
              : Colors.transparent,
        );

    List<InlineSpan> buildWordSpans(String text, {bool bold = false}) {
      final cleaned = _sanitizeLineForTts(text.replaceAll(_pauseRegex, ' '));
      final words = cleaned
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      final spans = <InlineSpan>[];
      for (var i = 0; i < words.length; i++) {
        final globalIndex = _ttsWords.isEmpty ? -1 : wordCursor + i;
        final isCurrent = _ttsWords.isEmpty
            ? false
            : globalIndex == _currentWordIndex;

        spans.add(
          TextSpan(
            text: '${words[i]} ',
            style: baseStyle(isCurrent, bold: bold),
          ),
        );
      }

      wordCursor += words.length;
      return spans;
    }

    List<InlineSpan> buildSpansWithMarkup(String line) {
      line = line.replaceAll(_pauseRegex, ' ');

      final spans = <InlineSpan>[];
      final tagRegex = RegExp(
        r'<(b|i|u)>(.*?)</\1>',
        caseSensitive: false,
        dotAll: true,
      );

      int last = 0;
      for (final match in tagRegex.allMatches(line)) {
        if (match.start > last) {
          spans.addAll(buildWordSpans(line.substring(last, match.start)));
        }

        final tag = match.group(1)?.toLowerCase();
        final inner = match.group(2) ?? '';

        TextStyle styleOverride(TextStyle base) {
          switch (tag) {
            case 'b':
              return base.copyWith(fontWeight: FontWeight.w700);
            case 'i':
              return base.copyWith(fontStyle: FontStyle.italic);
            case 'u':
              return base.copyWith(decoration: TextDecoration.underline);
            default:
              return base;
          }
        }

        final cleanedInner = _sanitizeLineForTts(inner);
        final words = cleanedInner
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();

        for (var i = 0; i < words.length; i++) {
          final globalIndex = _ttsWords.isEmpty ? -1 : wordCursor + i;
          final isCurrent = _ttsWords.isEmpty
              ? false
              : globalIndex == _currentWordIndex;

          spans.add(
            TextSpan(
              text: '${words[i]} ',
              style: styleOverride(baseStyle(isCurrent)),
            ),
          );
        }

        wordCursor += words.length;
        last = match.end;
      }

      if (last < line.length) {
        spans.addAll(buildWordSpans(line.substring(last)));
      }

      return spans;
    }

    int countWords(String text) {
      final cleaned = _sanitizeLineForTts(text.replaceAll(_pauseRegex, ' '));
      return cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (_imageRegex.hasMatch(trimmed)) {
        final imageMatch = _imageRegex.firstMatch(trimmed);
        final url = imageMatch?.group(1)?.trim() ?? '';
        if (url.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: const Color(0xFFE9ECEF),
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(),
                  ),
                  errorWidget: (context, url, error) {
                    return GestureDetector(
                      onTap: () => launchUrlString(
                        url,
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Container(
                        height: 200,
                        color: const Color(0xFFE9ECEF),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.broken_image,
                              size: 48,
                              color: Colors.black54,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Image not available\nTap to open in browser',
                              style: GoogleFonts.josefinSans(
                                color: Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  httpHeaders: const {'Accept': 'image/*'},
                ),
              ),
            ),
          );
          widgets.add(const SizedBox(height: 8));
        }
        continue;
      }

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // header line
      if (!headerRendered && !trimmed.startsWith('●')) {
        wordCursor += countWords(line);
        final displayHeader = _stripPauseMarkers(trimmed);

        final key = (anchorPtr < _lineAnchors.length)
            ? _lineAnchors[anchorPtr++].key
            : null;

        widgets.add(
          Padding(
            key: key,
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              displayHeader,
              style: GoogleFonts.josefinSans(
                fontSize: 20,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ),
        );
        headerRendered = true;
        continue;
      }

      final isBullet = trimmed.startsWith('●');
      final content = isBullet
          ? trimmed.replaceFirst('●', '').trimLeft()
          : trimmed;

      final key = (anchorPtr < _lineAnchors.length)
          ? _lineAnchors[anchorPtr++].key
          : null;

      if (isBullet) {
        widgets.add(
          Padding(
            key: key,
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6.5, right: 6),
                  child: Text('•', style: TextStyle(fontSize: 16, height: 1.2)),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(children: buildSpansWithMarkup(content)),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            key: key,
            padding: const EdgeInsets.only(bottom: 10),
            child: RichText(
              text: TextSpan(children: buildSpansWithMarkup(content)),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class _TtsChunk {
  _TtsChunk(this.text, this.startWordIndex, this.endWordIndex, this.pauseAfter);

  final String text;
  final int startWordIndex;
  final int endWordIndex;
  final bool pauseAfter;

  _TtsChunk copyWith({bool? pauseAfter}) {
    return _TtsChunk(
      text,
      startWordIndex,
      endWordIndex,
      pauseAfter ?? this.pauseAfter,
    );
  }
}

class _LineAnchor {
  _LineAnchor({
    required this.key,
    required this.startWord,
    required this.endWord,
  });
  final GlobalKey key;
  final int startWord;
  final int endWord;
}

class _GlowingNextTrainingButton extends StatelessWidget {
  const _GlowingNextTrainingButton({
    required this.glowAnimation,
    required this.onPressed,
  });

  final Animation<double> glowAnimation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF2F9E44,
                ).withOpacity(glowAnimation.value * 0.6),
                blurRadius: 20 + (glowAnimation.value * 15),
                spreadRadius: 2 + (glowAnimation.value * 3),
              ),
              BoxShadow(
                color: const Color(
                  0xFF2F9E44,
                ).withOpacity(glowAnimation.value * 0.4),
                blurRadius: 30 + (glowAnimation.value * 20),
                spreadRadius: 1 + (glowAnimation.value * 2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F9E44),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4 + (glowAnimation.value * 2),
            ),
            icon: const Icon(Icons.check_circle, color: Colors.white),
            label: Text(
              'Next Training',
              style: GoogleFonts.josefinSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            onPressed: onPressed,
          ),
        );
      },
    );
  }
}
