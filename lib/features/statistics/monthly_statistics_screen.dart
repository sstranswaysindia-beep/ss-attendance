import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/daily_attendance_summary.dart';
import '../../core/models/monthly_stat.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

const Color _statsPrimaryColor = Color(0xFF00296B);
const Color _statsAccentLight = Color(0xFFE3F2FD);
const LinearGradient _statsCardGradient = LinearGradient(
  colors: [Colors.white, _statsAccentLight],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class MonthlyStatisticsScreen extends StatefulWidget {
  const MonthlyStatisticsScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<MonthlyStatisticsScreen> createState() =>
      _MonthlyStatisticsScreenState();
}

class _MonthlyStatisticsScreenState extends State<MonthlyStatisticsScreen> {
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  bool _isLoading = false;
  bool _isLoadingDaily = false;
  String? _errorMessage;
  List<MonthlyStat> _stats = const [];
  MonthlyStat? _selected;
  List<DailyAttendanceSummary> _dailySummaries = const [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId.isEmpty) {
      setState(() {
        _errorMessage = 'User mapping missing. Contact admin.';
        _stats = const [];
        _selected = null;
        _dailySummaries = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stats = await _attendanceRepository.fetchMonthlyStats(
        driverId: driverId,
      );
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _selected = stats.isNotEmpty ? stats.first : null;
      });

      if (_selected != null) {
        await _loadDailySummary(_selected!.month);
      } else {
        setState(() => _dailySummaries = const []);
      }
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load monthly statistics.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadDailySummary(String monthKey) async {
    final driverId = widget.user.driverId;
    final month = _parseMonthKeyToDate(monthKey);
    if (driverId == null || driverId.isEmpty || month == null) {
      setState(() => _dailySummaries = const []);
      return;
    }

    setState(() => _isLoadingDaily = true);

    try {
      final summaries = await _attendanceRepository.fetchDailySummary(
        driverId: driverId,
        month: month,
      );
      if (!mounted) return;
      setState(() {
        _dailySummaries = summaries;
        _isLoadingDaily = false;
      });
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _dailySummaries = const [];
        _isLoadingDaily = false;
      });
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dailySummaries = const [];
        _isLoadingDaily = false;
      });
      showAppToast(context, 'Unable to load daily breakdown.', isError: true);
    }
  }

  String _formatMonthKey(String key) {
    final month = _parseMonthKeyToDate(key);
    if (month == null) {
      return key;
    }
    return DateFormat('MMMM yyyy').format(month);
  }

  DateTime? _parseMonthKeyToDate(String key) {
    if (key.length == 7 && key.contains('-')) {
      final parts = key.split('-');
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year != null && month != null) {
        return DateTime(year, month);
      }
    }
    return null;
  }

  DateTime? get _selectedMonthDate =>
      _selected != null ? _parseMonthKeyToDate(_selected!.month) : null;

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  Map<String, DailyAttendanceSummary> _dailySummaryMap() {
    final map = <String, DailyAttendanceSummary>{};
    for (final summary in _dailySummaries) {
      try {
        final parsed = DateFormat('dd MMM yyyy').parse(
          summary.dateLabel,
          true,
        );
        final key =
            '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
        map[key] = summary;
      } catch (_) {
        // Skip invalid date labels.
      }
    }
    return map;
  }

  int _presentCount(DateTime month, Map<String, DailyAttendanceSummary> map) {
    int count = 0;
    for (final entry in map.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      if (date.year == month.year && date.month == month.month) {
        if (!entry.value.hasApprovalPending) {
          count++;
        }
      }
    }
    return count;
  }

  int _pendingCount(DateTime month, Map<String, DailyAttendanceSummary> map) {
    int count = 0;
    for (final entry in map.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      if (date.year == month.year &&
          date.month == month.month &&
          entry.value.hasApprovalPending) {
        count++;
      }
    }
    return count;
  }

  int _openShiftCount(DateTime month, Map<String, DailyAttendanceSummary> map) {
    int count = 0;
    for (final entry in map.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      if (date.year == month.year &&
          date.month == month.month &&
          entry.value.hasOpenShift) {
        count++;
      }
    }
    return count;
  }

  int _absentCount(DateTime month, Map<String, DailyAttendanceSummary> map) {
    final now = DateTime.now();
    final lastDay = _daysInMonth(month);
    final lastDate = DateTime(month.year, month.month, lastDay);
    final cutoff = lastDate.isBefore(now)
        ? lastDate
        : DateTime(now.year, now.month, now.day);

    int absent = 0;
    for (int day = 1; day <= cutoff.day; day++) {
      final date = DateTime(month.year, month.month, day);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      if (!map.containsKey(key)) {
        absent++;
      }
    }
    return absent;
  }

  void _showDayDetails(DailyAttendanceSummary? summary, DateTime day) {
    final dateLabel = DateFormat('EEE, dd MMM yyyy').format(day);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (summary == null)
                  const Text('No attendance record for this day.')
                else ...[
                  Text('In: ${summary.inTimes.join(', ')}'),
                  Text(
                    'Out: ${summary.outTimes.isNotEmpty ? summary.outTimes.join(', ') : 'Pending'}',
                  ),
                  const SizedBox(height: 8),
                  Text('Total: ${summary.formattedDuration}'),
                  if (summary.hasOpenShift)
                    Text(
                      'Open shift',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Monthly Statistics',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF00296B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadStats,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: ColoredBox(
        color: Colors.white,
        child: _isLoading
            ? const Center(child: AppLoader())
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _stats.isEmpty
            ? Center(
                child: Text(
                  'No statistics available yet.',
                  style: theme.textTheme.bodyLarge,
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    value: _selected?.month,
                    items: _stats
                        .map(
                          (stat) => DropdownMenuItem<String>(
                            value: stat.month,
                            child: Text(_formatMonthKey(stat.month)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _selected = _stats.firstWhere(
                          (element) => element.month == value,
                          orElse: () => _stats.first,
                        );
                      });
                      await _loadDailySummary(value);
                    },
                    decoration: const InputDecoration(labelText: 'Month'),
                  ),
                  const SizedBox(height: 16),
                  if (_selected != null)
                    Container(
                      decoration: BoxDecoration(
                        gradient: _statsCardGradient,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _statsPrimaryColor.withOpacity(0.06),
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _MiniStat(
                                label: 'Days Present',
                                value: '${_selected!.daysPresent}',
                              ),
                              _MiniStat(
                                label: 'Total Hours',
                                value: _selected!.totalHours ?? '-',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _MiniStat(
                                label: 'Avg In',
                                value: _selected!.averageInTime ?? '-',
                              ),
                              _MiniStat(
                                label: 'Avg Hrs/Day',
                                value: _selected!.averageHours ?? '-',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_selectedMonthDate != null)
                    _AttendanceCalendarCard(
                      month: _selectedMonthDate!,
                      summaries: _dailySummaries,
                      onDaySelected: _showDayDetails,
                      presentCount: _presentCount(
                        _selectedMonthDate!,
                        _dailySummaryMap(),
                      ),
                      pendingCount: _pendingCount(
                        _selectedMonthDate!,
                        _dailySummaryMap(),
                      ),
                      openShiftCount: _openShiftCount(
                        _selectedMonthDate!,
                        _dailySummaryMap(),
                      ),
                      absentCount: _absentCount(
                        _selectedMonthDate!,
                        _dailySummaryMap(),
                      ),
                    ),
                  if (_selectedMonthDate != null) const SizedBox(height: 16),
                  Text('Monthly Overview', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _stats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final stat = _stats[index];
                      return Container(
                        decoration: BoxDecoration(
                          gradient: _statsCardGradient,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _statsPrimaryColor.withOpacity(0.06),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatMonthKey(stat.month),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Present: ${stat.daysPresent}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  stat.totalHours ?? '-',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Avg: ${stat.averageHours ?? '-'}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AttendanceCalendarCard extends StatelessWidget {
  const _AttendanceCalendarCard({
    required this.month,
    required this.summaries,
    required this.onDaySelected,
    required this.presentCount,
    required this.pendingCount,
    required this.openShiftCount,
    required this.absentCount,
  });

  final DateTime month;
  final List<DailyAttendanceSummary> summaries;
  final void Function(DailyAttendanceSummary? summary, DateTime day)
  onDaySelected;
  final int presentCount;
  final int pendingCount;
  final int openShiftCount;
  final int absentCount;

  Map<String, DailyAttendanceSummary> get _summaryMap {
    final map = <String, DailyAttendanceSummary>{};
    for (final summary in summaries) {
      try {
        final parsed = DateFormat('dd MMM yyyy').parse(
          summary.dateLabel,
          true,
        );
        final key =
            '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
        map[key] = summary;
      } catch (_) {
        // Skip invalid date labels.
      }
    }
    return map;
  }

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  List<DateTime?> _calendarDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final leadingEmpty = firstDay.weekday % 7;
    final totalDays = _daysInMonth(month);
    final totalCells = (leadingEmpty + totalDays) <= 35 ? 35 : 42;
    final days = <DateTime?>[];

    for (int i = 0; i < leadingEmpty; i++) {
      days.add(null);
    }
    for (int day = 1; day <= totalDays; day++) {
      days.add(DateTime(month.year, month.month, day));
    }
    while (days.length < totalCells) {
      days.add(null);
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _calendarDays(month);
    final summaryMap = _summaryMap;
    final monthLabel = DateFormat('MMMM yyyy').format(month);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statsPrimaryColor.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Calendar',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            monthLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendChip(
                label: 'Present',
                value: presentCount,
                color: Colors.green.shade600,
              ),
              _LegendChip(
                label: 'Pending Approval',
                value: pendingCount,
                color: const Color(0xFFF9A825),
              ),
              _LegendChip(
                label: 'Open Shift',
                value: openShiftCount,
                color: Colors.orange.shade600,
              ),
              _LegendChip(
                label: 'Absent',
                value: absentCount,
                color: Colors.red.shade600,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _WeekdayLabel('Sun'),
              _WeekdayLabel('Mon'),
              _WeekdayLabel('Tue'),
              _WeekdayLabel('Wed'),
              _WeekdayLabel('Thu'),
              _WeekdayLabel('Fri'),
              _WeekdayLabel('Sat'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              if (day == null) {
                return const SizedBox.shrink();
              }
              final key =
                  '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
              final summary = summaryMap[key];
              final now = DateTime.now();
              final isFuture = day.isAfter(
                DateTime(now.year, now.month, now.day),
              );
              final hasOpenShift = summary?.hasOpenShift == true;
              final hasApprovalPending = summary?.hasApprovalPending == true;

              Color fillColor;
              if (summary != null) {
                if (hasApprovalPending) {
                  fillColor = const Color(0xFFF9A825);
                } else {
                  fillColor = hasOpenShift
                      ? Colors.orange.shade400
                      : Colors.green.shade500;
                }
              } else if (!isFuture) {
                fillColor = Colors.red.shade400;
              } else {
                fillColor = Colors.grey.shade200;
              }

              final textColor = hasApprovalPending
                  ? Colors.black
                  : summary != null || !isFuture
                  ? Colors.white
                  : Colors.black87;

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onDaySelected(summary, day),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${day.day}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
