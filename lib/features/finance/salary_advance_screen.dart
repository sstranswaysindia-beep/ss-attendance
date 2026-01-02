import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../../core/models/advance_transaction.dart';
import '../../core/models/advance_request.dart';
import '../../core/models/app_user.dart';
import '../../core/models/salary_credit.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/finance_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';

const Color _financePrimaryColor = Color(0xFF12355B);

class SalaryAdvanceScreen extends StatefulWidget {
  const SalaryAdvanceScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<SalaryAdvanceScreen> createState() => _SalaryAdvanceScreenState();
}

class _SalaryAdvanceScreenState extends State<SalaryAdvanceScreen> {
  final FinanceRepository _financeRepository = FinanceRepository();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  bool _isLoading = false;
  String? _errorMessage;
  List<SalaryCredit> _salaryCredits = const [];
  List<AdvanceRequest> _advanceRequests = const [];
  List<AdvanceTransaction> _advanceTransactions = const [];
  int _daysWorkedForSelectedMonth = 0;
  String _advanceStatusFilter = 'All';
  bool _isSubmittingAdvance = false;
  final Set<String> _salaryDeleting = <String>{};
  final Set<String> _advanceDeleting = <String>{};

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  static final NumberFormat _inrNumber = NumberFormat.decimalPattern('en_IN');

  // Categories that represent *additional income* (not advance/expense balance).
  // These are the same labels used by backend `transaction_descriptions`.
  static const Set<String> _additionalIncomeCategories = <String>{
    'DA',
    'MEDICAL',
    'UNIFORM',
    'TRAVEL',
    'INCENTIVE',
    'ROOM',
    'EXTRA',
    'PAPER',
  };

  // Payroll constants (adjust to match billing rules if they change).
  static const double _employeePfRate = 0.12; // 12%
  static const double _employeeEsiRate = 0.0075; // 0.75%
  static const double _esiWageCeiling = 21000; // Common ESI wage ceiling

  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late String _selectedMonth;
  late int _selectedYear;
  List<int> _availableYears = const [];
  String? _resolvedEsiNumber;
  String? _resolvedUanNumber;

  String _formatInr(double value) {
    return '₹${_inrNumber.format(value.round())}';
  }

  String _formatInrSigned(double value) {
    final formatted = _inrNumber.format(value.abs().round());
    return value < 0 ? '-₹$formatted' : '₹$formatted';
  }

  bool _hasNonEmptyValue(String? value) {
    if (value == null) return false;
    final v = value.trim();
    if (v.isEmpty) return false;
    final normalized = v.toLowerCase();
    return normalized != '0' && normalized != 'null' && normalized != 'none';
  }

  String? _resolveIncomeCategory(AdvanceTransaction t) {
    final fromCategory = t.category?.trim().toUpperCase();
    if (fromCategory != null && fromCategory.isNotEmpty) {
      return fromCategory;
    }

    // Backward-compatibility: older rows may not have `category` stored, but
    // their description often starts with the label (e.g. "DA - ...").
    final desc = t.description.trim().toUpperCase();
    if (desc.isEmpty) return null;
    final match = RegExp(
      r'^(DA|MEDICAL|UNIFORM|TRAVEL|INCENTIVE|ROOM|EXTRA|PAPER)\b',
    ).firstMatch(desc);
    return match?.group(1);
  }

  bool _isAdditionalIncomeTxn(AdvanceTransaction t) {
    final category = _resolveIncomeCategory(t);
    if (category == null || category.isEmpty) return false;
    // Important: Only treat these categories as "additional income" when they
    // are actually CREDITED to the employee (advance_received).
    //
    // In many flows, categories like ROOM/PAPER/EXTRA are recorded as expenses.
    // Those should remain part of the normal advance/expense balance (not shown
    // as income).
    return t.type == 'advance_received' &&
        _additionalIncomeCategories.contains(category);
  }

  DateTime? _tryParseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  DateTime? _tryParseDateTimeFlexible(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    final normalized = raw.contains(' ') && !raw.contains('T')
        ? raw.replaceFirst(' ', 'T')
        : raw;
    return DateTime.tryParse(normalized);
  }

  String _monthKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

