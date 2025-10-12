import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late DateTime _selectedMonth;
  String _statusFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  bool _isLoading = false;
  bool _isDeleting = false;
  String? _errorMessage;
  List<AttendanceRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _errorMessage = 'User mapping missing. Contact admin.';
        _records = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: _selectedMonth,
      );
      if (!mounted) return;
      setState(() => _records = records);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load attendance history.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<DateTime> get _availableMonths {
    final now = DateTime.now();
    return List<DateTime>.generate(
      6,
      (index) => DateTime(now.year, now.month - index),
    );
  }

  List<AttendanceRecord> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _records
        .where((record) {
          if (_statusFilter != 'All' &&
              record.status != null &&
              record.status != _statusFilter) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            record.plantName,
            record.vehicleNumber,
            record.inTime,
            record.outTime,
            record.notes,
          ].whereType<String>().join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  String _formatMonth(DateTime month) => DateFormat('MMMM yyyy').format(month);

  String _formatTime(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return DateFormat('dd-MM-yyyy HH:mm').format(parsed);
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String _extractAdjustReason(String raw) {
    final delimiterIndex = raw.indexOf(':');
    if (delimiterIndex == -1) {
      return raw.trim();
    }
    return raw.substring(delimiterIndex + 1).trim();
  }

  Future<void> _deleteRecord(AttendanceRecord record) async {
    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'User mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attendance'),
        content: const Text(
          'Are you sure you want to delete this attendance record?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await _attendanceRepository.deleteAttendance(
        driverId: driverId,
        attendanceId: record.attendanceId,
      );
      if (!mounted) return;
      setState(() {
        _records = List.of(_records)
          ..removeWhere((item) => item.attendanceId == record.attendanceId);
        _isDeleting = false;
      });
      showAppToast(context, 'Attendance deleted.');
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      showAppToast(context, 'Unable to delete attendance.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthItems = _availableMonths;
    final filteredRecords = _filteredRecords;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: AppGradientBackground(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<DateTime>(
                      value: _selectedMonth,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: monthItems
                          .map(
                            (month) => DropdownMenuItem<DateTime>(
                              value: month,
                              child: Text(_formatMonth(month)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedMonth = value);
                          _loadHistory();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _statusFilter,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(
                          value: 'Approved',
                          child: Text('Approved'),
                        ),
                        DropdownMenuItem(
                          value: 'Pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'Rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _statusFilter = value ?? 'All'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                Expanded(
                  child: Center(
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else if (filteredRecords.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'No records found for ${_formatMonth(_selectedMonth)}.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Card(
                    child: ListView.separated(
                      itemCount: filteredRecords.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final record = filteredRecords[index];
                        final statusColor = _statusColor(record.status);
                        final inTime = _formatTime(record.inTime);
                        final outTime = _formatTime(record.outTime);
                        final parsedDate =
                            record.inTime != null && record.inTime!.isNotEmpty
                            ? DateTime.tryParse(record.inTime!)
                            : null;
                        final dayLabel = parsedDate != null
                            ? DateFormat('dd').format(parsedDate)
                            : '--';
                        final subtitleSegments = <String>[
                          'In: $inTime',
                          'Out: $outTime',
                        ];
                        if (record.notes != null && record.notes!.isNotEmpty) {
                          final extractedNotes = record.isAdjustRequest
                              ? _extractAdjustReason(record.notes!)
                              : record.notes!;
                          if (extractedNotes.isNotEmpty) {
                            subtitleSegments.add('Notes: $extractedNotes');
                          }
                        }

                        return Dismissible(
                          key: ValueKey('attendance-${record.attendanceId}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) async {
                            await _deleteRecord(record);
                            return false;
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete, color: Colors.red),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withOpacity(0.15),
                              child: Text(dayLabel),
                            ),
                            title: Text(
                              record.plantName ??
                                  record.plantId ??
                                  'Unknown plant',
                            ),
                            subtitle: Text(subtitleSegments.join('\n')),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Chip(
                                  label: Text(record.status ?? 'Unknown'),
                                  labelStyle: TextStyle(
                                    color: statusColor.withOpacity(0.9),
                                  ),
                                  backgroundColor: statusColor.withOpacity(0.1),
                                ),
                                if (record.isAdjustRequest) ...[
                                  const SizedBox(height: 6),
                                  const Chip(
                                    label: Text('Past Request'),
                                    avatar: Icon(Icons.edit_calendar, size: 16),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
