import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

// ── Design tokens ──
const Color _primaryDark = Color(0xFF0A2540);
const Color _accentTeal = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A2540);
const Color _gradientEnd = Color(0xFF1B5E7B);

class AttendanceAdjustRequestScreen extends StatefulWidget {
  const AttendanceAdjustRequestScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AttendanceAdjustRequestScreen> createState() =>
      _AttendanceAdjustRequestScreenState();
}

class _AttendanceAdjustRequestScreenState
    extends State<AttendanceAdjustRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _inTimeController = TextEditingController();
  final _outTimeController = TextEditingController();
  final _reasonController = TextEditingController();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  bool _isSubmitting = false;
  bool _isCheckingAdvanceEntry = false;
  bool _advanceEntryAllowed = false;
  TimeOfDay? _selectedInTime;
  TimeOfDay? _selectedOutTime;
  DateTime _absentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoadingAbsent = false;
  String? _absentError;
  List<AttendanceRecord> _absentRecords = const [];

  @override
  void initState() {
    super.initState();
    _advanceEntryAllowed = widget.user.advanceEntryAllowed;
    _refreshAdvanceEntryFlag();
    _loadAbsentMonth();
  }

  @override
  void dispose() {
    _inTimeController.dispose();
    _outTimeController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // ── Business logic (unchanged) ──

  Future<void> _refreshAdvanceEntryFlag() async {
    if (widget.user.id.isEmpty) return;
    setState(() => _isCheckingAdvanceEntry = true);
    try {
      final latest = await _attendanceRepository.fetchAdvanceEntryAllowed(
        userId: widget.user.id,
      );
      if (!mounted || latest == null) return;
      if (latest != _advanceEntryAllowed) {
        setState(() => _advanceEntryAllowed = latest);
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingAdvanceEntry = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstAllowed = _minSelectableDate(now);
    final lastAllowed = DateTime(now.year, now.month, now.day);
    var initial = _selectedDate;
    if (initial.isBefore(firstAllowed)) {
      initial = firstAllowed;
    } else if (initial.isAfter(lastAllowed)) {
      initial = lastAllowed;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstAllowed,
      lastDate: lastAllowed,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: const DatePickerThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
            ),
            colorScheme: theme.colorScheme.copyWith(
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      if (_isBackdateRestricted(picked, now)) {
        showAppToast(
          context,
          'Past attendance requests for previous months are closed after the 3rd.',
          isError: true,
        );
        return;
      }
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime({required bool isIn}) async {
    final fallback = TimeOfDay.now();
    final initial = isIn
        ? (_selectedInTime ?? fallback)
        : (_selectedOutTime ?? fallback);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Colors.white,
            ),
            colorScheme: theme.colorScheme.copyWith(
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isIn) {
          _selectedInTime = picked;
          _inTimeController.text = picked.format(context);
        } else {
          _selectedOutTime = picked;
          _outTimeController.text = picked.format(context);
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    if (_isBackdateRestricted(_selectedDate, now)) {
      showAppToast(
        context,
        'Past attendance requests for previous months are closed after the 3rd.',
        isError: true,
      );
      return;
    }

    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId.isEmpty) {
      showAppToast(context, 'User mapping missing. Contact admin.', isError: true);
      return;
    }

    final inTimeOfDay = _selectedInTime;
    final outTimeOfDay = _selectedOutTime;
    if (inTimeOfDay == null || outTimeOfDay == null) {
      showAppToast(context, 'Provide valid in and out time.', isError: true);
      return;
    }

    final proposedIn = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      inTimeOfDay.hour, inTimeOfDay.minute,
    );
    var proposedOut = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      outTimeOfDay.hour, outTimeOfDay.minute,
    );

    if (!proposedOut.isAfter(proposedIn)) {
      showAppToast(context, 'Out time must be after in time.', isError: true);
      return;
    }

    final reason = _reasonController.text.trim();
    final requestedById = widget.user.id;
    final plantId = widget.user.assignmentPlantId?.isNotEmpty == true
        ? widget.user.assignmentPlantId
        : widget.user.plantId;
    final vehicleId = widget.user.assignmentVehicleId?.isNotEmpty == true
        ? widget.user.assignmentVehicleId
        : (widget.user.availableVehicles.isNotEmpty
              ? widget.user.availableVehicles.first.id
              : null);
    final plantName = widget.user.assignmentPlantName?.isNotEmpty == true
        ? widget.user.assignmentPlantName
        : widget.user.plantName;
    final vehicleRole = widget.user.driverRole;
    final plantAllowsNoVehicle = _plantAllowsMissingVehicle(
      plantName: plantName, driverRole: vehicleRole,
    );

    if (plantId == null || plantId.isEmpty) {
      showAppToast(context, 'Plant mapping missing. Contact admin.', isError: true);
      return;
    }

    if (!plantAllowsNoVehicle && (vehicleId == null || vehicleId.isEmpty)) {
      showAppToast(context, 'Vehicle mapping missing. Contact admin.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _attendanceRepository.submitAdjustRequest(
        driverId: driverId,
        requestedById: requestedById,
        proposedIn: proposedIn,
        proposedOut: proposedOut,
        reason: reason,
        plantId: plantId,
        vehicleId: plantId != null && plantAllowsNoVehicle && (vehicleId == null || vehicleId.isEmpty)
            ? null
            : vehicleId,
      );
      if (!mounted) return;
      showAppToast(context, 'Request submitted for approval');
      Navigator.of(context).pop(true);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to submit request.', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _loadAbsentMonth() async {
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId.isEmpty) {
      setState(() {
        _absentError = 'User mapping missing. Contact admin.';
        _absentRecords = const [];
      });
      return;
    }

    setState(() {
      _isLoadingAbsent = true;
      _absentError = null;
    });

    try {
      final records = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: _absentMonth,
      );
      if (!mounted) return;
      setState(() => _absentRecords = records);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _absentError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _absentError = 'Unable to load absent days.');
    } finally {
      if (mounted) setState(() => _isLoadingAbsent = false);
    }
  }

  bool _plantAllowsMissingVehicle({
    required String? plantName,
    required String? driverRole,
  }) {
    bool containsOffice(String? text) {
      if (text == null || text.isEmpty) return false;
      return text.toLowerCase().contains('office');
    }
    return containsOffice(plantName) || containsOffice(driverRole);
  }

  void _changeAbsentMonth(int delta) {
    setState(() {
      _absentMonth = DateTime(_absentMonth.year, _absentMonth.month + delta, 1);
    });
    _loadAbsentMonth();
  }

  Map<String, List<AttendanceRecord>> get _absentRecordsByDay {
    final Map<String, List<AttendanceRecord>> map = {};
    for (final record in _absentRecords) {
      final raw = record.inTime?.isNotEmpty == true
          ? record.inTime
          : record.outTime;
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
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

  int get _absentDaysInMonth {
    final firstDayOfNextMonth =
        DateTime(_absentMonth.year, _absentMonth.month + 1, 1);
    return firstDayOfNextMonth.subtract(const Duration(days: 1)).day;
  }

  List<DateTime?> _buildAbsentCalendarDays() {
    final firstDay = DateTime(_absentMonth.year, _absentMonth.month, 1);
    final leadingEmpty = firstDay.weekday % 7;
    final total = leadingEmpty + _absentDaysInMonth;
    final totalCells = total <= 35 ? 35 : 42;
    final days = <DateTime?>[];

    for (int i = 0; i < leadingEmpty; i++) {
      days.add(null);
    }
    for (int day = 1; day <= _absentDaysInMonth; day++) {
      days.add(DateTime(_absentMonth.year, _absentMonth.month, day));
    }
    while (days.length < totalCells) {
      days.add(null);
    }
    return days;
  }

  bool _isBackdateRestricted(DateTime date, DateTime now) {
    if (_advanceEntryAllowed) {
      final firstOfCurrentMonth = DateTime(now.year, now.month, 1);
      final firstOfPreviousMonth =
          DateTime(firstOfCurrentMonth.year, firstOfCurrentMonth.month - 1, 1);
      return date.isBefore(firstOfPreviousMonth);
    }
    if (now.day <= 3) return false;
    final firstOfCurrentMonth = DateTime(now.year, now.month, 1);
    return date.isBefore(firstOfCurrentMonth);
  }

  DateTime _minSelectableDate(DateTime now) {
    if (_advanceEntryAllowed) {
      final firstOfCurrentMonth = DateTime(now.year, now.month, 1);
      return DateTime(firstOfCurrentMonth.year, firstOfCurrentMonth.month - 1, 1);
    }
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    if (now.day <= 3) return ninetyDaysAgo;
    final firstOfCurrentMonth = DateTime(now.year, now.month, 1);
    return firstOfCurrentMonth.isAfter(ninetyDaysAgo)
        ? firstOfCurrentMonth
        : ninetyDaysAgo;
  }

  // ── UI Helpers ──

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
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
                gradient: const LinearGradient(colors: [_primaryDark, _accentTeal]),
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
              color: _primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _premiumInputDecoration({
    required String label,
    required IconData icon,
    Color? fillColor,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, color: _accentTeal, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44),
      filled: true,
      fillColor: fillColor ?? const Color(0xFFF8FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accentTeal, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${DateFormat('dd MMM yyyy').format(_selectedDate)} (${DateFormat('EEEE').format(_selectedDate)})';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 134,
              floating: false,
              pinned: true,
              centerTitle: true,
              backgroundColor: _gradientStart,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'Past Attendance Request',
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
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Hero date card
                          GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_rounded, color: Colors.white70, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Selected Date',
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateLabel,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_month_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
            // Request Form
            _sectionTitle('Request Details', icon: Icons.edit_note_rounded),
            _buildRequestForm(),
            const SizedBox(height: 8),
            // Absent Days Calendar
            _sectionTitle('Absent Days', icon: Icons.event_busy_rounded),
            _buildAbsentCalendar(),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestForm() {
    return _glassCard(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // In Time
            TextFormField(
              controller: _inTimeController,
              readOnly: true,
              decoration: _premiumInputDecoration(
                label: 'In Time',
                icon: Icons.login_rounded,
              ),
              onTap: () => _pickTime(isIn: true),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Provide in time' : null,
            ),
            const SizedBox(height: 14),
            // Out Time
            TextFormField(
              controller: _outTimeController,
              readOnly: true,
              decoration: _premiumInputDecoration(
                label: 'Out Time',
                icon: Icons.logout_rounded,
              ),
              onTap: () => _pickTime(isIn: false),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Provide out time' : null,
            ),
            const SizedBox(height: 14),
            // Reason
            TextFormField(
              controller: _reasonController,
              maxLines: 3,
              decoration: _premiumInputDecoration(
                label: 'Reason for request',
                icon: Icons.notes_rounded,
                fillColor: const Color(0xFFFFF9E6),
              ).copyWith(
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Please describe the reason'
                  : null,
            ),
            const SizedBox(height: 20),
            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryDark, _accentTeal],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _accentTeal.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _isSubmitting ? 'Submitting...' : 'Submit Request',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbsentCalendar() {
    final days = _buildAbsentCalendarDays();
    final recordsByDay = _absentRecordsByDay;

    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month navigation
          Row(
            children: [
              GestureDetector(
                onTap: _isLoadingAbsent ? null : () => _changeAbsentMonth(-1),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: _isLoadingAbsent ? Colors.grey.shade300 : _primaryDark,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_absentMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isLoadingAbsent ? null : () => _changeAbsentMonth(1),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _isLoadingAbsent ? Colors.grey.shade300 : _primaryDark,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Legend
          Row(
            children: [
              _legendDot(Colors.red.shade400, 'Absent'),
              const SizedBox(width: 16),
              _legendDot(Colors.green.shade500, 'Present'),
              const SizedBox(width: 16),
              _legendDot(Colors.grey.shade300, 'Future'),
            ],
          ),
          const SizedBox(height: 12),
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
          // Calendar grid
          if (_isLoadingAbsent)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: AppLoader()),
            )
          else if (_absentError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  _absentError!,
                  style: TextStyle(color: Colors.red.shade600, fontSize: 13),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index];
                if (day == null) return const SizedBox.shrink();

                final key = _dayKey(day);
                final records = recordsByDay[key] ?? const [];
                final isAbsent = records.isEmpty && !_isFuture(day);
                final isPresent = records.isNotEmpty;
                final isToday = day == _today;

                Color fillColor;
                Color textColor;
                if (isAbsent) {
                  fillColor = Colors.red.shade400;
                  textColor = Colors.white;
                } else if (isPresent) {
                  fillColor = Colors.green.shade500;
                  textColor = Colors.white;
                } else {
                  fillColor = Colors.grey.shade100;
                  textColor = Colors.black87;
                }

                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday
                        ? Border.all(color: _accentTeal, width: 2)
                        : null,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Red indicates absent days — tap to raise a request',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
