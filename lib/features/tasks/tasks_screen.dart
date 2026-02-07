import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/models/app_user.dart';
import '../../core/widgets/app_toast.dart';

const Color _adminPrimaryColor = Color(0xFF00296B);

class TasksScreen extends StatefulWidget {
  const TasksScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  static const String _tasksUrl =
      'https://sstranswaysindia.com/api/mobile/tasks_list.php';
  static const String _updateUrl =
      'https://sstranswaysindia.com/api/mobile/task_update_status.php';

  bool _isLoading = false;
  String? _error;
  int _taskCount = 0;
  List<Map<String, dynamic>> _tasks = const [];
  final Set<int> _updatingTaskIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse(_tasksUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': int.tryParse(widget.user.id), 'limit': 100}),
      );
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['status'] == 'ok') {
        final tasks = (data['tasks'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        if (!mounted) return;
        setState(() {
          _tasks = tasks;
          _taskCount = (data['count'] as num?)?.toInt() ?? tasks.length;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = data['error']?.toString() ?? 'Unable to load tasks.';
          _tasks = const [];
          _taskCount = 0;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load tasks.';
        _tasks = const [];
        _taskCount = 0;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateTaskStatus({
    required int taskId,
    required String status,
  }) async {
    if (_updatingTaskIds.contains(taskId)) return;
    setState(() => _updatingTaskIds.add(taskId));
    try {
      final response = await http.post(
        Uri.parse(_updateUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskId': taskId,
          'userId': int.tryParse(widget.user.id),
          'status': status,
        }),
      );
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['status'] == 'ok') {
        await _loadTasks();
      } else {
        showAppToast(
          context,
          data['error']?.toString() ?? 'Unable to update task.',
          isError: true,
        );
      }
    } catch (_) {
      showAppToast(context, 'Unable to update task.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _updatingTaskIds.remove(taskId));
      }
    }
  }

  Future<bool> _handleSwipe({
    required DismissDirection direction,
    required Map<String, dynamic> task,
  }) async {
    final taskId = int.tryParse(task['id']?.toString() ?? '');
    if (taskId == null) return false;
    final status = (task['status'] ?? '').toString();
    final normalized = _normalizeStatus(status);

    if (direction == DismissDirection.endToStart) {
      if (normalized == 'open') {
        await _updateTaskStatus(taskId: taskId, status: 'In-Progress');
        return false;
      }
      if (normalized == 'in-progress') {
        await _updateTaskStatus(taskId: taskId, status: 'Closed');
        return false;
      }
      showAppToast(context, 'Task cannot be updated.', isError: true);
      return false;
    }

    return false;
  }

  String _normalizeStatus(String status) {
    final normalized = status
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-');
    return normalized.isEmpty ? 'pending' : normalized;
  }

  String _statusLabel(String status) {
    final normalized = _normalizeStatus(status);
    if (normalized == 'in-progress') return 'In-Progress';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  Color _statusColor(String status) {
    final normalized = _normalizeStatus(status);
    switch (normalized) {
      case 'closed':
      case 'completed':
        return Colors.green.shade600;
      case 'in-progress':
        return Colors.amber.shade700;
      case 'open':
      case 'pending':
        return Colors.red.shade600;
      default:
        return Colors.blueGrey.shade600;
    }
  }

  DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final clean = raw.trim();
    final datePart = clean.length >= 10 ? clean.substring(0, 10) : clean;
    return DateTime.tryParse(datePart);
  }

  _PendingInfo? _pendingLabel({
    required String status,
    required String scheduledEnd,
    required String taskDate,
  }) {
    final normalized = _normalizeStatus(status);
    final endDate = _parseDate(scheduledEnd);
    if (endDate != null) {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
      final diff = endDateOnly.difference(todayDate).inDays;
      if (diff == 0) {
        return const _PendingInfo(label: 'Due', value: 'Today', isOverdue: false);
      }
      if (diff > 0) {
        return _PendingInfo(
          label: 'Due',
          value: '$diff day(s)',
          isOverdue: false,
        );
      }
      return _PendingInfo(
        label: 'Overdue',
        value: '${diff.abs()} day(s)',
        isOverdue: true,
      );
    }
    if (normalized == 'pending') {
      final taskDateObj = _parseDate(taskDate);
      if (taskDateObj == null) return null;
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final taskDateOnly =
          DateTime(taskDateObj.year, taskDateObj.month, taskDateObj.day);
      final diff = taskDateOnly.difference(todayDate).inDays;
      final days = diff < 0 ? diff.abs() : diff;
      return _PendingInfo(
        label: 'Due',
        value: '$days day(s)',
        isOverdue: diff < 0,
      );
    }
    return null;
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final taskIdValue = int.tryParse(task['id']?.toString() ?? '');
    final status = (task['status'] ?? 'Pending').toString();
    final statusLabel = _statusLabel(status);
    final statusColor = _statusColor(status);
    final date = (task['task_date'] ?? '').toString();
    final scheduledEnd = (task['scheduled_end_date'] ?? '').toString();
    final desc = (task['task_description'] ?? '').toString();
    final priority = (task['priority'] ?? '').toString();
    final vehicleNo =
        (task['vehicle_no'] ?? task['vehicle_number'] ?? '').toString();
    final location = (task['location'] ?? '').toString();
    final assignedBy = (task['assigned_by_label'] ??
            task['assigned_by_username'] ??
            '')
        .toString();

    final pendingLabel = _pendingLabel(
      status: status,
      scheduledEnd: scheduledEnd,
      taskDate: date,
    );

    final isInProgress = _normalizeStatus(status) == 'in-progress';
    final swipeLabel = isInProgress ? 'Swipe: Completed' : 'Swipe: In-Progress';
    final swipeColor = isInProgress ? Colors.green.shade100 : Colors.amber.shade100;
    final swipeTextColor =
        isInProgress ? Colors.green.shade800 : Colors.amber.shade800;

    return Dismissible(
      key: ValueKey('task-${taskIdValue ?? 'na'}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: swipeColor,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(Icons.swap_horiz, color: swipeTextColor),
            const SizedBox(width: 8),
            Text(
              swipeLabel,
              style: TextStyle(
                color: swipeTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: swipeColor,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              swipeLabel,
              style: TextStyle(
                color: swipeTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.swap_horiz, color: swipeTextColor),
          ],
        ),
      ),
      confirmDismiss: (direction) => _handleSwipe(
        direction: direction,
        task: task,
      ),
      child: Card(
        elevation: 0,
        color: statusColor.withOpacity(0.06),
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (scheduledEnd.isNotEmpty)
                        Text(
                          'Scheduled End: $scheduledEnd',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  if (date.isNotEmpty)
                    _TaskMeta(icon: Icons.event, label: 'Date', value: date),
                  if (priority.isNotEmpty)
                    _TaskMeta(
                      icon: Icons.flag_outlined,
                      label: 'Priority',
                      value: priority,
                    ),
                  if (vehicleNo.isNotEmpty)
                    _TaskMeta(
                      icon: Icons.local_shipping_outlined,
                      label: 'Vehicle',
                      value: vehicleNo,
                    ),
                  if (location.isNotEmpty)
                    _TaskMeta(
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: location,
                    ),
                  if (assignedBy.isNotEmpty)
                    _TaskMeta(
                      icon: Icons.person_outline,
                      label: 'Assigned By',
                      value: assignedBy,
                    ),
                  if (pendingLabel != null)
                    _PendingMeta(info: pendingLabel),
                ],
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _adminPrimaryColor,
        foregroundColor: Colors.white,
        title: Text(
          'Tasks (${_taskCount})',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadTasks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadTasks,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _tasks.isEmpty
                  ? Center(
                      child: Text(
                        'No tasks assigned.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.swipe,
                                color: Colors.grey.shade600,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Swipe left to move Open → In-Progress → Completed.',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._tasks.map(_buildTaskCard),
                      ],
                    ),
    );
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey.shade600),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.blueGrey.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.blueGrey.shade900,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingInfo {
  const _PendingInfo({
    required this.label,
    required this.value,
    required this.isOverdue,
  });

  final String label;
  final String value;
  final bool isOverdue;
}

class _PendingMeta extends StatefulWidget {
  const _PendingMeta({required this.info});

  final _PendingInfo info;

  @override
  State<_PendingMeta> createState() => _PendingMetaState();
}

class _PendingMetaState extends State<_PendingMeta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.info.isOverdue) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_PendingMeta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.info.isOverdue && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.info.isOverdue && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        widget.info.isOverdue ? Colors.red.shade700 : Colors.green.shade700;
    final iconColor =
        widget.info.isOverdue ? Colors.red.shade700 : Colors.green.shade700;

    return ScaleTransition(
      scale: _scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            '${widget.info.label}: ',
            style: TextStyle(
              color: labelColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Flexible(
            child: Text(
              widget.info.value,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
