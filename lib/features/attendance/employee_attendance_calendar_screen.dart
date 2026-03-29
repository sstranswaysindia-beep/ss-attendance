import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/attendance_record.dart';
import '../../core/models/attendance_salary_details.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

// ─── Premium Design Tokens ───
const _gradientStart = Color(0xFF0A1628);
const _gradientMid = Color(0xFF142B47);
const _gradientEnd = Color(0xFF1B3A5C);
const _accentTeal = Color(0xFF00BFA6);
const _accentGold = Color(0xFFD4A843);
const _heroGreen = Color(0xFF7CFFB2);
const _heroRed = Color(0xFFFF5E5E);
const _surfaceBg = Color(0xFFF0F4F8);
const _surfaceCard = Color(0xFFF8FAFF);

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
    extends State<EmployeeAttendanceCalendarScreen>
    with TickerProviderStateMixin {
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = false;
  String? _errorMessage;
  List<AttendanceRecord> _records = const [];
  _CalendarFilter _filter = _CalendarFilter.all;
  bool _isLoadingSalary = false;
  String? _salaryError;
  AttendanceSalaryDetails? _salaryDetails;

  // Animations
  late AnimationController _heroController;
  late Animation<double> _heroFade;
  late Animation<double> _heroScale;

  late AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadMonth();
    _loadSalaryDetails();
  }

  void _setupAnimations() {
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _heroController, curve: Curves.easeOut),
    );
    _heroScale = Tween<double>(begin: 0.95, end: 1).animate(
      CurvedAnimation(parent: _heroController, curve: Curves.easeOutBack),
    );

    _staggerController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _heroController.forward();
    _staggerController.forward();
  }

  @override
  void dispose() {
    _heroController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _loadMonth() async {
    if (widget.driverId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Employee mapping missing. Contact admin.';
        _records = const [];
      });
      return;
    }

    if (!mounted) return;
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
      _staggerController.forward(from: 0);
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
      if (!mounted) return;
      setState(() {
        _salaryError = 'Employee mapping missing. Contact admin.';
        _salaryDetails = null;
      });
      return;
    }

    if (!mounted) return;
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
      final raw = record.inTime?.isNotEmpty == true ? record.inTime : record.outTime;
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
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isFuture(DateTime day) => day.isAfter(_today);

  int get _daysInMonth {
    final firstDayOfNextMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
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
      if (day.year == _selectedMonth.year && day.month == _selectedMonth.month) {
        final records = _recordsByDay[key] ?? const [];
        final hasPending =
            records.any((record) => _isPendingApproval(record.status));
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
      if (day.year == _selectedMonth.year && day.month == _selectedMonth.month) {
        final records = _recordsByDay[key] ?? const [];
        final hasPending =
            records.any((record) => _isPendingApproval(record.status));
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
    final monthEnd =
        DateTime(_selectedMonth.year, _selectedMonth.month, _daysInMonth);

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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bump
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAbsent
                          ? _heroRed.withValues(alpha: 0.1)
                          : _accentTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isAbsent
                          ? Icons.event_busy_rounded
                          : Icons.event_available_rounded,
                      color: isAbsent ? _heroRed : _accentTeal,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _gradientStart,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (isAbsent)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _heroRed.withValues(alpha: 0.05),
                    border: Border.all(color: _heroRed.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: _heroRed, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Absent (no attendance record).',
                          style: TextStyle(
                            color: _heroRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (records.isEmpty)
                const Text('No attendance record for this date.')
              else
                ...records.map(
                  (record) => Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _gradientStart.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: _gradientStart.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.factory_outlined,
                                size: 16, color: _accentTeal),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                record.plantName ??
                                    record.plantId ??
                                    'Unknown plant',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: _gradientStart,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _buildDetailRow('In Time', _formatTime(record.inTime),
                            Icons.login_rounded),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                            'Out Time', _formatTime(record.outTime), Icons.logout_rounded),
                        if (record.vehicleNumber != null &&
                            record.vehicleNumber!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildDetailRow(
                              'Vehicle', record.vehicleNumber!, Icons.local_shipping_outlined),
                        ],
                        if (record.notes != null && record.notes!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _accentGold.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _accentGold.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.note_alt_outlined,
                                    size: 16, color: _accentGold),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    record.notes!,
                                    style: const TextStyle(
                                      color: Color(0xFF947B2C),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _gradientStart,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = _formatMonth(_selectedMonth);
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
      backgroundColor: _surfaceBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Premium Gradient AppBar
          SliverAppBar(
            pinned: true,
            centerTitle: true,
            expandedHeight: 280,
            backgroundColor: _gradientEnd,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            title: const Text(
              'Attendance Calendar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        _loadMonth();
                        _loadSalaryDetails();
                      },
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                ),
                tooltip: 'Reload',
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_gradientStart, _gradientEnd, _gradientMid],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: FadeTransition(
                      opacity: _heroFade,
                      child: ScaleTransition(
                        scale: _heroScale,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildHeroCard(monthLabel),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Body content
          SliverToBoxAdapter(
            child: _isLoading
                ? const SizedBox(
                    height: 300,
                    child: Center(child: AppLoader()),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAnimatedElement(
                          index: 0,
                          child: _buildSalaryDetailsSection(),
                        ),
                        const SizedBox(height: 24),
                        _buildAnimatedElement(
                          index: 1,
                          child: _buildMonthFilters(monthLabel, monthOptions),
                        ),
                        const SizedBox(height: 20),
                        if (_errorMessage != null)
                          _buildAnimatedElement(
                            index: 1,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _heroRed.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: _heroRed),
                                ),
                              ),
                            ),
                          ),
                        _buildAnimatedElement(
                          index: 2,
                          child: _buildCalendarGrid(),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(String monthLabel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_accentTeal, _heroGreen]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _accentTeal.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.driverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildHeroStatBadge('Present', _presentCount.toString(), _heroGreen),
              const SizedBox(width: 12),
              _buildHeroStatBadge('Pending', _pendingCount.toString(), _accentGold),
              const SizedBox(width: 12),
              _buildHeroStatBadge('Absent', _absentCount.toString(), _heroRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedElement({required int index, required Widget child}) {
    final start = (index * 0.1).clamp(0.0, 1.0);
    final end = (start + 0.4).clamp(0.0, 1.0);
    
    final fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );
    final slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: child,
      ),
    );
  }

  Widget _buildMonthFilters(String monthLabel, List<DateTime> monthOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _isLoading ? null : () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded, color: _gradientStart),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    monthLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _gradientStart,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded, color: _gradientStart),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ],
            ),
            // Optional: Monthly selector dropdown
            if (monthOptions.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: monthOptions.firstWhere(
                      (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
                      orElse: () => monthOptions.first,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _gradientStart),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: _gradientStart),
                    onChanged: _isLoadingSalary
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedMonth = value);
                            _loadMonth();
                            _loadSalaryDetails();
                          },
                    items: monthOptions
                        .map((month) => DropdownMenuItem<DateTime>(
                              value: month,
                              child: Text(DateFormat('MMM yyyy').format(month)),
                            ))
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildFilterChip('All', _CalendarFilter.all),
              const SizedBox(width: 8),
              _buildFilterChip('Present', _CalendarFilter.present),
              const SizedBox(width: 8),
              _buildFilterChip('Absent', _CalendarFilter.absent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, _CalendarFilter filterType) {
    final isSelected = _filter == filterType;
    return InkWell(
      onTap: () {
        setState(() => _filter = filterType);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentTeal : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _accentTeal : Colors.grey.shade300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accentTeal.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final days = _buildCalendarDays();
    final recordsByDay = _recordsByDay;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gradientStart.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: _gradientStart.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _WeekdayLabel('Sun'),
              _WeekdayLabel('Mon'),
              _WeekdayLabel('Tue'),
              _WeekdayLabel('Wed'),
              _WeekdayLabel('Thu'),
              _WeekdayLabel('Fri'),
              _WeekdayLabel('Sat'),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              if (day == null) return const SizedBox.shrink();

              final key = _dayKey(day);
              final hasRecord = recordsByDay.containsKey(key);
              final isAbsent = !hasRecord && !_isFuture(day);
              final hasPending = hasRecord &&
                  (recordsByDay[key]?.any(
                        (record) => _isPendingApproval(record.status),
                      ) ??
                      false);

              final matchesFilter = _filter == _CalendarFilter.all ||
                  (_filter == _CalendarFilter.present && hasRecord) ||
                  (_filter == _CalendarFilter.absent && isAbsent);
              
              final isDimmed = !matchesFilter;
              
              Color fillColor;
              Color borderCol = Colors.transparent;
              Color textColor = Colors.white;

              if (hasPending) {
                fillColor = _accentGold;
                textColor = Colors.white;
              } else if (hasRecord) {
                fillColor = _accentTeal;
              } else if (isAbsent) {
                fillColor = _heroRed;
              } else {
                fillColor = Colors.transparent;
                textColor = Colors.grey.shade500;
              }

              if (day == _today) {
                borderCol = _gradientStart;
                if (!hasRecord && !isAbsent) {
                  textColor = _gradientStart;
                }
              }

              return AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isDimmed ? 0.2 : 1.0,
                child: GestureDetector(
                  onTap: () => _showDayDetails(day),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fillColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderCol, width: day == _today ? 2 : 0),
                      boxShadow: (hasRecord || isAbsent || hasPending) && !isDimmed && fillColor != Colors.transparent
                          ? [
                              BoxShadow(
                                color: fillColor.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: day == _today ? FontWeight.w900 : FontWeight.w700,
                        fontSize: 14,
                      ),
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

  Widget _buildSalaryDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_gradientStart, _accentTeal]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Salary Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _gradientStart,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoadingSalary)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: AppLoader(size: 64)))
        else if (_salaryError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _heroRed.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _heroRed.withValues(alpha: 0.2)),
            ),
            child: Text(
              _salaryError!,
              style: const TextStyle(color: _heroRed, fontWeight: FontWeight.w600),
            ),
          )
        else if (_salaryDetails == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'No salary details found.',
                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surfaceCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _gradientStart.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: _gradientStart.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildPremiumSalaryRow('Salary', _money(_salaryDetails!.salary), _amountColor(_salaryDetails!.salary)),
                _buildDivider(),
                _buildPremiumSalaryRow('Advance', _money(_salaryDetails!.advance), _amountColor(_salaryDetails!.advance)),
                _buildDivider(),
                _buildPremiumSalaryRow('Total Days / Paid', '${_salaryDetails!.totalDays} / ${_salaryDetails!.totalPaidDays}', _gradientStart),
                _buildDivider(),
                _buildPremiumSalaryRow('Holiday Deduction', _money(_salaryDetails!.holidayDeduction), _amountColor(_salaryDetails!.holidayDeduction), labelSuffix: '(${_salaryDetails!.holidayTaken} taken)'),
                _buildDivider(),
                _buildPremiumSalaryRow('Total Deduction', _money(_salaryDetails!.totalDeduction), _amountColor(_salaryDetails!.totalDeduction)),
                _buildDivider(),
                _buildPremiumSalaryRow('PF Salary', _money(_salaryDetails!.pfSalary), _amountColor(_salaryDetails!.pfSalary)),
                _buildDivider(),
                _buildPremiumSalaryRow('Employee/Employer PF', '${_money(_salaryDetails!.empPf)} / ${_money(_salaryDetails!.erPf)}', _amountColor(_salaryDetails!.empPf)),
                _buildDivider(),
                _buildPremiumSalaryRow('Employee/Employer ESIC', '${_money(_salaryDetails!.empEsic)} / ${_money(_salaryDetails!.erEsic)}', _amountColor(_salaryDetails!.empEsic)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_gradientStart, _gradientEnd]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _gradientStart.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Remaining Salary',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _money(_salaryDetails!.remSalary),
                        style: const TextStyle(
                          color: _heroGreen,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDivider() {
    return Divider(height: 24, color: _gradientStart.withValues(alpha: 0.05));
  }

  Widget _buildPremiumSalaryRow(String label, String value, Color valueColor, {String? labelSuffix}) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (labelSuffix != null) ...[
                const SizedBox(width: 6),
                Text(
                  labelSuffix,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  static String _money(double value) {
    if (value == 0) return '₹0';
    final formatted = NumberFormat('#,##0.##').format(value.abs());
    return value < 0 ? '-₹$formatted' : '₹$formatted';
  }

  static Color _amountColor(double value) {
    if (value < 0) return _heroRed;
    if (value > 0) return _accentTeal;
    return _gradientStart;
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
        style: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
