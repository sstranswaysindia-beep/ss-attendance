import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/models/advance_transaction.dart';
import '../../core/models/app_user.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

// ─── Premium Design Tokens ───
const _gradientStart = Color(0xFF0A1628);
const _gradientMid = Color(0xFF142B47);
const _gradientEnd = Color(0xFF1B3A5C);
const _accentTeal = Color(0xFF00BFA6);
const _heroRed = Color(0xFFFF5E5E);
const _surfaceBg = Color(0xFFF0F4F8);
const _surfaceCard = Color(0xFFF8FAFF);

class KhataAllExpensesScreen extends StatefulWidget {
  const KhataAllExpensesScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<KhataAllExpensesScreen> createState() => _KhataAllExpensesScreenState();
}

class _KhataAllExpensesScreenState extends State<KhataAllExpensesScreen>
    with TickerProviderStateMixin {
  static const String _allMonthsKey = '__all_months__';
  static const String _driversUrl =
      'https://sstranswaysindia.com/api/mobile/get_drivers.php';
  static const String _transactionsUrl =
      'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php';
  static const String _tripDetailsUrl =
      'https://sstranswaysindia.com/api/mobile/driver_trip_details_by_date.php';
  static const String _attendanceByDateUrl =
      'https://sstranswaysindia.com/api/mobile/driver_attendance_by_date.php';

  bool _isLoadingDrivers = false;
  bool _isLoadingExpenses = false;
  bool _isLoadingExpenseDetails = false;
  String? _error;

  List<_DriverOption> _drivers = const <_DriverOption>[];
  _DriverOption? _selectedDriver;
  final TextEditingController _driverSearchController = TextEditingController();
  final FocusNode _driverSearchFocusNode = FocusNode();
  List<_DriverOption> _filteredDrivers = const <_DriverOption>[];
  bool _showDriverList = false;
  List<_ExpenseEntry> _expenses = const <_ExpenseEntry>[];
  Map<String, List<_TripDetail>> _tripDetailsByDate = const {};
  Map<String, _AttendanceDayStatus> _attendanceByDate = const {};
  String? _selectedMonthKey;
  late List<_MonthOption> _monthOptions;

  // Animations
  late AnimationController _heroController;
  late AnimationController _staggerController;

  Map<int, String> get _vehicleNumberById {
    final mapped = <int, String>{};
    for (final vehicle in widget.user.availableVehicles) {
      final id = int.tryParse(vehicle.id) ?? 0;
      final number = vehicle.vehicleNumber.trim();
      if (id > 0 && number.isNotEmpty) {
        mapped[id] = number;
      }
    }
    return mapped;
  }

  @override
  void initState() {
    super.initState();
    _selectedMonthKey = null;
    _monthOptions = const <_MonthOption>[];
    _setupAnimations();
    if (widget.user.canViewDocuments) {
      _loadDriversAndExpenses();
    }
  }

  void _setupAnimations() {
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _heroController.forward();
    _staggerController.forward();
  }

  @override
  void dispose() {
    _driverSearchController.dispose();
    _driverSearchFocusNode.dispose();
    _heroController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _loadDriversAndExpenses() async {
    setState(() {
      _isLoadingDrivers = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse(_driversUrl),
        headers: const {'Content-Type': 'application/json'},
      );
      if (response.statusCode != 200) {
        throw Exception('Unable to load drivers.');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') {
        throw Exception(
          payload['error']?.toString() ?? 'Unable to load drivers.',
        );
      }
      final rawDrivers = payload['drivers'] as List<dynamic>? ?? const [];
      final drivers = rawDrivers
          .whereType<Map<String, dynamic>>()
          .map(_DriverOption.fromJson)
          .toList(growable: false);
      final options = <_DriverOption>[
        const _DriverOption(id: '', name: 'All Drivers', plant: ''),
        ...drivers,
      ];
      if (!mounted) return;
      setState(() {
        _drivers = options;
        _filteredDrivers = options;
        _selectedDriver = null;
        _driverSearchController.clear();
        _expenses = const <_ExpenseEntry>[];
        _tripDetailsByDate = const {};
        _attendanceByDate = const {};
        _monthOptions = const <_MonthOption>[];
        _selectedMonthKey = null;
      });
      _staggerController.forward(from: 0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDrivers = false;
        });
      }
    }
  }

  Future<List<_ExpenseEntry>> _fetchDriverExpenses(_DriverOption driver) async {
    final response = await http.post(
      Uri.parse(_transactionsUrl),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'driverId': driver.id, 'limit': 20000}),
    );
    if (response.statusCode != 200) {
      return const <_ExpenseEntry>[];
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (payload['status'] != 'ok') {
      return const <_ExpenseEntry>[];
    }
    final items = (payload['transactions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdvanceTransaction.fromJson)
        .toList(growable: false);
    final visibleTransactions = items
        .where((tx) => tx.isExpense)
        .toList(growable: false);
    final recordsToShow = visibleTransactions.isNotEmpty
        ? visibleTransactions
        : items;
    return recordsToShow
        .map(
          (tx) => _ExpenseEntry(
            driverId: driver.id,
            driverName: driver.name,
            driverPlant: driver.plant,
            transaction: tx,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_ExpenseEntry>> _fetchExpensesForSelection(
    _DriverOption selected,
  ) async {
    if (!selected.isAll) {
      return _fetchDriverExpenses(selected);
    }

    final driversToLoad = _drivers
        .where((item) => !item.isAll && item.id.trim().isNotEmpty)
        .toList(growable: false);
    final merged = <_ExpenseEntry>[];

    for (final driver in driversToLoad) {
      try {
        final items = await _fetchDriverExpenses(driver);
        merged.addAll(items);
      } catch (_) {
        // Skip failed drivers so one bad response doesn't blank the full list.
      }
    }

    return merged;
  }

  Future<void> _loadExpenses() async {
    final selected = _selectedDriver;
    if (selected == null) return;

    setState(() {
      _isLoadingExpenses = true;
      _isLoadingExpenseDetails = false;
      _error = null;
    });
    try {
      final merged = await _fetchExpensesForSelection(selected);
      merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _expenses = merged;
        _tripDetailsByDate = const {};
        _attendanceByDate = const {};
        _monthOptions = _buildMonthOptions(merged);
        final now = DateTime.now();
        final currentMonthKey =
            '${now.year}-${now.month.toString().padLeft(2, '0')}';
        if (_monthOptions.isEmpty) {
          _selectedMonthKey = null;
        } else if (_monthOptions.any((item) => item.key == currentMonthKey)) {
          _selectedMonthKey = currentMonthKey;
        } else if (_selectedMonthKey == null ||
            !_monthOptions.any((item) => item.key == _selectedMonthKey)) {
          _selectedMonthKey = _monthOptions.first.key;
        }
        _isLoadingExpenses = false;
        _isLoadingExpenseDetails = true;
      });
      if (merged.isEmpty && mounted) {
        showAppToast(
          context,
          'No khata record found for the selected driver.',
          isError: true,
        );
      }
      _staggerController.forward(from: 0.2); // Re-animate list on load

      final tripMap = await _fetchTripDetailsForDaEntries(
        selected: selected,
        expenses: merged,
      );
      final attendanceMap = await _fetchAttendanceForDaEntries(
        selected: selected,
        expenses: merged,
      );
      if (!mounted || _selectedDriver?.id != selected.id) return;
      setState(() {
        _tripDetailsByDate = tripMap;
        _attendanceByDate = attendanceMap;
        _isLoadingExpenseDetails = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load expenses right now. Please try again.';
        _isLoadingExpenses = false;
        _isLoadingExpenseDetails = false;
      });
    }
  }

  Future<Map<String, List<_TripDetail>>> _fetchTripDetailsForDaEntries({
    required _DriverOption selected,
    required List<_ExpenseEntry> expenses,
  }) async {
    if (selected.isAll) return const {};

    final daEntries = expenses.where(_isDaCategory).toList(growable: false);
    if (daEntries.isEmpty) return const {};

    final dateKeys = daEntries.map((item) => item.dateKey).toSet().toList()
      ..sort();
    if (dateKeys.isEmpty) return const {};

    final from = dateKeys.first;
    final to = dateKeys.last;

    try {
      final response = await http.post(
        Uri.parse(_tripDetailsUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': selected.id, 'from': from, 'to': to}),
      );
      if (response.statusCode != 200) return const {};
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') return const {};
      final byDateRaw = payload['byDate'];
      if (byDateRaw is! Map) return const {};
      final mapped = <String, List<_TripDetail>>{};
      byDateRaw.forEach((key, value) {
        final dateKey = key.toString();
        final listRaw = value;
        if (listRaw is! List) {
          mapped[dateKey] = const <_TripDetail>[];
          return;
        }
        final trips = listRaw
            .whereType<Map>()
            .map((item) => _TripDetail.fromJson(item))
            .toList(growable: false);
        mapped[dateKey] = trips;
      });
      return mapped;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, _AttendanceDayStatus>> _fetchAttendanceForDaEntries({
    required _DriverOption selected,
    required List<_ExpenseEntry> expenses,
  }) async {
    if (selected.isAll) return const {};

    final daEntries = expenses.where(_isDaCategory).toList(growable: false);
    if (daEntries.isEmpty) return const {};

    final dateKeys = daEntries.map((item) => item.dateKey).toSet().toList()
      ..sort();
    if (dateKeys.isEmpty) return const {};

    final from = dateKeys.first;
    final to = dateKeys.last;

    try {
      final response = await http.post(
        Uri.parse(_attendanceByDateUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': selected.id, 'from': from, 'to': to}),
      );
      if (response.statusCode != 200) return const {};
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') return const {};
      final byDateRaw = payload['byDate'];
      if (byDateRaw is! Map) return const {};
      final mapped = <String, _AttendanceDayStatus>{};
      byDateRaw.forEach((key, value) {
        if (value is Map) {
          mapped[key.toString()] = _AttendanceDayStatus.fromJson(value);
        }
      });
      return mapped;
    } catch (_) {
      return const {};
    }
  }

  bool _isDaCategory(_ExpenseEntry entry) {
    final category = (entry.transaction.category ?? '').trim().toLowerCase();
    return category == 'da';
  }

  void _showDaTripDetails(
    _ExpenseEntry expense,
    List<_TripDetail> trips, {
    required bool hasTrip,
    _AttendanceDayStatus? attendanceStatus,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'DA Trip Details',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _gradientStart,
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.dateKey,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (hasTrip) ...[
                if (attendanceStatus != null) ...[
                  _buildInfoRow(
                    Icons.login_rounded,
                    'Check-in:',
                    _formatTimeBracket(attendanceStatus.firstIn),
                  ),
                  const SizedBox(height: 6),
                  _buildInfoRow(
                    Icons.logout_rounded,
                    'Check-out:',
                    _formatTimeBracket(attendanceStatus.lastOut),
                  ),
                  const SizedBox(height: 6),
                  _buildInfoRow(
                    Icons.schedule_rounded,
                    'Working Hours:',
                    _workingHoursLabel(attendanceStatus),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                ],
                for (final trip in trips) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _gradientStart.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${trip.tripId} • ${trip.vehicleNumber.isEmpty ? '-' : trip.vehicleNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: _gradientStart,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildMiniTripLabel('Plant', trip.plantName),
                        _buildMiniTripLabel('Status', trip.status),
                        _buildMiniTripLabel('Drivers', trip.drivers),
                        if (trip.helpers.isNotEmpty)
                          _buildMiniTripLabel('Helpers', trip.helpers),
                        if (trip.customers.isNotEmpty)
                          _buildMiniTripLabel('Customers', trip.customers),
                        if (trip.startDate.isNotEmpty ||
                            trip.endDate.isNotEmpty)
                          _buildMiniTripLabel(
                            'Trip Date',
                            '${trip.startDate}${trip.endDate.isNotEmpty ? ' → ${trip.endDate}' : ''}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ] else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _heroRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _heroRed.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: _heroRed),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No trip found on this day for the selected user.',
                          style: TextStyle(
                            color: _heroRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label ',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: _gradientStart,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniTripLabel(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  List<_MonthOption> _buildMonthOptions(List<_ExpenseEntry> entries) {
    final monthKeys = <String>{};
    for (final item in entries) {
      monthKeys.add(item.monthKey);
    }
    final sorted = monthKeys.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    return <_MonthOption>[
      const _MonthOption(key: _allMonthsKey, label: 'All Months'),
      ...sorted.map(
        (key) => _MonthOption(key: key, label: _formatMonthLabel(key)),
      ),
    ];
  }

  String _formatMonthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return key;
    }
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[month - 1]} $year';
  }

  List<_ExpenseEntry> get _visibleExpenses {
    if (_selectedMonthKey == null ||
        _selectedMonthKey!.trim().isEmpty ||
        _selectedMonthKey == _allMonthsKey) {
      return _expenses;
    }
    return _expenses
        .where((item) => item.monthKey == _selectedMonthKey)
        .toList(growable: false);
  }

  bool get _shouldBlockPop => false;

  void _handleBackPressed() {}

  void _restoreSelectedDriverSearch() {
    final selected = _selectedDriver;
    if (selected == null) return;
    _driverSearchController.value = TextEditingValue(
      text: selected.name,
      selection: TextSelection.collapsed(offset: selected.name.length),
    );
    _filteredDrivers = _drivers;
  }

  DateTime? _parseDbDateTime(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  }

  String _formatTimeBracket(String? raw) {
    final dt = _parseDbDateTime(raw);
    if (dt == null) return '-';
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final h = hour == 0 ? 12 : hour;
    return '$h:$minute $period';
  }

  String _workingHoursLabel(_AttendanceDayStatus? status) {
    if (status == null) return '-';
    final inTime = _parseDbDateTime(status.firstIn);
    final outTime = _parseDbDateTime(status.lastOut);
    if (inTime == null || outTime == null || !outTime.isAfter(inTime)) {
      return '-';
    }
    final totalMinutes = outTime.difference(inTime).inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  bool _isWorkingHoursAtLeast13(_AttendanceDayStatus? status) {
    if (status == null) return false;
    final inTime = _parseDbDateTime(status.firstIn);
    final outTime = _parseDbDateTime(status.lastOut);
    if (inTime == null || outTime == null || !outTime.isAfter(inTime)) {
      return false;
    }
    return outTime.difference(inTime).inMinutes >= (13 * 60);
  }

  void _filterDrivers(String searchText) {
    final query = searchText.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredDrivers = _drivers;
        _showDriverList = false;
      });
      return;
    }
    final filtered = _drivers
        .where((driver) {
          if (driver.isAll) return false;
          final haystack = '${driver.name} ${driver.plant}'.toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
    setState(() {
      _filteredDrivers = filtered;
      _showDriverList = true;
    });
  }

  Future<void> _selectDriver(_DriverOption driver) async {
    setState(() {
      _driverSearchController.text = driver.name;
      _selectedDriver = driver;
      _filteredDrivers = _drivers;
      _showDriverList = false;
      _selectedMonthKey = _allMonthsKey;
    });
    _driverSearchFocusNode.unfocus();
    await _loadExpenses();
  }

  Future<void> _submitDriverSearch() async {
    final query = _driverSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _showDriverList = false;
      });
      _driverSearchFocusNode.unfocus();
      return;
    }

    final exactMatch = _drivers
        .where((driver) {
          return !driver.isAll &&
              (driver.name.trim().toLowerCase() == query ||
                  driver.plant.trim().toLowerCase() == query ||
                  driver.displayName.toLowerCase() == query);
        })
        .toList(growable: false);

    if (exactMatch.length == 1) {
      await _selectDriver(exactMatch.first);
      return;
    }

    if (_filteredDrivers.length == 1) {
      await _selectDriver(_filteredDrivers.first);
      return;
    }

    if (_filteredDrivers.isNotEmpty) {
      await _selectDriver(_filteredDrivers.first);
      return;
    }

    setState(() {
      _showDriverList = false;
    });
    if (mounted) {
      showAppToast(context, 'No matching driver found.', isError: true);
    }
  }

  void _clearDriverSearch() {
    setState(() {
      if (_selectedDriver != null) {
        _restoreSelectedDriverSearch();
      } else {
        _driverSearchController.clear();
        _filteredDrivers = _drivers;
      }
      _showDriverList = false;
    });
    _driverSearchFocusNode.unfocus();
  }

  String? _normalizeReceiptUrl(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'https://sstranswaysindia.com${value.startsWith('/') ? value : '/$value'}';
  }

  Future<void> _openReceipt(_ExpenseEntry expense) async {
    final url = _normalizeReceiptUrl(expense.transaction.receiptPath);
    if (url == null) {
      showAppToast(context, 'No receipt attached.', isError: true);
      return;
    }
    final isPdf = url.toLowerCase().split('?').first.trim().endsWith('.pdf');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Receipt',
          style: TextStyle(fontWeight: FontWeight.w800, color: _gradientStart),
        ),
        content: SizedBox(
          width: 340,
          height: 420,
          child: isPdf
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: WebViewWidget(
                    controller: WebViewController()
                      ..setJavaScriptMode(JavaScriptMode.unrestricted)
                      ..loadRequest(Uri.parse(url)),
                  ),
                )
              : InteractiveViewer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: AppLoader(size: 36));
                      },
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Unable to load receipt image.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          Theme(
            data: Theme.of(context).copyWith(
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(foregroundColor: _gradientStart),
              ),
            ),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.canViewDocuments) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Khatabook',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          backgroundColor: _gradientEnd,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'You do not have permission to view Khatabook.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return _buildStableScreen(context);
  }

  Widget _buildStableScreen(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_shouldBlockPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: _surfaceBg,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: _gradientEnd,
          foregroundColor: Colors.white,
          title: const Text(
            'Khatabook',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadDriversAndExpenses,
          color: _gradientStart,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_gradientStart, _gradientEnd, _gradientMid],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'All Expenses',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Manage and track driver expenses',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 110),
                          child: _buildMonthFilterCard(inline: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildDriverSearchCard(),
              if (_showDriverList) ...[
                const SizedBox(height: 8),
                _buildDriverResultsCard(),
              ],
              const SizedBox(height: 16),
              _buildExpenseSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthFilterCard({bool inline = false}) {
    final monthDropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedMonthKey,
        isDense: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        dropdownColor: Colors.white,
        items: _monthOptions
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.key,
                child: Text(
                  option.label,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: inline ? _gradientStart : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _selectedMonthKey = value);
        },
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: inline ? 10 : 14,
        vertical: inline ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: inline ? Colors.white.withValues(alpha: 0.96) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inline
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFFD8E2F0),
        ),
      ),
      child: Row(
        children: [
          if (_isLoadingExpenses && _monthOptions.isEmpty)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else if (_selectedDriver == null)
            Text(
              inline ? 'Month' : 'Select driver',
              style: TextStyle(
                color: inline ? _gradientStart : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (inline)
            monthDropdown
          else
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: monthDropdown,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverSearchCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Search Driver',
            style: TextStyle(
              color: _accentTeal,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD8E2F0)),
          ),
          child: TextField(
            controller: _driverSearchController,
            focusNode: _driverSearchFocusNode,
            enabled: !_isLoadingDrivers,
            onChanged: _filterDrivers,
            textInputAction: TextInputAction.search,
            onTap: () {
              if (_driverSearchController.text.trim().isEmpty) return;
              setState(() {
                _showDriverList = true;
              });
            },
            onSubmitted: (_) => _submitDriverSearch(),
            decoration: InputDecoration(
              hintText: 'Enter name or plant...',
              prefixIcon: const Icon(
                Icons.person_search_rounded,
                color: _gradientStart,
              ),
              suffixIcon: _driverSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _clearDriverSearch,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverResultsCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _filteredDrivers.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No drivers found',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _filteredDrivers.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final driver = _filteredDrivers[index];
                  return ListTile(
                    onTap: () => _selectDriver(driver),
                    leading: CircleAvatar(
                      backgroundColor: _gradientStart.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.person_rounded,
                        color: _gradientStart,
                      ),
                    ),
                    title: Text(driver.name),
                    subtitle: driver.plant.trim().isNotEmpty
                        ? Text(driver.plant.trim())
                        : null,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildExpenseSection() {
    if (_isLoadingDrivers || _isLoadingExpenses) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: AppLoader(size: 80)),
      );
    }

    if (_error != null && _error!.trim().isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _heroRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _heroRed.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: _heroRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(
                  color: _heroRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_selectedDriver == null) {
      return _buildEmptyExpenseState('Select a driver to view expenses.');
    }

    final selectedName = _selectedDriver!.displayName;

    if (_expenses.isNotEmpty) {
      final visibleExpenses = _visibleExpenses;
      return Column(
        children: [
          if (_isLoadingExpenseDetails)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blueGrey.shade400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Loading attendance details...',
                    style: TextStyle(
                      color: Colors.blueGrey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ...visibleExpenses.map(_buildSimpleExpenseRow),
        ],
      );
    }

    if (_visibleExpenses.isEmpty) {
      return _buildEmptyExpenseState(
        _selectedMonthKey == _allMonthsKey || _selectedMonthKey == null
            ? 'No khata records found for $selectedName.'
            : 'No khata records found for $selectedName in this month.',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyExpenseState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleExpenseRow(_ExpenseEntry expense) {
    final rawCategory = (expense.transaction.category ?? '').trim();
    final isAdvanceTheme =
        expense.transaction.isAdvanceReceived ||
        rawCategory.toLowerCase().contains('advance');
    final category = rawCategory.isEmpty
        ? (isAdvanceTheme ? 'ADVANCE' : 'EXPENSE')
        : rawCategory;
    final rawDescription = expense.transaction.description.trim();
    final vehicleMatch = RegExp(
      r'vehicle:\s*([^\n]+)',
      caseSensitive: false,
    ).firstMatch(rawDescription);
    final vehicleFromDescription = vehicleMatch == null
        ? ''
        : vehicleMatch.group(1)?.trim() ?? '';
    final vehicleNumberById = _vehicleNumberById;
    final vehicleLabel = vehicleFromDescription.isNotEmpty
        ? 'Vehicle: $vehicleFromDescription'
        : expense.transaction.vehicleId != null
            ? (vehicleNumberById[expense.transaction.vehicleId!] != null
                  ? 'Vehicle: ${vehicleNumberById[expense.transaction.vehicleId!]!}'
                  : 'Vehicle: ${expense.transaction.vehicleId}')
            : '';
    final cleanedDescription = vehicleMatch == null
        ? rawDescription
        : rawDescription
              .replaceFirst(vehicleMatch.group(0) ?? '', '')
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim();
    final description = cleanedDescription.isEmpty
        ? 'No description'
        : cleanedDescription;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E2F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: isAdvanceTheme ? const Color(0xFF0F9D58) : _heroRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${expense.transaction.formattedDate}${expense.transaction.formattedTime.isNotEmpty ? ' • ${expense.transaction.formattedTime}' : ''}',
                  style: const TextStyle(
                    color: _gradientStart,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isAdvanceTheme
                        ? const Color(0xFFEAFBF5)
                        : const Color(0xFFFFF2F2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isAdvanceTheme
                          ? const Color(0xFF0F9D58)
                          : _heroRed,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (vehicleLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isAdvanceTheme
                          ? const Color(0xFFEAFBF5)
                          : const Color(0xFFF2F5FA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      vehicleLabel,
                      style: TextStyle(
                        color: isAdvanceTheme
                            ? const Color(0xFF0F9D58)
                            : _gradientStart,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF31435F),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '₹${expense.transaction.amount.toStringAsFixed(0)}',
            style: TextStyle(
              color: isAdvanceTheme ? const Color(0xFF0F9D58) : _heroRed,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// Data models unchanged below
class _DriverOption {
  const _DriverOption({
    required this.id,
    required this.name,
    required this.plant,
  });

  factory _DriverOption.fromJson(Map<String, dynamic> json) {
    return _DriverOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString().trim(),
      plant: (json['plant'] ?? '').toString().trim(),
    );
  }

  final String id;
  final String name;
  final String plant;

  bool get isAll => id.isEmpty;
  String get displayName => plant.isEmpty ? name : '$name (${plant.trim()})';

  @override
  String toString() => plant.isEmpty ? name : '$name $plant';
}

class _ExpenseEntry {
  const _ExpenseEntry({
    required this.driverId,
    required this.driverName,
    required this.driverPlant,
    required this.transaction,
  });

  final String driverId;
  final String driverName;
  final String driverPlant;
  final AdvanceTransaction transaction;

  String get driverDisplay => driverPlant.trim().isEmpty
      ? '$driverName (#$driverId)'
      : '$driverName (${driverPlant.trim()})';

  DateTime get timestamp {
    final raw = transaction.createdAt.trim();
    if (raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return DateTime.parse(raw);
    } catch (_) {
      try {
        return DateTime.parse(raw.replaceFirst(' ', 'T'));
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
  }

  String get monthKey {
    final time = timestamp;
    final month = time.month.toString().padLeft(2, '0');
    return '${time.year}-$month';
  }

  String get dateKey {
    final time = timestamp;
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}

class _MonthOption {
  const _MonthOption({required this.key, required this.label});
  final String key;
  final String label;
}

class _TripDetail {
  const _TripDetail({
    required this.tripId,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.vehicleNumber,
    required this.plantName,
    required this.drivers,
    required this.helpers,
    required this.customers,
  });

  factory _TripDetail.fromJson(Map<dynamic, dynamic> json) {
    return _TripDetail(
      tripId: int.tryParse(json['tripId']?.toString() ?? '') ?? 0,
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      vehicleNumber: (json['vehicleNumber'] ?? '').toString(),
      plantName: (json['plantName'] ?? '').toString(),
      drivers: (json['drivers'] ?? '').toString(),
      helpers: (json['helpers'] ?? '').toString(),
      customers: (json['customers'] ?? '').toString(),
    );
  }

  final int tripId;
  final String startDate;
  final String endDate;
  final String status;
  final String vehicleNumber;
  final String plantName;
  final String drivers;
  final String helpers;
  final String customers;
}

class _AttendanceDayStatus {
  const _AttendanceDayStatus({
    required this.hasIn,
    required this.hasOut,
    this.firstIn,
    this.lastOut,
  });

  factory _AttendanceDayStatus.fromJson(Map<dynamic, dynamic> json) {
    bool asBool(dynamic value) {
      if (value == true) return true;
      final raw = (value ?? '').toString().trim().toLowerCase();
      return raw == '1' || raw == 'true' || raw == 'y' || raw == 'yes';
    }

    return _AttendanceDayStatus(
      hasIn: asBool(json['hasIn']),
      hasOut: asBool(json['hasOut']),
      firstIn: (json['firstIn'] ?? '').toString().trim().isEmpty
          ? null
          : json['firstIn'].toString(),
      lastOut: (json['lastOut'] ?? '').toString().trim().isEmpty
          ? null
          : json['lastOut'].toString(),
    );
  }

  final bool hasIn;
  final bool hasOut;
  final String? firstIn;
  final String? lastOut;
}
