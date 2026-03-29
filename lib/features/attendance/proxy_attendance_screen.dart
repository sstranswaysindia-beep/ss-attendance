import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/app_user.dart';
import '../../core/models/proxy_employee.dart';
import '../../core/services/proxy_attendance_repository.dart';
import '../../core/widgets/app_toast.dart';

// ─── Design tokens (matches salary_advance_screen.dart) ────────────────────
const Color _primaryColor = Color(0xFF12355B);
const Color _accentColor = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A1628);
const Color _gradientEnd = Color(0xFF1B3A5C);
const Color _surfaceCard = Color(0xFFF8FAFF);
const Color _pageBackground = Color(0xFFF0F4F8);

class ProxyAttendanceScreen extends StatefulWidget {
  const ProxyAttendanceScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<ProxyAttendanceScreen> createState() => _ProxyAttendanceScreenState();
}

class _ProxyAttendanceScreenState extends State<ProxyAttendanceScreen> {
  final ProxyAttendanceRepository _repository = ProxyAttendanceRepository();
  final DateFormat _dateFormatter = DateFormat('dd MMM yyyy • HH:mm');
  final DateFormat _selectedDateFormatter = DateFormat('dd MMM yyyy');
  final DateFormat _storageDateFormatter = DateFormat('yyyy-MM-dd');

  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<ProxyEmployee> _employees = const [];
  List<ProxyPlantOption> _plants = const [];
  ProxyEmployee? _selectedEmployee;
  String? _preferredEmployeeDriverId;
  String? _selectedPlantId;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _notesController = TextEditingController();
  final Map<String, bool> _platformSelections = <String, bool>{};
  final Map<String, String> _notesByDriver = <String, String>{};
  bool _platformSelected = false;
  static const String _platformTag = 'Rest';

  @override
  void initState() {
    super.initState();
    _notesController.addListener(_handleNotesChanged);
    _restoreFiltersAndLoad();
  }

