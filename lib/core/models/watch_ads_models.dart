import 'package:intl/intl.dart';

class WatchAdsLimits {
  const WatchAdsLimits({
    required this.rewardAmount,
    required this.dailyViewLimit,
    required this.rewardedToday,
    required this.cooldownMinutes,
    this.nextAvailableAt,
  });

  factory WatchAdsLimits.fromJson(Map<String, dynamic> json) {
    final next = json['next_available_at'];
    DateTime? nextAvailable;
    if (next is String && next.isNotEmpty) {
      nextAvailable = DateTime.tryParse(next);
    }
    return WatchAdsLimits(
      rewardAmount: (json['reward_amount'] as num?)?.toDouble() ?? 0,
      dailyViewLimit: json['daily_view_limit'] is num
          ? (json['daily_view_limit'] as num).toInt()
          : 0,
      rewardedToday: json['rewarded_today'] is num
          ? (json['rewarded_today'] as num).toInt()
          : 0,
      cooldownMinutes: json['cooldown_minutes'] is num
          ? (json['cooldown_minutes'] as num).toInt()
          : 0,
      nextAvailableAt: nextAvailable,
    );
  }

  final double rewardAmount;
  final int dailyViewLimit;
  final int rewardedToday;
  final int cooldownMinutes;
  final DateTime? nextAvailableAt;

  int get remainingViews =>
      dailyViewLimit > rewardedToday ? dailyViewLimit - rewardedToday : 0;
}

class WatchAdsHistoryEntry {
  const WatchAdsHistoryEntry({
    required this.amount,
    required this.type,
    required this.createdAt,
    this.referenceId,
    this.note,
  });

  factory WatchAdsHistoryEntry.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    final raw = json['created_at'];
    if (raw is String && raw.isNotEmpty) {
      created = DateTime.tryParse(raw);
    }
    return WatchAdsHistoryEntry(
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: json['type']?.toString() ?? 'ad_reward',
      referenceId: json['reference_id'] == null
          ? null
          : int.tryParse(json['reference_id'].toString()),
      note: json['note']?.toString(),
      createdAt: created ?? DateTime.now(),
    );
  }

  final double amount;
  final String type;
  final int? referenceId;
  final String? note;
  final DateTime createdAt;

  String formatTimestamp() {
    final formatter = DateFormat('dd MMM • HH:mm');
    return formatter.format(createdAt.toLocal());
  }
}

class WatchAdsStatus {
  const WatchAdsStatus({
    required this.balance,
    required this.limits,
    required this.history,
  });

  factory WatchAdsStatus.fromJson(Map<String, dynamic> json) {
    final limits = WatchAdsLimits.fromJson(
      (json['limits'] as Map<String, dynamic>? ?? const {}),
    );
    final history = (json['history'] as List<dynamic>? ?? const [])
        .map((entry) => WatchAdsHistoryEntry.fromJson(
              entry as Map<String, dynamic>,
            ))
        .toList(growable: false);
    return WatchAdsStatus(
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      limits: limits,
      history: history,
    );
  }

  final double balance;
  final WatchAdsLimits limits;
  final List<WatchAdsHistoryEntry> history;

  bool get canWatch =>
      limits.remainingViews > 0 &&
      (limits.nextAvailableAt == null ||
          limits.nextAvailableAt!.isBefore(DateTime.now()));
}

class WatchAdsSession {
  const WatchAdsSession({
    required this.id,
    required this.token,
    required this.adNetwork,
    required this.rewardAmount,
  });

  factory WatchAdsSession.fromJson(Map<String, dynamic> json) {
    return WatchAdsSession(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      token: json['token']?.toString() ?? '',
      adNetwork: json['ad_network']?.toString() ?? 'admob',
      rewardAmount: (json['reward_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  final int id;
  final String token;
  final String adNetwork;
  final double rewardAmount;
}

class WatchAdsConfirmResult {
  const WatchAdsConfirmResult({
    required this.rewardAmount,
    required this.balance,
    required this.sessionId,
    this.duplicate = false,
  });

  factory WatchAdsConfirmResult.fromJson(Map<String, dynamic> json) {
    return WatchAdsConfirmResult(
      rewardAmount: (json['reward_amount'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      sessionId: json['session_id'] is num
          ? (json['session_id'] as num).toInt()
          : (json['session_id'] != null
              ? int.tryParse(json['session_id'].toString()) ?? 0
              : 0),
      duplicate: json['duplicate'] == true,
    );
  }

  final double rewardAmount;
  final double balance;
  final int sessionId;
  final bool duplicate;
}
