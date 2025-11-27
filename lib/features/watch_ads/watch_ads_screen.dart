import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/watch_ads_models.dart';
import '../../core/services/watch_ads_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/services/rewarded_ad_manager.dart';

class WatchAdsScreen extends StatefulWidget {
  const WatchAdsScreen({
    required this.user,
    super.key,
  });

  final AppUser user;

  @override
  State<WatchAdsScreen> createState() => _WatchAdsScreenState();
}

class _WatchAdsScreenState extends State<WatchAdsScreen> {
  late final WatchAdsRepository _repository;
  late final RewardedAdManager _adManager;

  WatchAdsStatus? _status;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isWatching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = WatchAdsRepository(currentUser: widget.user);
    _adManager = RewardedAdManager();
    _loadStatus();
  }

  Future<void> _loadStatus({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _error = null;
      });
    }
    try {
      final status = await _repository.fetchStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _handleWatchPressed() async {
    final status = _status;
    if (status == null || _isWatching) return;

    setState(() {
      _isWatching = true;
      _error = null;
    });

    try {
      final session = await _repository.startSession();
      await _adManager.showRewardedAd(
        onRewarded: () async {
          final result = await _repository.confirmSession(
            sessionToken: session.token,
          );
          if (!mounted) return;
          showAppToast(
            context,
            result.duplicate
                ? 'Reward already credited earlier.'
                : 'Reward added: ₹${result.rewardAmount.toStringAsFixed(2)}',
          );
          await _loadStatus(silent: true);
        },
        onError: (message) {
          if (!mounted) return;
          showAppToast(context, message, isError: true);
          setState(() {
            _error = message;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, error.toString(), isError: true);
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isWatching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: theme.colorScheme.primary,
        title: const Text('Watch Ads & Earn'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : status == null
              ? _ErrorState(
                  message: _error ?? 'Unable to load reward status',
                  onRetry: () => _loadStatus(),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadStatus(silent: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      _SummaryCard(status: status),
                      const SizedBox(height: 16),
                      _WatchButton(
                        canWatch: status.canWatch,
                        isBusy: _isWatching,
                        limits: status.limits,
                        onPressed: _handleWatchPressed,
                      ),
                      if (_error != null && !_isWatching) ...[
                        const SizedBox(height: 12),
                        _WarningBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Recent rewards',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (status.history.isEmpty)
                        const _EmptyHistory()
                      else
                        ...status.history
                            .map((entry) => _HistoryTile(entry: entry)),
                      if (_isRefreshing) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.status});

  final WatchAdsStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limits = status.limits;
    final nextAvailable = limits.nextAvailableAt;
    final formatter = DateFormat('dd MMM • HH:mm');
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A5AE0), Color(0xFF1FB8D1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x216A5AE0),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current balance',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '₹${status.balance.toStringAsFixed(2)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryChip(
                    title: 'Reward per ad',
                    value: '₹${limits.rewardAmount.toStringAsFixed(2)}',
                    icon: Icons.monetization_on_outlined,
                    onDarkBackground: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryChip(
                    title: 'Remaining today',
                    value: limits.hasUnlimitedViews
                        ? '∞'
                        : '${limits.remainingViews}',
                    icon: Icons.timelapse_outlined,
                    color: limits.remainingViews > 0
                        ? Colors.white.withOpacity(0.18)
                        : const Color(0x33FFB74D),
                    iconColor: limits.remainingViews > 0
                        ? Colors.white
                        : const Color(0xFFFFF3E0),
                    onDarkBackground: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (nextAvailable != null)
              Row(
                children: [
                  Icon(
                    Icons.watch_later_outlined,
                    size: 18,
                    color: Colors.white.withOpacity(0.85),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextAvailable.isAfter(DateTime.now())
                          ? 'Next ad available at ${formatter.format(nextAvailable.toLocal())}'
                          : 'You can watch another ad now.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.iconColor,
    this.onDarkBackground = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final Color? iconColor;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor =
        onDarkBackground ? Colors.white : theme.colorScheme.onSurface;
    final subtitleColor = onDarkBackground
        ? Colors.white.withOpacity(0.72)
        : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ??
            (onDarkBackground
                ? Colors.white.withOpacity(0.15)
                : theme.colorScheme.surfaceVariant.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: iconColor ??
                (onDarkBackground
                    ? Colors.white
                    : theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: subtitleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WatchButton extends StatelessWidget {
  const _WatchButton({
    required this.canWatch,
    required this.isBusy,
    required this.onPressed,
    required this.limits,
  });

  final bool canWatch;
  final bool isBusy;
  final VoidCallback onPressed;
  final WatchAdsLimits limits;

  @override
  Widget build(BuildContext context) {
    final isDisabled = !canWatch || isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    colors: [
                      Color(0xFFFF8A80),
                      Color(0xFFFF6E7F),
                      Color(0xFFFF4081),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isDisabled ? Colors.grey.shade300 : null,
            boxShadow: isDisabled
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x33FF6E7F),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: isDisabled ? null : onPressed,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBusy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    else
                      Icon(
                        Icons.play_circle_fill_rounded,
                        color:
                            isDisabled ? Colors.grey.shade600 : Colors.white,
                        size: 22,
                      ),
                    const SizedBox(width: 10),
                    Text(
                      isBusy
                          ? 'Preparing...'
                          : canWatch
                              ? 'Watch Ad & Earn'
                              : 'Limit reached',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDisabled
                                ? Colors.grey.shade600
                                : Colors.white,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          limits.hasUnlimitedViews
              ? 'You can watch unlimited ads today. '
                'Cooldown: ${limits.cooldownMinutes} minute(s) between ads.'
              : 'You can watch up to ${limits.dailyViewLimit} ads per day. '
                'Cooldown: ${limits.cooldownMinutes} minute(s) between ads.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final WatchAdsHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = entry.type == 'ad_reward'
        ? const Color(0xFFFF6E7F)
        : theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shadowColor: Colors.transparent,
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white,
          border: Border.all(color: accentColor.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.85),
                  accentColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              entry.type == 'ad_reward'
                  ? Icons.play_circle_fill
                  : Icons.receipt_long,
              color: Colors.white,
            ),
          ),
          title: Text(
            '₹${entry.amount.toStringAsFixed(2)} • ${entry.type.replaceAll('_', ' ')}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.formatTimestamp(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (entry.note != null && entry.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  entry.note!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          trailing: entry.referenceId != null
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#${entry.referenceId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFFFF9F9),
        border: Border.all(color: const Color(0xFFFFCDD2).withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFEBEE),
            ),
            child: const Icon(
              Icons.emoji_objects_outlined,
              color: Color(0xFFFF6E7F),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'No rewards recorded yet. Watch your first ad to start earning!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFAD1457),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
