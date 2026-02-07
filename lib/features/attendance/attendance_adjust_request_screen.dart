import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    if (_isBackdateRestricted(_selectedDate, now)) {
      showAppToast(
        context,
        'Past attendance requests for previous months are closed after the 3rd.',
        isError: true,
      );
      return;
    }

    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId.isEmpty) {
      showAppToast(
        context,
        'User mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    final inTimeOfDay = _selectedInTime;
    final outTimeOfDay = _selectedOutTime;
    if (inTimeOfDay == null || outTimeOfDay == null) {
      showAppToast(context, 'Provide valid in and out time.', isError: true);
      return;
    }

    final proposedIn = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      inTimeOfDay.hour,
      inTimeOfDay.minute,
    );
    var proposedOut = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      outTimeOfDay.hour,
      outTimeOfDay.minute,
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
      plantName: plantName,
      driverRole: vehicleRole,
    );

    if (plantId == null || plantId.isEmpty) {
      showAppToast(
        context,
        'Plant mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    if (!plantAllowsNoVehicle && (vehicleId == null || vehicleId.isEmpty)) {
      showAppToast(
        context,
        'Vehicle mapping missing. Contact admin.',
        isError: true,
      );
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
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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
      if (mounted) {
        setState(() => _isLoadingAbsent = false);
      }
    }
  }

  bool _plantAllowsMissingVehicle({
    required String? plantName,
    required String? driverRole,
  }) {
    bool containsOffice(String? text) {
      if (text == null || text.isEmpty) {
        return false;
      }
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

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${DateFormat('dd-MM-yyyy').format(_selectedDate)} (${DateFormat('EEEE').format(_selectedDate)})';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Past Attendance Request',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF12355B),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(dateLabel),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _pickDate,
                    ),
                  ),
                  TextFormField(
                    controller: _inTimeController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'In Time'),
                    onTap: () => _pickTime(isIn: true),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Provide in time'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _outTimeController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Out Time'),
                    onTap: () => _pickTime(isIn: false),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Provide out time'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Reason',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: const Color(0xFFFFF4B8),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please describe the reason'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit'),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.event_busy, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Absent Days',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _isLoadingAbsent
                                  ? null
                                  : () => _changeAbsentMonth(-1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text(
                              DateFormat('MMM yyyy').format(_absentMonth),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            IconButton(
                              onPressed: _isLoadingAbsent
                                  ? null
                                  : () => _changeAbsentMonth(1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            _CalendarWeekdayLabel('S'),
                            _CalendarWeekdayLabel('M'),
                            _CalendarWeekdayLabel('T'),
                            _CalendarWeekdayLabel('W'),
                            _CalendarWeekdayLabel('T'),
                            _CalendarWeekdayLabel('F'),
                            _CalendarWeekdayLabel('S'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_isLoadingAbsent)
                          const Center(child: AppLoader(size: 96))
                        else if (_absentError != null)
                          Text(
                            _absentError!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.red),
                          )
                        else
                          Builder(
                            builder: (context) {
                              final days = _buildAbsentCalendarDays();
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 6,
                                  childAspectRatio: 1.1,
                                ),
                                itemCount: days.length,
                                itemBuilder: (context, index) {
                                  final day = days[index];
                                  if (day == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final key = _dayKey(day);
                                  final records =
                                      _absentRecordsByDay[key] ?? const [];
                                  final isAbsent =
                                      records.isEmpty && !_isFuture(day);
                                  final isToday = day == _today;
                                  return Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isAbsent
                                          ? const Color(0xFFFFCDD2)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isToday
                                            ? const Color(0xFF1C6DD0)
                                            : Colors.blueGrey.shade100,
                                      ),
                                    ),
                                    child: Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isAbsent
                                            ? Colors.red.shade700
                                            : Colors.black87,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Note: this section will show only absent days',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.blueGrey,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    if (now.day <= 3) {
      return ninetyDaysAgo;
    }
    final firstOfCurrentMonth = DateTime(now.year, now.month, 1);
    return firstOfCurrentMonth.isAfter(ninetyDaysAgo)
        ? firstOfCurrentMonth
        : ninetyDaysAgo;
  }
}

class _CalendarWeekdayLabel extends StatelessWidget {
  const _CalendarWeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey,
            ),
      ),
    );
  }
}
