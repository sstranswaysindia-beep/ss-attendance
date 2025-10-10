import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/daily_attendance_summary.dart';
import '../../core/models/monthly_stat.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class MonthlyStatisticsScreen extends StatefulWidget {
  const MonthlyStatisticsScreen({
    required this.user,
    super.key,
  });

  final AppUser user;

  @override
  State<MonthlyStatisticsScreen> createState() => _MonthlyStatisticsScreenState();
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
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _errorMessage = 'Driver mapping missing. Contact admin.';
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
      final stats = await _attendanceRepository.fetchMonthlyStats(driverId: driverId);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Statistics'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadStats,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
                            Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _StatTile(label: 'Days Present', value: '${_selected!.daysPresent}'),
                                    const Divider(),
                                    _StatTile(label: 'Total Hours', value: _selected!.totalHours ?? '-'),
                                    const Divider(),
                                    _StatTile(label: 'Average In Time', value: _selected!.averageInTime ?? '-'),
                                    const Divider(),
                                    _StatTile(label: 'Average Hours/Day', value: _selected!.averageHours ?? '-'),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text('Monthly Overview', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Card(
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _stats.length,
                              separatorBuilder: (_, __) => const Divider(height: 0),
                              itemBuilder: (context, index) {
                                final stat = _stats[index];
                                return ListTile(
                                  title: Text(_formatMonthKey(stat.month)),
                                  subtitle: Text('Days present: ${stat.daysPresent}'),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(stat.totalHours ?? '-'),
                                      Text(
                                        'Avg Hrs: ${stat.averageHours ?? '-'}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Daily Breakdown', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (_isLoadingDaily)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (_dailySummaries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No daily records for the selected month yet.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            )
                          else
                            Card(
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _dailySummaries.length,
                                separatorBuilder: (_, __) => const Divider(height: 0),
                                itemBuilder: (context, index) {
                                  final summary = _dailySummaries[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: summary.hasOpenShift
                                          ? Colors.orange.shade100
                                          : Colors.green.shade100,
                                      child: Text(summary.dateLabel.split(' ').first),
                                    ),
                                    title: Text(summary.dateLabel),
                                    subtitle: Text(
                                      'In: ${summary.inTimes.join(', ')}\nOut: ${summary.outTimes.isNotEmpty ? summary.outTimes.join(', ') : 'Pending'}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('Total: ${summary.formattedDuration}'),
                                        if (summary.hasOpenShift)
                                          Text(
                                            'Open shift',
                                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
                                          ),
                                      ],
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
  });

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
