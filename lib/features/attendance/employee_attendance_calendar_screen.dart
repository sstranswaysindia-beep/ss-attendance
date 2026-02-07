import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/attendance_record.dart';
import '../../core/models/attendance_salary_details.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

enum _CalendarFilter { all, present, absent }

class EmployeeAttendanceCalendarScreen extends StatefulWidget {
  const EmployeeAttendanceCalendarScreen({
    required this.driverId,
    required this.driverName,
    super.key,
  });

  final String driverId;
  final String driverName;

  @override
  State<EmployeeAttendanceCalendarScreen> createState() =>
      _EmployeeAttendanceCalendarScreenState();
}

class _EmployeeAttendanceCalendarScreenState
    extends State<EmployeeAttendanceCalendarScreen> {
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = false;
  String? _errorMessage;
  List<AttendanceRecord> _records = const [];
  _CalendarFilter _filter = _CalendarFilter.all;
  bool _isLoadingSalary = false;
  String? _salaryError;
  AttendanceSalaryDetails? _salaryDetails;

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadSalaryDetails();
  }

  Future<void> _loadMonth() async {
    if (widget.driverId.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Employee mapping missing. Contact admin.';
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
        driverId: widget.driverId,
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
      const fallback = 'Unable to load attendance calendar.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSalaryDetails() async {
    if (widget.driverId.trim().isEmpty) {
      setState(() {
        _salaryError = 'Employee mapping missing. Contact admin.';
        _salaryDetails = null;
      });
      return;
    }

    setState(() {
      _isLoadingSalary = true;
      _salaryError = null;
    });

    try {
      final details = await _attendanceRepository.fetchSalaryDetails(
        driverId: widget.driverId,
        month: _selectedMonth,
      );
      if (!mounted) return;
      setState(() => _salaryDetails = details);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _salaryError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salaryError = 'Unable to load salary details.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSalary = false);
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    _loadMonth();
    _loadSalaryDetails();
  }

  Map<String, List<AttendanceRecord>> get _recordsByDay {
    final Map<String, List<AttendanceRecord>> map = {};
    for (final record in _records) {
      final raw = record.inTime?.isNotEmpty == true
          ? record.inTime
          : record.outTime;
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) {
        continue;
      }
      final key = _dayKey(parsed);
      map.putIfAbsent(key, () => <AttendanceRecord>[]).add(record);
    }
    return map;
  }

  String _dayKey(DateTime day) {
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isFuture(DateTime day) => day.isAfter(_today);

  int get _daysInMonth {
    final firstDayOfNextMonth = DateTime(_selectedMonth.year,
        _selectedMonth.month + 1, 1);
    return firstDayOfNextMonth.subtract(const Duration(days: 1)).day;
  }

  List<DateTime?> _buildCalendarDays() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final leadingEmpty = firstDay.weekday % 7;
    final total = leadingEmpty + _daysInMonth;
    final totalCells = total <= 35 ? 35 : 42;
    final days = <DateTime?>[];

    for (int i = 0; i < leadingEmpty; i++) {
      days.add(null);
    }
    for (int day = 1; day <= _daysInMonth; day++) {
      days.add(DateTime(_selectedMonth.year, _selectedMonth.month, day));
    }
    while (days.length < totalCells) {
      days.add(null);
    }
    return days;
  }

  int get _presentCount {
    final keys = _recordsByDay.keys.toSet();
    int count = 0;
    for (final key in keys) {
      final day = DateTime.tryParse(key);
      if (day == null) continue;
      if (day.year == _selectedMonth.year &&
          day.month == _selectedMonth.month) {
        final records = _recordsByDay[key] ?? const [];
        final hasPending = records.any(
          (record) => _isPendingApproval(record.status),
        );
        if (!hasPending) {
          count++;
        }
      }
    }
    return count;
  }

  int get _pendingCount {
    final keys = _recordsByDay.keys.toSet();
    int count = 0;
    for (final key in keys) {
      final day = DateTime.tryParse(key);
      if (day == null) continue;
      if (day.year == _selectedMonth.year &&
          day.month == _selectedMonth.month) {
        final records = _recordsByDay[key] ?? const [];
        final hasPending = records.any(
          (record) => _isPendingApproval(record.status),
        );
        if (hasPending) {
          count++;
        }
      }
    }
    return count;
  }

  int get _absentCount {
    final today = _today;
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month,
        _daysInMonth);

    DateTime lastDayToCount;
    if (monthEnd.isBefore(today)) {
      lastDayToCount = monthEnd;
    } else if (monthStart.isAfter(today)) {
      return 0;
    } else {
      lastDayToCount = today;
    }

    int absent = 0;
    for (int day = 1; day <= lastDayToCount.day; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final key = _dayKey(date);
      if (!_recordsByDay.containsKey(key)) {
        absent++;
      }
    }
    return absent;
  }

  bool _isPendingApproval(String? status) {
    if (status == null) return false;
    final normalized = status.toLowerCase().trim();
    if (normalized.isEmpty) return false;
    if (normalized.contains('approved')) return false;
    return normalized.contains('pending') ||
        normalized.contains('approval') ||
        normalized.contains('awaiting');
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
    return DateFormat('hh:mm a').format(parsed);
  }

  void _showDayDetails(DateTime day) {
    final key = _dayKey(day);
    final records = _recordsByDay[key] ?? const [];
    final isAbsent = records.isEmpty && !_isFuture(day);
    final dateLabel = DateFormat('EEE, dd MMM yyyy').format(day);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (isAbsent)
                  const Text('Absent (no attendance record).')
                else
                  ...records.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.plantName ??
                                record.plantId ??
                                'Unknown plant',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text('In: ${_formatTime(record.inTime)}'),
                          Text('Out: ${_formatTime(record.outTime)}'),
                          if (record.vehicleNumber != null &&
                              record.vehicleNumber!.isNotEmpty)
                            Text('Vehicle: ${record.vehicleNumber}'),
                          if (record.notes != null && record.notes!.isNotEmpty)
                            Text('Notes: ${record.notes}'),
                        ],
                      ),
                    ),
                  ),
                if (!isAbsent && records.isEmpty)
                  const Text('No attendance record for this date.'),
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
    final monthLabel = _formatMonth(_selectedMonth);
    final recordsByDay = _recordsByDay;
    final days = _buildCalendarDays();
    final now = DateTime.now();
    final canSelectPrevMonth = now.day <= 15;
    final previousMonth = DateTime(now.year, now.month - 1);
    final monthOptions = canSelectPrevMonth
        ? <DateTime>[
            DateTime(now.year, now.month),
            DateTime(previousMonth.year, previousMonth.month),
          ]
        : <DateTime>[DateTime(now.year, now.month)];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00296B),
        foregroundColor: Colors.white,
        title: const Text(
          'Attendance Calendar',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading
                ? null
                : () {
                    _loadMonth();
                    _loadSalaryDetails();
                  },
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: _isLoading
            ? const Center(child: AppLoader())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD6F0FF), Color(0xFFAEDBFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.driverName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            monthLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _SummaryChip(
                                label: 'Present',
                                value: _presentCount,
                                color: const Color(0xFF0F9D58),
                              ),
                              const SizedBox(width: 8),
                              _SummaryChip(
                                label: 'Pending',
                                value: _pendingCount,
                                color: const Color(0xFFF9A825),
                                textColor: Colors.black,
                              ),
                              const SizedBox(width: 8),
                              _SummaryChip(
                                label: 'Absent',
                                value: _absentCount,
                                color: const Color(0xFFE53935),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SalaryMonthFilter(
                      months: monthOptions,
                      selected: _selectedMonth,
                      onChanged: _isLoadingSalary
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _selectedMonth = value);
                              _loadMonth();
                              _loadSalaryDetails();
                            },
                    ),
                    const SizedBox(height: 12),
                    _SalaryDetailsSection(
                      isLoading: _isLoadingSalary,
                      errorMessage: _salaryError,
                      details: _salaryDetails,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _isLoading ? null : () => _changeMonth(-1),
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous month',
                        ),
                        Expanded(
                          child: Text(
                            monthLabel,
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          onPressed: _isLoading ? null : () => _changeMonth(1),
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next month',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _filter == _CalendarFilter.all,
                          onTap: () =>
                              setState(() => _filter = _CalendarFilter.all),
                        ),
                        _FilterChip(
                          label: 'Present',
                          selected: _filter == _CalendarFilter.present,
                          onTap: () =>
                              setState(() => _filter = _CalendarFilter.present),
                        ),
                        _FilterChip(
                          label: 'Absent',
                          selected: _filter == _CalendarFilter.absent,
                          onTap: () =>
                              setState(() => _filter = _CalendarFilter.absent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
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
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            itemBuilder: (context, index) {
                              final day = days[index];
                              if (day == null) {
                                return const SizedBox.shrink();
                              }
                              final key = _dayKey(day);
                              final hasRecord = recordsByDay.containsKey(key);
                              final isAbsent =
                                  !hasRecord && !_isFuture(day);
                              final hasPending = hasRecord &&
                                  (recordsByDay[key]?.any(
                                        (record) =>
                                            _isPendingApproval(record.status),
                                      ) ??
                                      false);

                              final matchesFilter = _filter ==
                                      _CalendarFilter.all ||
                                  (_filter == _CalendarFilter.present &&
                                      hasRecord) ||
                                  (_filter == _CalendarFilter.absent &&
                                      isAbsent);
                              final isDimmed = !matchesFilter;

                              Color? fillColor;
                              if (hasPending) {
                                fillColor = const Color(0xFFF9A825);
                              } else if (hasRecord) {
                                fillColor = const Color(0xFF0F9D58);
                              } else if (isAbsent) {
                                fillColor = const Color(0xFFE53935);
                              } else {
                                fillColor = Colors.grey.shade200;
                              }

                              final textColor = hasPending
                                  ? Colors.black
                                  : hasRecord || isAbsent
                                  ? Colors.white
                                  : Colors.black87;

                              return Opacity(
                                opacity: isDimmed ? 0.35 : 1,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showDayDetails(day),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: fillColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: day == _today
                                          ? Border.all(
                                              color: Colors.black87,
                                              width: 1.4,
                                            )
                                          : null,
                                    ),
                                    child: Text(
                                      '${day.day}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: textColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.primary.withOpacity(0.2),
      labelStyle: TextStyle(
        color: selected ? theme.colorScheme.primary : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    this.textColor,
  });

  final String label;
  final int value;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: TextStyle(
              color: textColor ?? color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalaryDetailsSection extends StatelessWidget {
  const _SalaryDetailsSection({
    required this.isLoading,
    required this.errorMessage,
    required this.details,
  });

  final bool isLoading;
  final String? errorMessage;
  final AttendanceSalaryDetails? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Salary Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(child: AppLoader(size: 96))
          else if (errorMessage != null)
            Text(
              errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (details == null)
            Text(
              'No salary details found.',
              style: theme.textTheme.bodyMedium,
            )
          else
            Column(
              children: [
                _SalaryRow(
                  label: 'Salary',
                  value: _money(details!.salary),
                  valueColor: _amountColor(details!.salary),
                ),
                _SalaryRow(
                  label: 'Advance',
                  value: _money(details!.advance),
                  valueColor: _amountColor(details!.advance),
                ),
                _SalaryRow(
                  label: 'Total Days',
                  value: details!.totalDays.toString(),
                ),
                _SalaryRow(
                  label: 'Total Paid Days',
                  value: details!.totalPaidDays.toString(),
                ),
                _SalaryRow(
                  label: 'Holiday Taken',
                  value: details!.holidayTaken.toString(),
                ),
                _SalaryRow(
                  label: 'Holiday Deduction',
                  value: _money(details!.holidayDeduction),
                  valueColor: _amountColor(details!.holidayDeduction),
                ),
                _SalaryRow(
                  label: 'Total Deduction',
                  value: _money(details!.totalDeduction),
                  valueColor: _amountColor(details!.totalDeduction),
                ),
                _SalaryRow(
                  label: 'PF Salary',
                  value: _money(details!.pfSalary),
                  valueColor: _amountColor(details!.pfSalary),
                ),
                _SalaryRow(
                  label: 'Employee PF',
                  value: _money(details!.empPf),
                  valueColor: _amountColor(details!.empPf),
                ),
                _SalaryRow(
                  label: 'Employee ESIC',
                  value: _money(details!.empEsic),
                  valueColor: _amountColor(details!.empEsic),
                ),
                _SalaryRow(
                  label: 'Employer PF',
                  value: _money(details!.erPf),
                  valueColor: _amountColor(details!.erPf),
                ),
                _SalaryRow(
                  label: 'Employer ESIC',
                  value: _money(details!.erEsic),
                  valueColor: _amountColor(details!.erEsic),
                ),
                _SalaryRow(
                  label: 'Remaining Salary',
                  value: _money(details!.remSalary),
                  valueColor: _amountColor(details!.remSalary),
                  labelColor: const Color(0xFF00296B),
                  valueFontSize: 18,
                  labelFontSize: 16,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _money(double value) {
    final formatted = NumberFormat('#,##0.##').format(value.abs());
    return value < 0 ? '-$formatted' : formatted;
  }

  static Color _amountColor(double value) {
    if (value < 0) return Colors.red;
    if (value > 0) return Colors.green;
    return Colors.black87;
  }
}

class _SalaryRow extends StatelessWidget {
  const _SalaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.labelColor,
    this.valueFontSize,
    this.labelFontSize,
    this.valueLabel,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? labelColor;
  final double? valueFontSize;
  final double? labelFontSize;
  final String? valueLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: labelColor ?? theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
                fontSize: labelFontSize,
              ),
            ),
          ),
          if (valueLabel != null && valueLabel!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                valueLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? Colors.black87,
              fontSize: valueFontSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalaryMonthFilter extends StatelessWidget {
  const _SalaryMonthFilter({
    required this.months,
    required this.selected,
    required this.onChanged,
  });

  final List<DateTime> months;
  final DateTime selected;
  final ValueChanged<DateTime?>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (months.length <= 1) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Text(
          'Salary Month',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const Spacer(),
        DropdownButton<DateTime>(
          value: months.firstWhere(
            (m) => m.year == selected.year && m.month == selected.month,
            orElse: () => months.first,
          ),
          onChanged: onChanged,
          items: months
              .map(
                (month) => DropdownMenuItem<DateTime>(
                  value: month,
                  child: Text(DateFormat('MMM yyyy').format(month)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
