class TrainingProgress {
  const TrainingProgress({this.position = 0, this.completed = false});

  factory TrainingProgress.fromJson(Map<String, dynamic> json) {
    return TrainingProgress(
      position: int.tryParse(json['position']?.toString() ?? '') ?? 0,
      completed: json['completed'] == true || json['completed'] == 1,
    );
  }

  final int position;
  final bool completed;
}

class TrainingModule {
  const TrainingModule({
    required this.id,
    required this.code,
    required this.title,
    this.description,
    this.transcript,
    this.audioUrl,
    this.audioCandidates = const [],
    this.duration,
    this.sortOrder = 1,
    this.progress = const TrainingProgress(),
    this.locked = false,
  });

  factory TrainingModule.fromJson(Map<String, dynamic> json) {
    final progressRaw = json['progress'];
    final progress = progressRaw is Map<String, dynamic>
        ? TrainingProgress.fromJson(progressRaw)
        : const TrainingProgress();

    String? audioUrl = json['audioUrl']?.toString();
    if (audioUrl != null && audioUrl.isNotEmpty && !audioUrl.startsWith('http')) {
      if (!audioUrl.startsWith('/')) {
        audioUrl = '/$audioUrl';
      }
      audioUrl = 'https://sstranswaysindia.com' + audioUrl;
    }

    final audioCandidatesRaw = json['audioCandidates'];
    final candidates = <String>[];
    if (audioCandidatesRaw is List) {
      for (final entry in audioCandidatesRaw) {
        final str = entry?.toString() ?? '';
        if (str.isNotEmpty) candidates.add(str);
      }
    }
    if (audioUrl != null && audioUrl.isNotEmpty && !candidates.contains(audioUrl)) {
      candidates.insert(0, audioUrl);
    }

    return TrainingModule(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      transcript: json['transcript']?.toString(),
      audioUrl: audioUrl,
      audioCandidates: candidates,
      duration: int.tryParse(json['duration']?.toString() ?? '') ?? json['duration'] as int?,
      sortOrder: int.tryParse(json['sortOrder']?.toString() ?? '') ?? 1,
      progress: progress,
      locked: json['locked'] == true,
    );
  }

  final int id;
  final String code;
  final String title;
  final String? description;
  final String? transcript;
  final String? audioUrl;
  final List<String> audioCandidates;
  final int? duration;
  final int sortOrder;
  final TrainingProgress progress;
  final bool locked;
}
