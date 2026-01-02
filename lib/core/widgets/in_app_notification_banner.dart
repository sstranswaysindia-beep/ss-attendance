import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import '../services/notification_service.dart';

Future<void> showNotificationDetailDialog(
  BuildContext context, {
  String? title,
  required String message,
  DateTime? timestamp,
}) {
  final theme = Theme.of(context);
  final trimmedMessage = message.trim().isEmpty
      ? 'No message content.'
      : message;

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Text(
        title?.trim().isEmpty == true
            ? 'Notification'
            : title ?? 'Notification',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trimmedMessage),
          if (timestamp != null) ...[
            const SizedBox(height: 12),
            Text(
              DateFormat('dd MMM yyyy • hh:mm a').format(timestamp),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
      ],
    ),
  );
}

class InAppNotificationBannerHost extends StatefulWidget {
  const InAppNotificationBannerHost({
    required this.child,
    this.hideBell = false,
    super.key,
  });

  final Widget child;
  final bool hideBell;

  @override
  State<InAppNotificationBannerHost> createState() =>
      _InAppNotificationBannerHostState();
}

class _InAppNotificationBannerHostState
    extends State<InAppNotificationBannerHost> {
  StreamSubscription<InAppNotificationData>? _subscription;
  StreamSubscription<List<InAppNotificationData>>? _listSubscription;
  StreamSubscription<bool>? _bellVisibilitySubscription;
  InAppNotificationData? _currentNotification;
  List<InAppNotificationData> _inboxNotifications =
      NotificationService().recentInAppNotifications;
  bool _isBellForcedHidden = NotificationService().isBellHidden;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService().inAppNotifications.listen(
      _handleIncomingNotification,
    );
    _listSubscription = NotificationService().inAppNotificationList.listen((
      notifications,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inboxNotifications = notifications;
      });
    });
    _bellVisibilitySubscription = NotificationService().bellVisibilityChanges
        .listen((hidden) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isBellForcedHidden = hidden;
          });
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _listSubscription?.cancel();
    _bellVisibilitySubscription?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _handleIncomingNotification(InAppNotificationData notification) {
    _hideTimer?.cancel();
    setState(() => _currentNotification = notification);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _currentNotification = null);
      }
    });
    _showNotificationTicker(notification);
  }

  void _dismissBanner() {
    _hideTimer?.cancel();
    if (mounted) {
      setState(() => _currentNotification = null);
    }
  }

  void _handleTapBanner() {
    final notification = _currentNotification;
    if (notification == null) {
      return;
    }

    _dismissBanner();

    final fallbackMessage =
        notification.data['body']?.toString() ??
        notification.data['message']?.toString() ??
        'Notification received.';

    showNotificationDetailDialog(
      context,
      title: notification.title,
      message: notification.body.isNotEmpty
          ? notification.body
          : fallbackMessage,
      timestamp: notification.receivedAt,
    );
  }

  void _openNotificationCenter() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      NotificationService().clearInAppNotifications();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _inboxNotifications.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text('No notifications yet'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _inboxNotifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final n = _inboxNotifications[index];
                          final title = n.title.trim().isEmpty
                              ? 'Notification'
                              : n.title.trim();
                          final msg = n.body.trim().isNotEmpty
                              ? n.body.trim()
                              : (n.data['body']?.toString() ??
                                    n.data['message']?.toString() ??
                                    'Notification received.');
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              msg,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              onPressed: () {
                                NotificationService().removeInAppNotification(
                                  n.id,
                                );
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                            onTap: () {
                              showNotificationDetailDialog(
                                context,
                                title: title,
                                message: msg,
                                timestamp: n.receivedAt,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNotificationTicker([InAppNotificationData? notification]) {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) {
      return;
    }

    final notifications = notification != null
        ? [notification]
        : _inboxNotifications;

    if (notifications.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No notifications yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final preview = notifications
        .take(3)
        .map((entry) {
          final title = entry.title.trim().isNotEmpty
              ? entry.title.trim()
              : 'Notification';
          final message = entry.body.trim().isNotEmpty
              ? entry.body.trim()
              : (entry.data['body']?.toString() ??
                    entry.data['message']?.toString() ??
                    'Received');
          return '$title: $message';
        })
        .join('   •   ');

    scaffoldMessenger.clearSnackBars();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: 4 + (preview.length ~/ 20)),
        content: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = _currentNotification != null;
    final inboxCount = _inboxNotifications.length;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: IgnorePointer(
              ignoring: !isVisible,
              child: AnimatedSlide(
                offset: isVisible ? Offset.zero : const Offset(0, -1.1),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: isVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: isVisible
                      ? _InAppBannerCard(
                          notification: _currentNotification!,
                          onDismiss: _dismissBanner,
                          onTap: _handleTapBanner,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        if (!_shouldHideBell(inboxCount))
          Positioned(
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(right: 16, bottom: 16),
              child: _NotificationBellButton(
                count: inboxCount,
                onPressed: _openNotificationCenter,
              ),
            ),
          ),
      ],
    );
  }

  bool _shouldHideBell(int inboxCount) =>
      widget.hideBell || _isBellForcedHidden;
}

class _InAppBannerCard extends StatelessWidget {
  const _InAppBannerCard({
    required this.notification,
    required this.onDismiss,
    required this.onTap,
  });

  final InAppNotificationData notification;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final timestampLabel = DateFormat(
      'hh:mm a',
    ).format(notification.receivedAt);

    return Material(
      elevation: 8,
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.notifications_active,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notification.title.trim().isEmpty
                          ? 'Notification'
                          : notification.title.trim(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body.trim().isEmpty
                          ? (notification.data['body']?.toString() ??
                                notification.data['message']?.toString() ??
                                'Notification received.')
                          : notification.body.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface.withOpacity(0.85),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timestampLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                splashRadius: 20,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNotifications = count > 0;
    final background = Colors.white;
    final foreground = hasNotifications
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final badgeText = count > 99 ? '99+' : count.toString();

    return SizedBox(
      width: 62,
      height: 62,
      child: FloatingActionButton(
        heroTag: 'notification_inbox_fab',
        elevation: 8,
        backgroundColor: background,
        foregroundColor: foreground,
        shape: const CircleBorder(),
        onPressed: onPressed,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Lottie.asset(
                'assets/animations/notification.json',
                repeat: true,
              ),
            ),
            if (hasNotifications)
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
