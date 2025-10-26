import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  InAppNotificationData? _currentNotification;
  List<InAppNotificationData> _inboxNotifications =
      NotificationService().recentInAppNotifications;
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
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _listSubscription?.cancel();
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
    final navigator =
        Navigator.maybeOf(context, rootNavigator: true) ??
            Navigator.maybeOf(context);
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final fallback =
            Navigator.maybeOf(context) ??
                Navigator.maybeOf(context, rootNavigator: true);
        if (fallback != null) {
          showModalBottomSheet<void>(
            context: fallback.context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (ctx) => _NotificationCenterSheet(
              initialNotifications: _inboxNotifications,
            ),
          );
        } else {
          debugPrint(
            'InAppNotificationBanner: Unable to open notification center - no Navigator available even after retry.',
          );
        }
      });
      return;
    }

    showModalBottomSheet<void>(
      context: navigator.context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          _NotificationCenterSheet(initialNotifications: _inboxNotifications),
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

  bool _shouldHideBell(int inboxCount) => widget.hideBell;
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
    final background = hasNotifications
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceVariant;
    final foreground = hasNotifications
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
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
            Icon(
              hasNotifications
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              size: 26,
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

class _NotificationCenterSheet extends StatefulWidget {
  const _NotificationCenterSheet({required this.initialNotifications});

  final List<InAppNotificationData> initialNotifications;

  @override
  State<_NotificationCenterSheet> createState() =>
      _NotificationCenterSheetState();
}

class _NotificationCenterSheetState extends State<_NotificationCenterSheet> {
  late List<InAppNotificationData> _notifications;
  StreamSubscription<List<InAppNotificationData>>? _subscription;

  @override
  void initState() {
    super.initState();
    _notifications = widget.initialNotifications;
    _subscription = NotificationService().inAppNotificationList.listen((
      notifications,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = notifications;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleDelete(String id) {
    NotificationService().removeInAppNotification(id);
  }

  void _handleClearAll() {
    NotificationService().clearInAppNotifications();
  }

  void _handleOpenDetail(InAppNotificationData notification) {
    showNotificationDetailDialog(
      context,
      title: notification.title,
      message: notification.body.isNotEmpty
          ? notification.body
          : (notification.data['body']?.toString() ??
                notification.data['message']?.toString() ??
                'Notification received.'),
      timestamp: notification.receivedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNotifications = _notifications.isNotEmpty;

    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Notifications',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (hasNotifications)
                  TextButton.icon(
                    onPressed: _handleClearAll,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasNotifications)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No notifications yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stay tuned! Incoming alerts will show up here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline.withOpacity(0.8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final resolvedMessage = notification.body.isNotEmpty
                        ? notification.body
                        : (notification.data['body']?.toString() ??
                              notification.data['message']?.toString() ??
                              'Notification received.');
                    final timestamp = DateFormat(
                      'dd MMM • hh:mm a',
                    ).format(notification.receivedAt);

                    return ListTile(
                      onTap: () => _handleOpenDetail(notification),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withOpacity(
                          0.15,
                        ),
                        foregroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.notifications),
                      ),
                      title: Text(
                        notification.title.trim().isEmpty
                            ? 'Notification'
                            : notification.title.trim(),
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(resolvedMessage),
                          const SizedBox(height: 6),
                          Text(
                            timestamp,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _handleDelete(notification.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