  int _getMonthIndex(String monthName) {
    final idx = _monthNames.indexOf(monthName);
    return idx >= 0 ? (idx + 1) : DateTime.now().month;
  }

  String _selectedMonthLabel() {
    final mm = _getMonthIndex(_selectedMonth);
    final dt = DateTime(_selectedYear, mm, 1);
    return DateFormat('MMM yy').format(dt);
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6),
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
      child: Padding(padding: padding, child: child),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = _monthNames[now.month - 1];
    _selectedYear = now.year;
    _availableYears = [now.year, now.year - 1, now.year - 2];
    _resolvedEsiNumber = widget.user.esiNumber;
    _resolvedUanNumber = widget.user.uanNumber;
    _loadFinanceData();
    _loadPfEsiFromDriver();
  }

  Future<void> _loadPfEsiFromDriver() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_driver_pf_esi.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          // Be lenient: backend accepts both driverId and driver_id.
          'driverId': driverId,
          'driver_id': driverId,
        }),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'ok') return;

      if (!mounted) return;
      setState(() {
        // Support both camelCase and snake_case payloads (server versions vary).
        final esi =
            data['esiNumber'] ??
            data['esi_number'] ??
            data['esi'] ??
            data['esi_no'];
        final uan =
            data['uanNumber'] ??
            data['uan_number'] ??
            data['uan'] ??
            data['uan_no'];
        _resolvedEsiNumber =
            (esi != null &&
                esi.toString().trim().isNotEmpty &&
                esi.toString().toLowerCase() != 'null')
            ? esi.toString().trim()
            : null;
        _resolvedUanNumber =
            (uan != null &&
                uan.toString().trim().isNotEmpty &&
                uan.toString().toLowerCase() != 'null')
            ? uan.toString().trim()
            : null;
      });
    } catch (_) {
      // ignore PF/ESI fetch errors; UI will fall back to login payload.
    }
  }

  Future<List<AdvanceTransaction>> _fetchAdvanceTransactions(
    String driverId,
  ) async {
    final response = await http.post(
      Uri.parse(
        'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'driverId': driverId, 'limit': 5000}),
    );

    if (response.statusCode != 200) {
      throw FinanceFailure(
        'Unable to load advance transactions (status: ${response.statusCode}).',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'ok') {
      throw FinanceFailure(
        data['error']?.toString() ?? 'Unable to load advance transactions.',
      );
    }
    final list = data['transactions'] as List<dynamic>? ?? const [];
    return list
        .map((e) => AdvanceTransaction.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<int> _fetchDaysWorkedForSelectedMonth(String driverId) async {
    final monthIndex = _getMonthIndex(_selectedMonth);
    final month = DateTime(_selectedYear, monthIndex, 1);
    final records = await _attendanceRepository.fetchHistory(
      driverId: driverId,
      month: month,
    );

    final uniqueDays = <String>{};
    for (final r in records) {
      final dt =
          _tryParseDateTimeFlexible(r.inTime) ??
          _tryParseDateTimeFlexible(r.outTime);
      if (dt == null) continue;
      if (_monthKey(dt) != _monthKey(month)) continue;
      uniqueDays.add(
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
      );
    }
    return uniqueDays.length;
  }

  void _updateAvailableYears() {
    final years = <int>{DateTime.now().year};

    for (final c in _salaryCredits) {
      final dt = _tryParseDate(c.creditedOn);
      if (dt != null) years.add(dt.year);
    }
    for (final t in _advanceTransactions) {
      final dt = _tryParseDate(t.createdAt);
      if (dt != null) years.add(dt.year);
    }

    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    _availableYears = sorted;
    if (!_availableYears.contains(_selectedYear)) {
      _selectedYear = _availableYears.first;
    }
  }

  void _showMonthSelector() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        var tempYear = _selectedYear;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Select Month',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: tempYear,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: _availableYears
                        .map(
                          (y) => DropdownMenuItem(
                            value: y,
                            child: Text(y.toString()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v == null) return;
                      setSheetState(() => tempYear = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: ListView.separated(
                      itemCount: _monthNames.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final month = _monthNames[index];
                        final selected =
                            tempYear == _selectedYear &&
                            month == _selectedMonth;
                        return ListTile(
                          title: Text(month),
                          trailing: selected
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedYear = tempYear;
                              _selectedMonth = month;
                            });
                            Navigator.of(context).pop();
                            final driverId = widget.user.driverId;
                            if (driverId != null && driverId.isNotEmpty) {
                              _fetchDaysWorkedForSelectedMonth(driverId).then((
                                value,
                              ) {
                                if (!mounted) return;
                                setState(
                                  () => _daysWorkedForSelectedMonth = value,
                                );
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadFinanceData() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _errorMessage = 'Driver mapping missing. Contact admin.';
        _salaryCredits = const [];
        _advanceRequests = const [];
        _advanceTransactions = const [];
        _daysWorkedForSelectedMonth = 0;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final salaryFuture = _financeRepository.fetchSalaryCredits(driverId);
      final advanceFuture = _financeRepository.fetchAdvanceRequests(
        driverId,
        status: widget.user.role == UserRole.supervisor
            ? (_advanceStatusFilter == 'All' ? null : _advanceStatusFilter)
            : null,
      );
      final advanceTxnFuture = _fetchAdvanceTransactions(driverId);

      final results = await Future.wait([
        salaryFuture,
        advanceFuture,
        advanceTxnFuture,
      ]);

      if (!mounted) return;

      setState(() {
        _salaryCredits = results[0] as List<SalaryCredit>;
        _advanceRequests = results[1] as List<AdvanceRequest>;
        _advanceTransactions = results[2] as List<AdvanceTransaction>;
      });
      _updateAvailableYears();
      final days = await _fetchDaysWorkedForSelectedMonth(driverId);
      if (mounted) {
        setState(() => _daysWorkedForSelectedMonth = days);
      }
    } on FinanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load salary and advance details.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onAdvanceStatusChanged(String? status) async {
    if (status == null) return;
    if (widget.user.role != UserRole.supervisor) return;
    setState(() => _advanceStatusFilter = status);
    await _loadFinanceData();
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseSalary = widget.user.salary;
    final isSupervisor = widget.user.role == UserRole.supervisor;
    final selectedMonthIndex = _getMonthIndex(_selectedMonth);
    final selectedKey = _monthKey(
      DateTime(_selectedYear, selectedMonthIndex, 1),
    );

    // Same as Khata Book "You will get/give" for selected month:
    // balance = (advance_received) - (expense), but exclude "additional income" categories
    // so DA/Medical/Uniform/etc don't reduce salary.
    final additionalIncomeByCategory = <String, double>{};
    double additionalIncomeTotal = 0.0;
    final advanceBalanceForSelectedMonth = _advanceTransactions.fold<double>(
      0.0,
      (sum, t) {
        final dt = _tryParseDate(t.createdAt);
        if (dt == null) return sum;
        if (_monthKey(dt) != selectedKey) return sum;

        if (_isAdditionalIncomeTxn(t)) {
          final key = _resolveIncomeCategory(t)!;
          additionalIncomeByCategory[key] =
              (additionalIncomeByCategory[key] ?? 0) + t.amount;
          additionalIncomeTotal += t.amount;
          return sum;
        }

        if (t.type == 'advance_received') return sum + t.amount;
        if (t.type == 'expense') return sum - t.amount;
        return sum;
      },
    );

    final salaryCreditsForSelectedMonth = _salaryCredits
        .where((c) {
          final dt = _tryParseDate(c.creditedOn);
          if (dt == null) return false;
          return _monthKey(dt) == selectedKey;
        })
        .toList(growable: false);

    final advanceRequestsForSelectedMonth = _advanceRequests
        .where((r) {
          final dt =
              _tryParseDateTimeFlexible(r.requestedAt) ??
              _tryParseDateTimeFlexible(r.disbursedAt);
          if (dt == null) return false;
          return _monthKey(dt) == selectedKey;
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Salary & Advances',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: _financePrimaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadFinanceData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      backgroundColor: Colors.grey[200],
      body: _isLoading
          ? const Center(child: AppLoader())
          : _errorMessage != null
          ? Center(
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Salary + Credits widget (white)
                  _whiteCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Salary & Credits',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showMonthSelector,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade100,
                                foregroundColor: Colors.black87,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_selectedMonthLabel()),
                            ),
                          ],
                        ),
                        Builder(
                          builder: (context) {
                            final hasPf = _hasNonEmptyValue(_resolvedUanNumber);
                            final hasEsi = _hasNonEmptyValue(
                              _resolvedEsiNumber,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(
                                    label: Text(hasPf ? 'PF' : 'PF (NA)'),
                                    backgroundColor: hasPf
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    labelStyle: TextStyle(
                                      color: hasPf
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Chip(
                                    label: Text(hasEsi ? 'ESI' : 'ESI (NA)'),
                                    backgroundColor: hasEsi
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    labelStyle: TextStyle(
                                      color: hasEsi
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final monthIndex = selectedMonthIndex;
                            final daysInMonth = DateTime(
                              _selectedYear,
                              monthIndex + 1,
                              0,
                            ).day;
                            final monthlySalary =
                                double.tryParse(baseSalary ?? '') ?? 0.0;
                            final daysWorked = _daysWorkedForSelectedMonth;
                            final perDay = daysInMonth > 0
                                ? (monthlySalary / daysInMonth)
                                : 0.0;
                            final monthlyEarned = perDay * daysWorked;
                            final grossEarned =
                                monthlyEarned + additionalIncomeTotal;

                            final hasPf = _hasNonEmptyValue(_resolvedUanNumber);
                            final hasEsi = _hasNonEmptyValue(
                              _resolvedEsiNumber,
                            );
                            final employeePf = hasPf
                                ? (grossEarned * _employeePfRate)
                                : 0.0;
                            final employeeEsi = hasEsi
                                ? ((grossEarned <= _esiWageCeiling)
                                      ? (grossEarned * _employeeEsiRate)
                                      : 0.0)
                                : 0.0;

                            final salaryCreditedCalc =
                                grossEarned -
                                advanceBalanceForSelectedMonth -
                                employeePf -
                                employeeEsi;

                            Widget row(
                              String label,
                              String value, {
                              Color? valueColor,
                              FontWeight valueWeight = FontWeight.w700,
                            }) {
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    value,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: valueColor,
                                      fontWeight: valueWeight,
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.black.withOpacity(0.06),
                                ),
                              ),
                              child: Column(
                                children: [
                                  row(
                                    'Monthly salary (total)',
                                    _formatInr(monthlySalary),
                                  ),
                                  const SizedBox(height: 6),
                                  row(
                                    'Days worked (${_selectedMonthLabel()})',
                                    '$daysWorked',
                                  ),
                                  const SizedBox(height: 6),
                                  row(
                                    'Monthly earned (${_selectedMonthLabel()})',
                                    _formatInr(monthlyEarned),
                                  ),
                                  if (additionalIncomeByCategory
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Additional income',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ...additionalIncomeByCategory.entries
                                        .where((e) => e.value.abs() > 0.0001)
                                        .map((entry) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: row(
                                              entry.key,
                                              _formatInrSigned(entry.value),
                                              valueColor: entry.value >= 0
                                                  ? Colors.green.shade700
                                                  : Colors.red.shade700,
                                              valueWeight: FontWeight.w700,
                                            ),
                                          );
                                        }),
                                    row(
                                      'Total additional income',
                                      _formatInrSigned(additionalIncomeTotal),
                                      valueColor: additionalIncomeTotal >= 0
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      valueWeight: FontWeight.w800,
                                    ),
                                    const SizedBox(height: 6),
                                    row(
                                      'Gross earned (earned + income)',
                                      _formatInrSigned(grossEarned),
                                      valueColor: grossEarned >= 0
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      valueWeight: FontWeight.w800,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  row(
                                    'Advance balance (${_selectedMonthLabel()})',
                                    _formatInrSigned(
                                      advanceBalanceForSelectedMonth,
                                    ),
                                    valueColor:
                                        advanceBalanceForSelectedMonth >= 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                  if (hasPf) ...[
                                    const SizedBox(height: 6),
                                    row(
                                      'Employee PF deduction',
                                      _formatInrSigned(-employeePf),
                                      valueColor: Colors.red.shade700,
                                      valueWeight: FontWeight.w700,
                                    ),
                                  ],
                                  if (hasEsi) ...[
                                    const SizedBox(height: 6),
                                    row(
                                      'Employee ESI deduction',
                                      _formatInrSigned(-employeeEsi),
                                      valueColor: Colors.red.shade700,
                                      valueWeight: FontWeight.w700,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  row(
                                    'Salary credited (net)',
                                    _formatInrSigned(salaryCreditedCalc),
                                    valueColor: salaryCreditedCalc >= 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                    valueWeight: FontWeight.w800,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const Divider(height: 24),
                        Text(
                          'Salary Credits',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (salaryCreditsForSelectedMonth.isEmpty)
                          Builder(
                            builder: (context) {
                              final nextMonth = DateTime(
                                _selectedYear,
                                selectedMonthIndex + 1,
                                15,
                              );
                              final nextLabel = DateFormat(
                                'MMM yy',
                              ).format(nextMonth);
                              return Text(
                                '${_selectedMonthLabel()} salary will be credited on 15th of $nextLabel',
                                style: theme.textTheme.bodyMedium,
                              );
                            },
                          )
                        else
                          ...salaryCreditsForSelectedMonth.map((credit) {
                            final isDeleting = _salaryDeleting.contains(
                              credit.salaryCreditId,
                            );
                            final tile = ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.account_balance_wallet),
                              title: Text(_formatInr(credit.amount)),
                              subtitle: Text(
                                'Credited on ${_formatDate(credit.creditedOn)}',
                              ),
                              trailing: isDeleting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: AppLoader(size: 16),
                                    )
                                  : null,
                            );

                            // keep existing delete behavior (supervisors)
                            return isSupervisor
                                ? Dismissible(
                                    key: ValueKey(
                                      'salary-${credit.salaryCreditId}',
                                    ),
                                    direction: DismissDirection.endToStart,
                                    confirmDismiss: (_) async {
                                      await _confirmDeleteSalary(credit);
                                      return false;
                                    },
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                    ),
                                    child: tile,
                                  )
                                : tile;
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Advance Requests widget (white)
                  _whiteCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Advance Requests',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (isSupervisor)
                              SizedBox(
                                width: 170,
                                child: DropdownButtonFormField<String>(
                                  value: _advanceStatusFilter,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'All',
                                      child: Text('All'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Pending',
                                      child: Text('Pending'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Approved',
                                      child: Text('Approved'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Rejected',
                                      child: Text('Rejected'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Disbursed',
                                      child: Text('Disbursed'),
                                    ),
                                  ],
                                  onChanged: _onAdvanceStatusChanged,
                                  decoration: const InputDecoration(
                                    labelText: 'Status',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (advanceRequestsForSelectedMonth.isEmpty)
                          Text(
                            'No advance requests for ${_selectedMonthLabel()}.',
                            style: theme.textTheme.bodyMedium,
                          )
                        else
                          ...advanceRequestsForSelectedMonth.map((request) {
                            final statusColor = switch (request.status) {
                              'Approved' => Colors.green,
                              'Disbursed' => Colors.blue,
                              'Rejected' => Colors.red,
                              'Pending' => Colors.orange,
                              _ => Colors.grey,
                            };
                            final isDeleting = _advanceDeleting.contains(
                              request.advanceRequestId,
                            );

                            final tile = ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.request_page),
                              title: Text(_formatInr(request.amount)),
                              subtitle: Text(
                                '${request.purpose}\nRequested: ${_formatDate(request.requestedAt)}',
                              ),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Chip(
                                    label: Text(request.status),
                                    backgroundColor: statusColor.withOpacity(
                                      0.15,
                                    ),
                                    labelStyle: TextStyle(color: statusColor),
                                  ),
                                  if (request.disbursedAt != null)
                                    Text(
                                      'Disbursed: ${_formatDate(request.disbursedAt)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  if (isDeleting)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: AppLoader(size: 16),
                                      ),
                                    ),
                                ],
                              ),
                            );

                            if (!isSupervisor) return tile;

                            return Dismissible(
                              key: ValueKey(
                                'advance-${request.advanceRequestId}',
                              ),
                              direction: request.status == 'Pending'
                                  ? DismissDirection.endToStart
                                  : DismissDirection.none,
                              confirmDismiss: (_) async {
                                await _confirmDeleteAdvance(request);
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                              ),
                              child: tile,
                            );
                          }),
                        if (isSupervisor) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _openAdvanceRequestSheet,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Request Advance'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _openAdvanceRequestSheet() async {
    if (widget.user.role != UserRole.supervisor) {
      showAppToast(context, 'Only supervisors can manage advance requests');
      return;
    }
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'Driver mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    _amountController.clear();
    _purposeController.clear();
    _notesController.clear();
    final formKey = GlobalKey<FormState>();

    final shouldReload = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request Advance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter amount';
                        }
                        final parsed = double.tryParse(value.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Amount must be greater than zero';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _purposeController,
                      decoration: const InputDecoration(labelText: 'Purpose'),
                      maxLength: 120,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter purpose';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                      maxLines: 3,
                      maxLength: 255,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSubmittingAdvance
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    final amount = double.parse(
                                      _amountController.text.trim(),
                                    );
                                    final purpose = _purposeController.text
                                        .trim();
                                    final notes = _notesController.text.trim();

                                    modalSetState(
                                      () => _isSubmittingAdvance = true,
                                    );
                                    setState(() => _isSubmittingAdvance = true);

                                    try {
                                      await _financeRepository
                                          .submitAdvanceRequest(
                                            driverId: driverId,
                                            amount: amount,
                                            purpose: purpose,
                                            notes: notes.isEmpty ? null : notes,
                                          );
                                      if (!mounted) return;
                                      modalSetState(
                                        () => _isSubmittingAdvance = false,
                                      );
                                      setState(
                                        () => _isSubmittingAdvance = false,
                                      );
                                      showAppToast(
                                        context,
                                        'Advance requested successfully.',
                                      );
                                      Navigator.of(context).pop(true);
                                    } on FinanceFailure catch (error) {
                                      modalSetState(
                                        () => _isSubmittingAdvance = false,
                                      );
                                      setState(
                                        () => _isSubmittingAdvance = false,
                                      );
                                      showAppToast(
                                        context,
                                        error.message,
                                        isError: true,
                                      );
                                    } catch (_) {
                                      modalSetState(
                                        () => _isSubmittingAdvance = false,
                                      );
                                      setState(
                                        () => _isSubmittingAdvance = false,
                                      );
                                      showAppToast(
                                        context,
                                        'Unable to submit request.',
                                        isError: true,
                                      );
                                    }
                                  },
                            child: _isSubmittingAdvance
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: AppLoader(size: 20),
                                  )
                                : const Text('Submit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldReload == true) {
      await _loadFinanceData();
    }
  }

  Future<void> _confirmDeleteSalary(SalaryCredit credit) async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'Driver mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Salary Credit'),
        content: const Text('Remove this salary credit entry?'),
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

    setState(() => _salaryDeleting.add(credit.salaryCreditId));
    try {
      await _financeRepository.deleteSalaryCredit(
        driverId: driverId,
        salaryCreditId: credit.salaryCreditId,
      );
      if (!mounted) return;
      setState(() {
        _salaryCredits = List.of(_salaryCredits)
          ..removeWhere((item) => item.salaryCreditId == credit.salaryCreditId);
        _salaryDeleting.remove(credit.salaryCreditId);
      });
      showAppToast(context, 'Salary credit removed.');
    } on FinanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _salaryDeleting.remove(credit.salaryCreditId));
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salaryDeleting.remove(credit.salaryCreditId));
      showAppToast(context, 'Unable to delete salary credit.', isError: true);
    }
  }

  Future<void> _confirmDeleteAdvance(AdvanceRequest request) async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'Driver mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Advance Request'),
        content: const Text('Cancel this advance request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
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

    setState(() => _advanceDeleting.add(request.advanceRequestId));
    try {
      await _financeRepository.deleteAdvanceRequest(
        driverId: driverId,
        advanceRequestId: request.advanceRequestId,
      );
      if (!mounted) return;
      setState(() {
        _advanceRequests = List.of(_advanceRequests)
          ..removeWhere(
            (item) => item.advanceRequestId == request.advanceRequestId,
          );
        _advanceDeleting.remove(request.advanceRequestId);
      });
      showAppToast(context, 'Advance request removed.');
    } on FinanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _advanceDeleting.remove(request.advanceRequestId));
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _advanceDeleting.remove(request.advanceRequestId));
      showAppToast(context, 'Unable to delete advance request.', isError: true);
    }
  }
}