  @override
  void dispose() {
    _notesController.removeListener(_handleNotesChanged);
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _repository.fetchEmployees(
        supervisorUserId: widget.user.id,
        plantId: _selectedPlantId,
        attendanceDate: _selectedDate,
      );
      if (!mounted) return;

      ProxyEmployee? updatedSelection;
      if (_selectedEmployee != null) {
        updatedSelection = response.employees.firstWhere(
          (employee) => employee.driverId == _selectedEmployee!.driverId,
          orElse: () => _selectedEmployee!,
        );
        if (!response.employees.contains(updatedSelection)) {
          updatedSelection = null;
        }
      } else if (_preferredEmployeeDriverId != null) {
        updatedSelection = response.employees.cast<ProxyEmployee?>().firstWhere(
          (employee) => employee?.driverId == _preferredEmployeeDriverId,
          orElse: () => null,
        );
      }

      setState(() {
        _employees = response.employees;
        _plants = response.plants;
        _selectedEmployee =
            updatedSelection ??
            (response.employees.isNotEmpty ? response.employees.first : null);
        _isLoading = false;
      });
      if (_selectedEmployee != null) {
        _preferredEmployeeDriverId = _selectedEmployee!.driverId;
      }
      await _persistFilters();
      _applySelectionState();
    } on ProxyAttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
        _employees = const [];
      });
      _applySelectionState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load proxy records.';
        _employees = const [];
      });
      _applySelectionState();
    }
  }

  Future<void> _submit(String action) async {
    final employee = _selectedEmployee;
    final selectedDateLabel = _selectedDateFormatter.format(_selectedDate);
    if (employee == null) {
      showAppToast(context, 'Select an employee first.', isError: true);
      return;
    }
    if (_isSelf(employee)) {
      showAppToast(
        context,
        'You cannot proxy mark attendance for your own account.',
        isError: true,
      );
      return;
    }
    if (action == 'check_in' && employee.attendanceCompletedOn(_selectedDate)) {
      showAppToast(
        context,
        'Attendance already completed for this employee on $selectedDateLabel.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final notes = _notesController.text.trim();
      final payloadNotes = notes.isEmpty ? null : notes;
      await _repository.submit(
        supervisorUserId: widget.user.id,
        driverId: employee.driverId,
        userId: employee.userId,
        action: action,
        notes: payloadNotes,
        attendanceDate: _selectedDate,
      );

      if (!mounted) return;
      showAppToast(
        context,
        action == 'check_in'
            ? 'Check-in recorded for $selectedDateLabel.'
            : 'Check-out recorded for $selectedDateLabel.',
      );
      await _loadData();
    } on ProxyAttendanceFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to submit attendance.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _pickAttendanceDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Select Attendance Date',
    );
    if (picked == null || !mounted) {
      return;
    }
    final normalized = DateTime(picked.year, picked.month, picked.day);
    if (normalized ==
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)) {
      return;
    }
    setState(() {
      _selectedDate = normalized;
    });
    await _persistFilters();
    await _loadData();
  }

  Future<void> _restoreFiltersAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final String keyPrefix = _prefsKeyPrefix;
    final savedPlantId = prefs.getString('${keyPrefix}plant_id');
    final savedEmployeeDriverId = prefs.getString(
      '${keyPrefix}employee_driver_id',
    );
    final savedDate = prefs.getString('${keyPrefix}attendance_date');
    final parsedDate = savedDate == null
        ? null
        : DateTime.tryParse(savedDate) ??
              (() {
                try {
                  return _storageDateFormatter.parseStrict(savedDate);
                } catch (_) {
                  return null;
                }
              })();

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedPlantId = savedPlantId != null && savedPlantId.isNotEmpty
          ? savedPlantId
          : null;
      _preferredEmployeeDriverId =
          savedEmployeeDriverId != null && savedEmployeeDriverId.isNotEmpty
          ? savedEmployeeDriverId
          : null;
      if (parsedDate != null) {
        _selectedDate = DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
        );
      }
    });

    await _loadData();
  }

  Future<void> _persistFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final String keyPrefix = _prefsKeyPrefix;
    final plantId = _selectedPlantId;
    final employeeDriverId =
        _selectedEmployee?.driverId ?? _preferredEmployeeDriverId;

    if (plantId == null || plantId.isEmpty) {
      await prefs.remove('${keyPrefix}plant_id');
    } else {
      await prefs.setString('${keyPrefix}plant_id', plantId);
    }

    if (employeeDriverId == null || employeeDriverId.isEmpty) {
      await prefs.remove('${keyPrefix}employee_driver_id');
    } else {
      await prefs.setString('${keyPrefix}employee_driver_id', employeeDriverId);
    }

    await prefs.setString(
      '${keyPrefix}attendance_date',
      _storageDateFormatter.format(_selectedDate),
    );
  }

  String get _prefsKeyPrefix => 'proxy_attendance_${widget.user.id}_';

  // ─── Premium helper widgets ───────────────────────────────────────────────

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    EdgeInsetsGeometry? margin,
    Color? color,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color ?? _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _sectionTitle(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 4, top: 1),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, _accentColor],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    IconData? icon,
    required VoidCallback? onTap,
    required List<Color> colors,
    bool isLoading = false,
  }) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: disabled
                ? [Colors.grey.shade300, Colors.grey.shade400]
                : colors,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: colors.last.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Screen ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: _isLoading
          ? Container(
              color: _pageBackground,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                ),
              ),
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    expandedHeight: 138,
                    floating: false,
                    pinned: true,
                    centerTitle: true,
                    backgroundColor: _gradientStart,
                    foregroundColor: Colors.white,
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      IconButton(
                        onPressed: _isLoading ? null : _loadData,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Reload',
                      ),
                    ],
                    title: const Text(
                      'Proxy Attendance',
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
                            colors: [
                              _gradientStart,
                              _gradientEnd,
                              Color(0xFF0D4F6B),
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 34, 20, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Supervisor info hero card
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Gradient avatar
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              _accentColor,
                                              Color(0xFF007C6E),
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.4,
                                            ),
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            widget.user.displayName.isNotEmpty
                                                ? widget.user.displayName[0]
                                                      .toUpperCase()
                                                : 'S',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.user.displayName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Supervisor · ID ${widget.user.id}',
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Employee count badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF7CFFB2,
                                          ).withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF7CFFB2,
                                            ).withOpacity(0.4),
                                          ),
                                        ),
                                        child: Text(
                                          '${_employees.length} emp',
                                          style: const TextStyle(
                                            color: Color(0xFF7CFFB2),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
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
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(20),
                      child: Container(
                        height: 20,
                        decoration: const BoxDecoration(
                          color: _pageBackground,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ];
              },
              body: _buildContent(context),
            ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _glassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 36,
                    color: Colors.orange.shade400,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                _buildGradientButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onTap: _loadData,
                  colors: const [_primaryColor, _accentColor],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _accentColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
        children: [
          // ── Plant filter ─────────────────────────────────────
          if (_plants.isNotEmpty) ...[
            _sectionTitle('Filter by Plant', icon: Icons.factory_rounded),
            _buildPlantFilter(context),
            const SizedBox(height: 2),
          ],

          _sectionTitle('Attendance Date', icon: Icons.calendar_month_rounded),
          _buildDateFilter(context),
          const SizedBox(height: 2),

          // ── Employee selector ─────────────────────────────────
          _sectionTitle('Select Employee', icon: Icons.people_alt_rounded),
          _buildEmployeeSelector(context),

          const SizedBox(height: 2),

          // ── Employee summary card ─────────────────────────────
          if (_selectedEmployee != null) ...[
            _sectionTitle('Employee Details', icon: Icons.badge_rounded),
            _buildEmployeeSummary(context, _selectedEmployee!),
            const SizedBox(height: 2),
          ],

          // ── Action buttons ────────────────────────────────────
          if (_selectedEmployee != null) ...[
            _buildActionButtons(context, _selectedEmployee!),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildPlantFilter(BuildContext context) {
    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPlantId,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: _accentColor),
          dropdownColor: Colors.white,
          hint: const Text(
            'All plants',
            style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text(
                'All plants',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
            ..._plants.map(
              (plant) => DropdownMenuItem<String>(
                value: plant.plantId,
                child: Text(
                  plant.plantName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _selectedPlantId = value;
            });
            _persistFilters();
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildDateFilter(BuildContext context) {
    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isSubmitting ? null : _pickAttendanceDate,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: _accentColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDateFormatter.format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Load attendance for the selected date',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more_rounded, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSelector(BuildContext context) {
    if (_employees.isEmpty) {
      return _glassCard(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: 32,
                color: Colors.blueGrey.shade300,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No proxy-enabled employees found for ${_selectedDateFormatter.format(_selectedDate)}.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ProxyEmployee>(
          value: _selectedEmployee,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: _accentColor),
          dropdownColor: Colors.white,
          hint: const Text(
            'Select employee',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          items: _employees
              .map(
                (employee) => DropdownMenuItem<ProxyEmployee>(
                  value: employee,
                  child: Text(
                    '${employee.fullName} (${employee.roleBadge})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (employee) {
            setState(() {
              _selectedEmployee = employee;
              _preferredEmployeeDriverId = employee?.driverId;
            });
            _persistFilters();
            _applySelectionState();
          },
        ),
      ),
    );
  }

  Widget _buildEmployeeSummary(BuildContext context, ProxyEmployee employee) {
    final Color statusColor = employee.hasOpenShiftOn(_selectedDate)
        ? Colors.orange.shade600
        : employee.attendanceCompletedOn(_selectedDate)
        ? Colors.green.shade600
        : Colors.blueGrey.shade500;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gradient avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryColor, _accentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    employee.fullName.isNotEmpty
                        ? employee.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      employee.roleBadge,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (employee.plantName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        employee.plantName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _statusPill(employee.statusLabelFor(_selectedDate), statusColor),
            ],
          ),

          const SizedBox(height: 12),
          Container(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Last Check-in',
                  value: employee.lastCheckInDisplayFor(
                    _selectedDate,
                    _dateFormatter,
                  ),
                  icon: Icons.login_rounded,
                  color: Colors.green.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Last Check-out',
                  value: employee.lastCheckOutDisplayFor(
                    _selectedDate,
                    _dateFormatter,
                  ),
                  icon: Icons.logout_rounded,
                  color: Colors.indigo.shade400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ProxyEmployee employee) {
    final bool isSelf = _isSelf(employee);
    final bool completedForSelectedDate = employee.attendanceCompletedOn(
      _selectedDate,
    );
    final bool hasOpenShiftForSelectedDate = employee.hasOpenShiftOn(
      _selectedDate,
    );
    final String selectedDateLabel = _selectedDateFormatter.format(
      _selectedDate,
    );
    if (isSelf) {
      return _glassCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.info_rounded,
                color: Colors.blue.shade400,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'You are viewing your own profile. Proxy actions are disabled for self.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (completedForSelectedDate) {
      return _glassCard(
        color: const Color(0xFFF0FFF8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.verified_rounded,
                color: Colors.green.shade500,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attendance Complete',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Attendance already completed for $selectedDateLabel.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Check-in / Check-out buttons ──────────────────────
        Row(
          children: [
            Expanded(
              child: _buildGradientButton(
                label: 'Check-in',
                icon: Icons.login_rounded,
                onTap: (!_isSubmitting && !hasOpenShiftForSelectedDate)
                    ? () => _submit('check_in')
                    : null,
                colors: const [Color(0xFF1B8F3A), Color(0xFF34C759)],
                isLoading: _isSubmitting && !hasOpenShiftForSelectedDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGradientButton(
                label: 'Check-out',
                icon: Icons.logout_rounded,
                onTap: (!_isSubmitting && hasOpenShiftForSelectedDate)
                    ? () => _submit('check_out')
                    : null,
                colors: const [Color(0xFFF4B400), Color(0xFFFFD54F)],
                isLoading: _isSubmitting && hasOpenShiftForSelectedDate,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Rest toggle chip ───────────────────────────────────
        GestureDetector(
          onTap: _isSubmitting
              ? null
              : () => _setPlatformSelected(!_platformSelected),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: _platformSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF5C35CC), Color(0xFF8A63D2)],
                    )
                  : null,
              color: _platformSelected ? null : _surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _platformSelected
                    ? Colors.transparent
                    : Colors.grey.shade200,
              ),
              boxShadow: _platformSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF5C35CC).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Icon(
                  _platformSelected
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  color: _platformSelected
                      ? Colors.white
                      : Colors.grey.shade400,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Text(
                  'Mark as Rest',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _platformSelected
                        ? Colors.white
                        : const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── Notes field ────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFE082)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFBC02D).withOpacity(0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _notesController,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
              labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              hintText: 'Add any relevant notes…',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                color: _accentColor.withOpacity(0.7),
              ),
              floatingLabelStyle: const TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.w600,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _accentColor, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.transparent),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Logic methods (unchanged) ──────────────────────────────────────────

  void _applySelectionState() {
    final employee = _selectedEmployee;
    if (employee == null) {
      _setNotesText('');
      _storeNotes('');
      setState(() => _platformSelected = false);
      return;
    }
    final driverId = employee.driverId;
    final bool selected = _platformSelections[driverId] ?? false;
    var notes = _notesByDriver[driverId] ?? _notesController.text;
    notes = selected ? _appendPlatformTag(notes) : _removePlatformTag(notes);
    _setNotesText(notes);
    _storeNotes(notes);
    setState(() => _platformSelected = selected);
  }

  void _setPlatformSelected(bool selected) {
    final employee = _selectedEmployee;
    if (employee == null) {
      return;
    }
    setState(() {
      _platformSelected = selected;
      _platformSelections[employee.driverId] = selected;
      final updated = selected
          ? _appendPlatformTag(_notesController.text)
          : _removePlatformTag(_notesController.text);
      _setNotesText(updated);
      _storeNotes(updated);
    });
  }

  void _handleNotesChanged() {
    _storeNotes(_notesController.text);
  }

  void _storeNotes(String value) {
    final employee = _selectedEmployee;
    if (employee == null) {
      return;
    }
    if (value.isEmpty) {
      _notesByDriver.remove(employee.driverId);
    } else {
      _notesByDriver[employee.driverId] = value;
    }
  }

  void _setNotesText(String value) {
    _notesController.removeListener(_handleNotesChanged);
    _notesController.text = value;
    _notesController.selection = TextSelection.fromPosition(
      TextPosition(offset: value.length),
    );
    _notesController.addListener(_handleNotesChanged);
  }

  bool _containsPlatformTag(String text) => text.contains(_platformTag);

  String _appendPlatformTag(String text) {
    final trimmed = text.trim();
    if (_containsPlatformTag(trimmed)) {
      return trimmed.isEmpty ? _platformTag : trimmed;
    }
    if (trimmed.isEmpty) {
      return _platformTag;
    }
    return '$trimmed | $_platformTag';
  }

  String _removePlatformTag(String text) {
    var updated = text.replaceAll(' | $_platformTag', '');
    updated = updated.replaceAll(_platformTag, '');
    updated = updated.replaceAll(RegExp(r'\s*\|\s*$'), '');
    updated = updated.replaceAll(RegExp(r'^\s*\|\s*'), '');
    updated = updated.replaceAll(RegExp(r'\s*\|\s*'), ' | ');
    return updated.trim();
  }

  bool _isSelf(ProxyEmployee employee) {
    final driverId = widget.user.driverId;
    if (driverId != null && driverId.isNotEmpty) {
      return driverId == employee.driverId;
    }
    return widget.user.id == employee.userId;
  }
}
