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
      appBar: AppBar(
        title: const Text('Watch Ads & Earn'),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current balance',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '₹${status.balance.toStringAsFixed(2)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
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
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryChip(
                    title: 'Remaining today',
                    value: '${limits.remainingViews}',
                    icon: Icons.timelapse_outlined,
                    color: limits.remainingViews > 0
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    iconColor: limits.remainingViews > 0
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
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
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextAvailable.isAfter(DateTime.now())
                          ? 'Next ad available at ${formatter.format(nextAvailable.toLocal())}'
                          : 'You can watch another ad now.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
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
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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
        ElevatedButton.icon(
          onPressed: isDisabled ? null : onPressed,
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_circle_outline),
          label: Text(
            isBusy
                ? 'Preparing...'
                : canWatch
                    ? 'Watch Ad & Earn'
                    : 'Limit reached',
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You can watch up to ${limits.dailyViewLimit} ads per day. '
          'Cooldown: ${limits.cooldownMinutes} minutes between ads.',
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
          child: Icon(
            entry.type == 'ad_reward'
                ? Icons.play_circle_fill
                : Icons.receipt_long,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          '₹${entry.amount.toStringAsFixed(2)} • ${entry.type.replaceAll('_', ' ')}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.formatTimestamp()),
            if (entry.note != null && entry.note!.isNotEmpty)
              Text(entry.note!),
          ],
        ),
        trailing: entry.referenceId != null
            ? Text(
                '#${entry.referenceId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            : null,
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'No rewards recorded yet. Watch your first ad to start earning!',
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
