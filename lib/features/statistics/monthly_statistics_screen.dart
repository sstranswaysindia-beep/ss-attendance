import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/daily_attendance_summary.dart';
import '../../core/models/monthly_stat.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

// ── Design tokens ──
const Color _statsPrimary = Color(0xFF0A2540);
const Color _statsAccent = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A2540);
const Color _gradientEnd = Color(0xFF1B5E7B);

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

  // ── Data fetching (unchanged logic) ──

  Future<void> _loadStats() async {
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

  // ── Helpers (unchanged logic) ──

  String _formatMonthKey(String key) {
    final month = _parseMonthKeyToDate(key);
    if (month == null) return key;
    return DateFormat('MMMM yyyy').format(month);
  }

  String _shortMonthLabel(String key) {
    final month = _parseMonthKeyToDate(key);
    if (month == null) return key;
    return DateFormat('MMM yy').format(month);
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
      } catch (_) {}
    }
    return map;
  }

  int _presentCount(DateTime month, Map<String, DailyAttendanceSummary> map) {
    int count = 0;
    for (final entry in map.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      if (date.year == month.year && date.month == month.month) {
        if (!entry.value.hasApprovalPending) count++;
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

  int _openShiftCount(
      DateTime month, Map<String, DailyAttendanceSummary> map) {
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
      if (!map.containsKey(key)) absent++;
    }
    return absent;
  }

  void _showDayDetails(DailyAttendanceSummary? summary, DateTime day) {
    final dateLabel = DateFormat('EEE, dd MMM yyyy').format(day);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _statsPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (summary == null)
                    _detailRow(Icons.event_busy_rounded, 'No attendance record', Colors.red.shade400)
                  else ...[
                    _detailRow(Icons.login_rounded, 'In: ${summary.inTimes.join(', ')}', Colors.green.shade600),
                    const SizedBox(height: 8),
                    _detailRow(
                      Icons.logout_rounded,
                      'Out: ${summary.outTimes.isNotEmpty ? summary.outTimes.join(', ') : 'Pending'}',
                      summary.outTimes.isNotEmpty ? Colors.blue.shade600 : Colors.orange.shade600,
                    ),
                    const SizedBox(height: 8),
                    _detailRow(Icons.timer_rounded, 'Total: ${summary.formattedDuration}', _statsPrimary),
                    if (summary.hasOpenShift) ...[
                      const SizedBox(height: 8),
                      _detailRow(Icons.warning_amber_rounded, 'Open shift', Colors.orange.shade600),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }

  // ── Month selector sheet ──

  void _showMonthSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Month',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _statsPrimary,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.5,
                ),
                itemCount: _stats.length,
                itemBuilder: (context, index) {
                  final stat = _stats[index];
                  final selected = _selected?.month == stat.month;
                  return GestureDetector(
                    onTap: () async {
                      Navigator.of(context).pop();
                      setState(() {
                        _selected = stat;
                      });
                      await _loadDailySummary(stat.month);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(colors: [_statsPrimary, _statsAccent])
                            : null,
                        color: selected ? null : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? Colors.transparent : Colors.grey.shade200,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _shortMonthLabel(stat.month),
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Glass card helper ──

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_statsPrimary, _statsAccent]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _statsPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthDate = _selectedMonthDate;
    final summaryMap = _dailySummaryMap();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: _isLoading
          ? Container(
              color: const Color(0xFFF0F4F8),
              child: const Center(child: AppLoader()),
            )
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
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    expandedHeight: _selected != null ? 216 : 120,
                    floating: false,
                    pinned: true,
                    centerTitle: true,
                    backgroundColor: _gradientStart,
                    foregroundColor: Colors.white,
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      IconButton(
                        onPressed: _isLoading ? null : _loadStats,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Reload',
                      ),
                    ],
                    title: const Text(
                      'Monthly Statistics',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_gradientStart, _gradientEnd, Color(0xFF0D4F6B)],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 34, 20, 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_selected != null) _buildHeroCard(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ];
              },
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // Attendance Calendar
                  if (monthDate != null) ...[
                    _sectionTitle('Attendance Calendar', icon: Icons.calendar_month_rounded),
                    _buildCalendarCard(monthDate, summaryMap),
                    const SizedBox(height: 8),
                  ],
                  // Monthly Overview
                  _sectionTitle('Monthly Overview', icon: Icons.bar_chart_rounded),
                  ...List.generate(_stats.length, (index) {
                    final stat = _stats[index];
                    final isSelected = _selected?.month == stat.month;
                    return _buildMonthOverviewCard(stat, isSelected);
                  }),
                ],
              ),
            ),
    );
  }

  // ── Hero Card ──

  Widget _buildHeroCard() {
    final stat = _selected!;
    return GestureDetector(
      onTap: _showMonthSelector,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Days Present',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stat.daysPresent}',
                      style: const TextStyle(
                        color: Color(0xFF7CFFB2),
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _shortMonthLabel(stat.month),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _heroMiniStat('Total Hrs', stat.totalHours ?? '-'),
                _heroMiniStat('Avg In', stat.averageInTime ?? '-'),
                _heroMiniStat('Avg Hrs/Day', stat.averageHours ?? '-'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Calendar Card ──

  Widget _buildCalendarCard(
      DateTime month, Map<String, DailyAttendanceSummary> summaryMap) {
    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final present = _presentCount(month, summaryMap);
    final pending = _pendingCount(month, summaryMap);
    final openShift = _openShiftCount(month, summaryMap);
    final absent = _absentCount(month, summaryMap);

    final firstDay = DateTime(month.year, month.month, 1);
    final leadingEmpty = firstDay.weekday % 7;
    final totalDays = _daysInMonth(month);
    final totalCells = (leadingEmpty + totalDays) <= 35 ? 35 : 42;
    final days = <DateTime?>[];
    for (int i = 0; i < leadingEmpty; i++) days.add(null);
    for (int day = 1; day <= totalDays; day++) {
      days.add(DateTime(month.year, month.month, day));
    }
    while (days.length < totalCells) days.add(null);

    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            monthLabel,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _legendChip('Present', present, Colors.green.shade600),
              _legendChip('Pending', pending, const Color(0xFFF9A825)),
              _legendChip('Open', openShift, Colors.orange.shade600),
              _legendChip('Absent', absent, Colors.red.shade500),
            ],
          ),
          const SizedBox(height: 14),
          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (d) => Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          // Grid
          _isLoadingDaily
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: AppLoader()),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: days.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 5,
                  ),
                  itemBuilder: (context, index) {
                    final day = days[index];
                    if (day == null) return const SizedBox.shrink();

                    final key =
                        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                    final summary = summaryMap[key];
                    final now = DateTime.now();
                    final isFuture = day.isAfter(DateTime(now.year, now.month, now.day));
                    final hasOpen = summary?.hasOpenShift == true;
                    final hasPending = summary?.hasApprovalPending == true;

                    Color fillColor;
                    if (summary != null) {
                      fillColor = hasPending
                          ? const Color(0xFFF9A825)
                          : hasOpen
                              ? Colors.orange.shade400
                              : Colors.green.shade500;
                    } else if (!isFuture) {
                      fillColor = Colors.red.shade400;
                    } else {
                      fillColor = Colors.grey.shade100;
                    }

                    final textColor = hasPending
                        ? Colors.black
                        : summary != null || !isFuture
                            ? Colors.white
                            : Colors.black87;

                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showDayDetails(summary, day),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: fillColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
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

  Widget _legendChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  // ── Monthly Overview Card ──

  Widget _buildMonthOverviewCard(MonthlyStat stat, bool isSelected) {
    return GestureDetector(
      onTap: () async {
        setState(() => _selected = stat);
        await _loadDailySummary(stat.month);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _statsPrimary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _statsAccent : Colors.grey.shade100,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.08 : 0.03),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withOpacity(0.15)
                    : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: isSelected ? Colors.white : _statsAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatMonthKey(stat.month),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${stat.daysPresent} days present',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  stat.totalHours ?? '-',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? const Color(0xFF7CFFB2) : _statsAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Avg: ${stat.averageHours ?? '-'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white54 : Colors.grey.shade500,
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
