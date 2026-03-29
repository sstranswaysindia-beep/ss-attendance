import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import '../../features/attendance/check_in_out_screen.dart';
import '../services/auth_storage_service.dart';
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
  List<InAppNotificationData> _inboxNotifications =
      NotificationService().recentInAppNotifications;
  bool _isBellForcedHidden = NotificationService().isBellHidden;
  bool _isPreviewOpen = false;
  bool _isDialogVisible = false;
  final List<InAppNotificationData> _dialogQueue = [];

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
    super.dispose();
  }

  void _handleIncomingNotification(InAppNotificationData notification) {
    _enqueueInstantDialog(notification);
  }

  Future<void> _toggleNotificationCenter() async {
    final shouldOpen = !_isPreviewOpen;
    if (shouldOpen) {
      await NotificationService().syncInboxFromServer();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isPreviewOpen = shouldOpen;
    });
  }

  void _enqueueInstantDialog(InAppNotificationData notification) {
    _dialogQueue.add(notification);
    if (!_isDialogVisible) {
      _showNextDialog();
    }
  }

  Future<void> _showNextDialog() async {
    if (!mounted || _isDialogVisible || _dialogQueue.isEmpty) {
      return;
    }

    final notification = _dialogQueue.removeAt(0);
    _isDialogVisible = true;
    final title = notification.title.trim().isEmpty
        ? 'New Notification'
        : notification.title.trim();
    final message = notification.body.trim().isNotEmpty
        ? notification.body.trim()
        : (notification.data['body']?.toString() ??
              notification.data['message']?.toString() ??
              'Notification received.');

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notification dialog',
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, __) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _InstantNotificationDialog(
                notification: notification,
                title: title,
                message: message,
                onClose: () => Navigator.of(dialogContext).pop(),
                onOpenInbox: () {
                  Navigator.of(dialogContext).pop();
                  if (mounted) {
                    setState(() => _isPreviewOpen = true);
                  }
                },
                onRemove: () {
                  NotificationService().removeInAppNotification(
                    notification.id,
                  );
                  Navigator.of(dialogContext).pop();
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    _isDialogVisible = false;
    if (_dialogQueue.isNotEmpty) {
      _showNextDialog();
    }
  }

  void _openNotificationDetails(InAppNotificationData n) {
    final title = n.title.trim().isEmpty ? 'Notification' : n.title.trim();
    final msg = n.body.trim().isNotEmpty
        ? n.body.trim()
        : (n.data['body']?.toString() ??
              n.data['message']?.toString() ??
              'Notification received.');
    showNotificationDetailDialog(
      context,
      title: title,
      message: msg,
      timestamp: n.receivedAt,
    );
  }

  bool _isAttendanceReminder(InAppNotificationData notification) {
    final type = notification.data['type']?.toString().toLowerCase() ?? '';
    final action = notification.data['action']?.toString().toLowerCase() ?? '';
    final title = notification.title.toLowerCase();
    final body = notification.body.toLowerCase();
    return type == 'attendance' ||
        action.contains('checkin') ||
        action.contains('checkout') ||
        title.contains('attendance reminder') ||
        body.contains('check in') ||
        body.contains('check-in') ||
        body.contains('check out') ||
        body.contains('check-out');
  }

  Future<void> _handleNotificationTap(
    InAppNotificationData notification,
  ) async {
    if (!_isAttendanceReminder(notification)) {
      _openNotificationDetails(notification);
      return;
    }

    if (mounted && _isPreviewOpen) {
      setState(() => _isPreviewOpen = false);
    }

    final user = await AuthStorageService.getUser();
    if (!mounted || user == null) {
      _openNotificationDetails(notification);
      return;
    }

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CheckInOutScreen(
          user: user,
          availableVehicles: user.availableVehicles,
        ),
      ),
    );
  }

  void _clearNotificationCenter() {
    NotificationService().clearInAppNotifications();
    if (mounted) {
      setState(() => _isPreviewOpen = false);
    }
  }

  void _removeNotification(String id) {
    NotificationService().removeInAppNotification(id);
    if (_inboxNotifications.length <= 1 && mounted) {
      setState(() => _isPreviewOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inboxCount = _inboxNotifications.length;

    return Stack(
      children: [
        widget.child,
        if (_isPreviewOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _isPreviewOpen = false),
              child: Container(color: Colors.black.withValues(alpha: 0.12)),
            ),
          ),
        if (!_shouldHideBell(inboxCount))
          Positioned(
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(right: 16, bottom: 92),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isPreviewOpen
                        ? Padding(
                            key: const ValueKey('preview_panel'),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _NotificationPreviewPanel(
                              notifications: _inboxNotifications,
                              onClear: _clearNotificationCenter,
                              onRemove: _removeNotification,
                              onTap: (n) {
                                setState(() => _isPreviewOpen = false);
                                unawaited(_handleNotificationTap(n));
                              },
                              onClose: () =>
                                  setState(() => _isPreviewOpen = false),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('preview_empty')),
                  ),
                  _NotificationBellButton(
                    count: inboxCount,
                    isActive: _isPreviewOpen,
                    onPressed: () {
                      unawaited(_toggleNotificationCenter());
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  bool _shouldHideBell(int inboxCount) =>
      widget.hideBell || _isBellForcedHidden;
}

class _InstantNotificationDialog extends StatelessWidget {
  const _InstantNotificationDialog({
    required this.notification,
    required this.title,
    required this.message,
    required this.onClose,
    required this.onOpenInbox,
    required this.onRemove,
  });

  final InAppNotificationData notification;
  final String title;
  final String message;
  final VoidCallback onClose;
  final VoidCallback onOpenInbox;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FBFF),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x330D1B2A),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F4C81), Color(0xFF2196F3)],
                      ),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New notification',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF4B6584),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          DateFormat(
                            'dd MMM yyyy • hh:mm a',
                          ).format(notification.receivedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B7A90),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF10233D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF425466),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpenInbox,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('View all'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Floating Preview Panel ────────────────────────────────────────────────

class _NotificationPreviewPanel extends StatefulWidget {
  const _NotificationPreviewPanel({
    required this.notifications,
    required this.onClear,
    required this.onRemove,
    required this.onTap,
    required this.onClose,
  });

  final List<InAppNotificationData> notifications;
  final VoidCallback onClear;
  final ValueChanged<String> onRemove;
  final ValueChanged<InAppNotificationData> onTap;
  final VoidCallback onClose;

  @override
  State<_NotificationPreviewPanel> createState() =>
      _NotificationPreviewPanelState();
}

class _NotificationPreviewPanelState extends State<_NotificationPreviewPanel> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompactMobile = screenWidth <= 500;
    final maxWidth = screenWidth > 500 ? 380.0 : screenWidth - 32;
    final count = widget.notifications.length;
    final maxPanelHeight = isCompactMobile
        ? (screenHeight * 0.68).clamp(420.0, 600.0)
        : 760.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: maxWidth,
        constraints: BoxConstraints(maxHeight: maxPanelHeight),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCE7F5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x290D1B2A),
              blurRadius: 28,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                isCompactMobile ? 12 : 16,
                10,
                isCompactMobile ? 8 : 10,
              ),
              child: Row(
                children: [
                  Container(
                    width: isCompactMobile ? 36 : 40,
                    height: isCompactMobile ? 36 : 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F4C81), Color(0xFF2196F3)],
                      ),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notification Center',
                          style: TextStyle(
                            fontSize: isCompactMobile ? 16 : 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF10233D),
                          ),
                        ),
                        Text(
                          count == 0
                              ? 'You are up to date'
                              : '$count item${count == 1 ? '' : 's'} in inbox',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF66788A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    _ClearAllButton(onPressed: widget.onClear),
                  ],
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: const Color(0xFFDCE7F5)),
            if (count > 0)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  isCompactMobile ? 8 : 10,
                  16,
                  0,
                ),
                child: Row(
                  children: [
                    Text(
                      'Tap to open. Swipe left to remove.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF73839A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: count == 0
                  ? const _EmptyNotificationState()
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        isCompactMobile ? 10 : 12,
                        14,
                        isCompactMobile ? 10 : 14,
                      ),
                      shrinkWrap: true,
                      itemCount: count,
                      itemBuilder: (context, index) {
                        final n = widget.notifications[index];
                        return _NotificationItemCard(
                          notification: n,
                          isFirst: index == 0,
                          onTap: () => widget.onTap(n),
                          onDismiss: () => widget.onRemove(n.id),
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

// ── Clear All Button ──────────────────────────────────────────────────────

class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFD9534F).withValues(alpha: 0.24),
            ),
            color: const Color(0xFFD9534F).withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_sweep_rounded,
                size: 16,
                color: const Color(0xFFD9534F).withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFD9534F).withValues(alpha: 0.9),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────

class _EmptyNotificationState extends StatelessWidget {
  const _EmptyNotificationState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF42A5F5).withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Icon(
              Icons.notifications_off_rounded,
              size: 48,
              color: const Color(0xFF9EB1C8),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF425466),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'You\'re all caught up! New notifications\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF73839A),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual Notification Card ───────────────────────────────────────────

class _NotificationItemCard extends StatelessWidget {
  const _NotificationItemCard({
    required this.notification,
    required this.isFirst,
    required this.onTap,
    required this.onDismiss,
  });

  final InAppNotificationData notification;
  final bool isFirst;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  IconData _resolveIcon() {
    final titleLower = notification.title.toLowerCase();
    final bodyLower = notification.body.toLowerCase();
    final combined = '$titleLower $bodyLower';
    if (combined.contains('attend')) {
      return Icons.access_time_rounded;
    }
    if (combined.contains('salary') ||
        combined.contains('advance') ||
        combined.contains('credit')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (combined.contains('trip') || combined.contains('vehicle')) {
      return Icons.local_shipping_rounded;
    }
    if (combined.contains('leave')) {
      return Icons.beach_access_rounded;
    }
    if (combined.contains('safety') || combined.contains('training')) {
      return Icons.shield_rounded;
    }
    if (combined.contains('approval') ||
        combined.contains('approved') ||
        combined.contains('reject')) {
      return Icons.task_alt_rounded;
    }
    return Icons.notifications_rounded;
  }

  Color _resolveAccent() {
    final titleLower = notification.title.toLowerCase();
    final bodyLower = notification.body.toLowerCase();
    final combined = '$titleLower $bodyLower';
    if (combined.contains('reject') ||
        combined.contains('error') ||
        combined.contains('fail')) {
      return const Color(0xFFEF5350);
    }
    if (combined.contains('approved') ||
        combined.contains('success') ||
        combined.contains('credit')) {
      return const Color(0xFF66BB6A);
    }
    if (combined.contains('pending') || combined.contains('warning')) {
      return const Color(0xFFFFCA28);
    }
    return const Color(0xFF42A5F5);
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final title = notification.title.trim().isEmpty
        ? 'Notification'
        : notification.title.trim();
    final msg = notification.body.trim().isNotEmpty
        ? notification.body.trim()
        : (notification.data['body']?.toString() ??
              notification.data['message']?.toString() ??
              'Notification received.');
    final accentColor = _resolveAccent();
    final icon = _resolveIcon();
    final timestamp = _formatTimestamp(notification.receivedAt);

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFD9534F).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_rounded,
          color: Color(0xFFD9534F),
          size: 24,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFirst
                  ? accentColor.withValues(alpha: 0.28)
                  : const Color(0xFFE3ECF5),
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: isFirst ? 0.10 : 0.04),
                blurRadius: isFirst ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Accent icon
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.12),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10233D),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Timestamp pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F5FB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              timestamp,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF6F8097),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        msg,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: const Color(0xFF596B80),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (isFirst) ...[
                            Icon(
                              Icons.swipe_left_rounded,
                              size: 12,
                              color: const Color(0xFF9AAABD),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Swipe to dismiss',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF9AAABD),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          if (isFirst) const Spacer(),
                          if (!isFirst) const Spacer(),
                          Text(
                            DateFormat(
                              'dd MMM yyyy • hh:mm a',
                            ).format(notification.receivedAt),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7A8CA5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bell FAB (with Lottie animation) ──────────────────────────────────────

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({
    required this.count,
    required this.onPressed,
    this.isActive = false,
  });

  final int count;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompactMobile = MediaQuery.of(context).size.width <= 500;
    final hasNotifications = count > 0;
    final background = isActive ? const Color(0xFF0F4C81) : Colors.white;
    final foreground = hasNotifications
        ? (isActive ? Colors.white : theme.colorScheme.primary)
        : (isActive ? Colors.white : theme.colorScheme.outline);
    final badgeText = count > 99 ? '99+' : count.toString();
    final buttonSize = isCompactMobile ? 54.0 : 62.0;
    final animationSize = isCompactMobile ? 36.0 : 42.0;
    final badgeRight = isCompactMobile ? -2.0 : -4.0;
    final badgeTop = isCompactMobile ? -4.0 : -6.0;

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: FloatingActionButton(
        heroTag: 'notification_inbox_fab',
        elevation: isActive ? 16 : 8,
        backgroundColor: background,
        foregroundColor: foreground,
        shape: const CircleBorder(),
        onPressed: onPressed,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: animationSize,
              height: animationSize,
              child: Lottie.asset(
                'assets/animations/notification.json',
                repeat: true,
              ),
            ),
            if (hasNotifications)
              Positioned(
                right: badgeRight,
                top: badgeTop,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompactMobile ? 5 : 6,
                    vertical: isCompactMobile ? 1.5 : 2,
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
