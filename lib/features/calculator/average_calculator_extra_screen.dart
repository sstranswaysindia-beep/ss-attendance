import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/average_calculator_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/services/notification_service.dart';

class AverageCalculatorExtraScreen extends StatefulWidget {
  const AverageCalculatorExtraScreen({super.key});

  @override
  State<AverageCalculatorExtraScreen> createState() =>
      _AverageCalculatorExtraScreenState();
}

class _AverageCalculatorExtraScreenState
    extends State<AverageCalculatorExtraScreen> with WidgetsBindingObserver {
  static const int _initialCount = 20;
  static const int _stepCount = 10;
  static const TextStyle _dropdownTextStyle = TextStyle(
    fontSize: 14,
    color: Colors.black,
    fontFamily: 'Josefin Sans',
  );
  final AverageCalculatorRepository _repository =
      AverageCalculatorRepository();
  final NotificationService _notificationService = NotificationService();

  final TextEditingController _entryDateController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _initialController = TextEditingController();
  final TextEditingController _finalController = TextEditingController();
  final TextEditingController _runningController = TextEditingController();
  final TextEditingController _avgValueController = TextEditingController();
  final TextEditingController _fuelQtyController = TextEditingController();
  final TextEditingController _fuelTakenController = TextEditingController();
  final TextEditingController _dieselDiffController = TextEditingController();
  final TextEditingController _fuelPriceController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _currentAvgController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();
  final TextEditingController _avgFuelAmountController =
      TextEditingController();
  final TextEditingController _driverSearchController =
      TextEditingController();

  List<AveragePlant> _plants = const [];
  List<AverageVehicle> _vehicles = const [];
  List<AverageDriver> _drivers = const [];
  List<AverageDriver> _filteredDrivers = const [];
  List<AverageEntry> _entries = const [];
  List<AverageEntry> _filteredEntries = const [];
  Map<String, List<SpecialLedgerRow>> _specialMap = const {};
  SpecialBounds? _specialBounds;

  int? _selectedPlantId;
  int? _selectedVehicleId;
  AverageDriver? _selectedDriver;
  String _selectedMonth = '';
  String _exportMonth = '';
  List<String> _monthOptions = const [];
  bool _showValues = false;
  bool _isLoading = false;
  bool _isLoadingEntries = false;
  bool _isSubmitting = false;
  bool _isLoadingPlants = false;
  bool _isLoadingDrivers = false;
  String? _driversError;
  bool _showDriverList = false;
  int _shownCount = 0;

  DateTime _entryDate = DateTime.now();
  DateTime _minEntryDate = DateTime.now();
  DateTime _maxEntryDate = DateTime.now();

  Timer? _refreshTimer;
  bool _isFormDirty = false;
  bool _suppressDirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationService.requestBellHide();
    _setupDefaultRange();
    _entryDateController.text = _formatDate(_entryDate);
    _loadDrivers();
    _loadPlants();
    _wireCalculations();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationService.releaseBellHide();
    _refreshTimer?.cancel();
    _entryDateController.dispose();
    _nameController.dispose();
    _initialController.dispose();
    _finalController.dispose();
    _runningController.dispose();
    _avgValueController.dispose();
    _fuelQtyController.dispose();
    _fuelTakenController.dispose();
    _dieselDiffController.dispose();
    _fuelPriceController.dispose();
    _amountController.dispose();
    _currentAvgController.dispose();
    _totalController.dispose();
    _avgFuelAmountController.dispose();
    _driverSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshEntries();
    }
  }

  void _setupDefaultRange() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final prevMonthFirst = DateTime(now.year, now.month - 1, 1);
    _minEntryDate = prevMonthFirst;
    _maxEntryDate = lastDay;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_selectedVehicleId != null && mounted) {
        _refreshEntries();
      }
    });
  }

  void _wireCalculations() {
    _initialController.addListener(_updateRunning);
    _finalController.addListener(_updateRunning);
    _avgValueController.addListener(_calcFields);
    _fuelTakenController.addListener(_calcFields);
    _fuelPriceController.addListener(_calcFields);

    _nameController.addListener(_markFormDirty);
    _initialController.addListener(_markFormDirty);
    _finalController.addListener(_markFormDirty);
    _avgValueController.addListener(_markFormDirty);
    _fuelTakenController.addListener(_markFormDirty);
    _fuelPriceController.addListener(_markFormDirty);
  }

  Future<void> _loadDrivers() async {
    setState(() {
      _isLoadingDrivers = true;
      _driversError = null;
    });
    try {
      final drivers = await _repository.fetchDrivers();
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _filteredDrivers = drivers;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _drivers = const [];
        _filteredDrivers = const [];
        _driversError = 'Unable to load drivers.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingDrivers = false);
      }
    }
  }

  void _selectDriver(AverageDriver? driver) {
    setState(() {
      _selectedDriver = driver;
      _nameController.text = driver?.name ?? '';
      _driverSearchController.text = driver?.name ?? '';
      _showDriverList = false;
    });
    _markFormDirty();
  }

  Future<void> _loadPlants() async {
    setState(() {
      _isLoadingPlants = true;
    });
    try {
      final plants = await _repository.fetchPlants();
      if (!mounted) return;
      setState(() {
        _plants = plants;
      });
    } catch (_) {
      _showMessage('Unable to load plants.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPlants = false;
        });
      }
    }
  }

  Future<void> _loadVehicles(int plantId) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final vehicles = await _repository.fetchVehicles(plantId);
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
      });
    } catch (_) {
      _showMessage('Unable to load vehicles.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshEntries() async {
    final vehicleId = _selectedVehicleId;
    if (vehicleId == null) {
      return;
    }
    if (_isLoadingEntries || _isSubmitting) {
      return;
    }
    await _loadEntries(vehicleId, silent: true);
  }

  Future<void> _loadEntries(int vehicleId, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingEntries = true;
      });
    }
    try {
      final entries = await _repository.fetchEntries(vehicleId);
      entries.sort((a, b) {
        final aDate = DateTime.tryParse(a.entryDate);
        final bDate = DateTime.tryParse(b.entryDate);
        if (aDate != null && bDate != null) {
          final dateCompare = bDate.compareTo(aDate);
          if (dateCompare != 0) return dateCompare;
        }
        return b.id.compareTo(a.id);
      });
      if (!mounted) return;
      setState(() {
        _entries = entries;
      });
      await _loadSpecialMap(vehicleId);
      _rebuildMonthOptions();
      _applyMonthFilter();
      if (!silent && !_isFormDirty) {
        _resetEntryFormDefaults();
      }
    } catch (_) {
      if (!silent) {
        _showMessage('Unable to load entries.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEntries = false;
        });
      }
    }
  }

  Future<void> _loadSpecialBounds(int vehicleId) async {
    try {
      final bounds = await _repository.fetchSpecialBounds(vehicleId);
      if (!mounted) return;
      setState(() {
        _specialBounds = bounds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _specialBounds = null;
      });
    }
  }

  Future<void> _loadSpecialMap(int vehicleId) async {
    final range = _defaultEntryRange();
    try {
      final map = await _repository.fetchSpecialMap(
        vehicleId: vehicleId,
        from: range.$1,
        to: range.$2,
      );
      if (!mounted) return;
      setState(() {
        _specialMap = map;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _specialMap = const {};
      });
    }
  }

  (String, String) _defaultEntryRange() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final prevMonthFirst = DateTime(now.year, now.month - 1, 1);
    return (_formatDate(prevMonthFirst), _formatDate(lastDay));
  }

  void _rebuildMonthOptions() {
    final months = _entries
        .map((entry) => _monthKeyFromDate(entry.entryDate))
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final sorted = months.reversed.toList();
    setState(() {
      _monthOptions = sorted;
      if (_selectedMonth.isNotEmpty && !_monthOptions.contains(_selectedMonth)) {
        _selectedMonth = '';
      }
      if (_exportMonth.isNotEmpty && !_monthOptions.contains(_exportMonth)) {
        _exportMonth = '';
      }
    });
  }

  void _applyMonthFilter() {
    final month = _selectedMonth;
    final filtered = month.isEmpty
        ? _entries
        : _entries
            .where(
              (entry) =>
                  _monthKeyFromDate(entry.entryDate) == month,
            )
            .toList();
    setState(() {
      _filteredEntries = filtered;
      _shownCount = _filteredEntries.isEmpty
          ? 0
          : _filteredEntries.length.clamp(0, _initialCount);
    });
  }

  void _selectPlant(int? plantId) {
    if (plantId == null) return;
    setState(() {
      _selectedPlantId = plantId;
      _selectedVehicleId = null;
      _vehicles = const [];
      _entries = const [];
      _filteredEntries = const [];
      _selectedMonth = '';
      _specialBounds = null;
      _specialMap = const {};
    });
    _loadVehicles(plantId);
    _resetEntryFormDefaults(clearVehicle: true);
  }

  void _selectVehicle(int? vehicleId) {
    setState(() {
      _selectedVehicleId = vehicleId;
    });
    if (vehicleId == null) {
      setState(() {
        _entries = const [];
        _filteredEntries = const [];
        _specialBounds = null;
        _specialMap = const {};
      });
      _resetEntryFormDefaults(clearVehicle: true);
      return;
    }
    _loadEntries(vehicleId);
    _loadSpecialBounds(vehicleId);
  }

  void _resetEntryFormDefaults({bool clearVehicle = false}) {
    _isFormDirty = false;
    _suppressDirty = true;
    _entryDate = DateTime.now();
    _entryDateController.text = _formatDate(_entryDate);
    if (clearVehicle) {
      _selectedDriver = null;
      _nameController.clear();
      _driverSearchController.clear();
      _filteredDrivers = _drivers;
      _showDriverList = false;
      _initialController.clear();
      _finalController.clear();
      _runningController.clear();
      _avgValueController.clear();
      _fuelQtyController.text = '0.00';
      _fuelTakenController.clear();
      _dieselDiffController.text = '0.00';
      _fuelPriceController.clear();
      _amountController.text = '0.0000';
      _currentAvgController.text = '0.00';
      _totalController.text = '0.00';
      _avgFuelAmountController.text = '0.00';
      _suppressDirty = false;
      return;
    }

    final latest = _entries.isNotEmpty ? _entries.first : null;
    if (latest != null) {
      _initialController.text = latest.finalReading ?? '';
      _avgValueController.text = latest.avgValue ?? '';
    } else {
      _initialController.clear();
      _avgValueController.clear();
    }
    _finalController.clear();
    _runningController.clear();
    _fuelQtyController.text = '0.00';
    _fuelTakenController.clear();
    _dieselDiffController.text = '0.00';
    _fuelPriceController.clear();
    _amountController.text = '0.0000';
    _currentAvgController.text = '0.00';
    _totalController.text = '0.00';
    _avgFuelAmountController.text = '0.00';
    _calcFields();
    _suppressDirty = false;
  }

  void _markFormDirty() {
    if (_suppressDirty) return;
    if (!_isFormDirty) {
      _isFormDirty = true;
    }
  }

  void _updateRunning() {
    final initial = _parseNumber(_initialController.text);
    final finalVal = _parseNumber(_finalController.text);
    final running = finalVal > initial ? finalVal - initial : 0;
    _runningController.text = running.toStringAsFixed(0);
    _calcFields();
  }

  void _calcFields() {
    final running = _parseDouble(_runningController.text);
    final avgValue = _parseDouble(_avgValueController.text);
    final fuelTaken = _parseDouble(_fuelTakenController.text);
    final fuelPrice = _parseDouble(_fuelPriceController.text);

    final fuelQty = avgValue > 0 ? (running / avgValue) : 0;
    _fuelQtyController.text = fuelQty.toStringAsFixed(2);

    final avgFuelAmount = fuelQty * fuelPrice;
    _avgFuelAmountController.text = avgFuelAmount.isFinite
        ? avgFuelAmount.toStringAsFixed(2)
        : '0.00';

    final dieselDiff = fuelTaken - fuelQty;
    _dieselDiffController.text = dieselDiff.isFinite
        ? dieselDiff.toStringAsFixed(2)
        : '0.00';

    final currentAvg = fuelTaken > 0 ? (running / fuelTaken) : 0;
    _currentAvgController.text = currentAvg.isFinite
        ? currentAvg.toStringAsFixed(2)
        : '0.00';

    final total = (fuelPrice > 0 && fuelTaken > 0) ? fuelPrice * fuelTaken : 0;
    _totalController.text =
        total.isFinite ? total.toStringAsFixed(2) : '0.00';

    final amount = (fuelPrice > 0 && dieselDiff.isFinite)
        ? fuelPrice * dieselDiff
        : 0;
    _amountController.text =
        amount.isFinite ? amount.toStringAsFixed(4) : '0.0000';
  }

  double _parseNumber(String value) {
    final trimmed = value.replaceAll(',', '').trim();
    return double.tryParse(trimmed) ?? 0;
  }

  double _parseDouble(String value) => _parseNumber(value);

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateDisplay(String isoDate) {
    if (isoDate.length < 10) return isoDate;
    final parts = isoDate.substring(0, 10).split('-');
    if (parts.length != 3) return isoDate;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  String _monthKeyFromDate(String isoDate) {
    if (isoDate.length < 7) return '';
    return isoDate.substring(0, 7);
  }

  String _monthLabel(String monthKey) {
    if (monthKey.length != 7) return monthKey;
    final parts = monthKey.split('-');
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 1;
    const names = [
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
    final label = names[(month - 1).clamp(0, 11)];
    return '$label $year';
  }

  SpecialLedgerRow? _pickBestSpecialRow(AverageEntry entry) {
    if (entry.entryDate.isEmpty) return null;
    final key = entry.entryDate.substring(0, 10);
    final list = _specialMap[key];
    if (list == null || list.isEmpty) return null;
    if (list.length == 1) return list.first;

    final entryVol = _parseNullable(entry.fuelTaken);
    final entryPrice = _parseNullable(entry.fuelPrice);

    if (entryVol == null || entryPrice == null) return list.first;

    SpecialLedgerRow? best;
    var bestScore = double.infinity;

    for (final row in list) {
      final rowVol = row.volume;
      final rowPrice = row.price;
      if (rowVol == null || rowPrice == null) continue;

      final volDiff = (entryVol - rowVol).abs();
      final priceDiff = (entryPrice - rowPrice).abs();
      var score = (volDiff * 1000) + (priceDiff * 100);

      final exactVol = volDiff < 0.0001;
      final exactPrice = priceDiff < 0.01;
      if (exactVol && exactPrice) {
        score -= 1000000;
      } else if (exactVol || exactPrice) {
        score -= 20000;
      }

      if (score < bestScore) {
        bestScore = score;
        best = row;
      }
    }

    return best ?? list.first;
  }

  double? _parseNullable(String? value) {
    if (value == null) return null;
    final trimmed = value.replaceAll(',', '').trim();
    return double.tryParse(trimmed);
  }

  Color? _fuelMatchColor(String? entryValue, double? specialValue) {
    final entry = _parseNullable(entryValue);
    if (entry == null || specialValue == null) return null;
    if ((entry - specialValue).abs() < 0.0001) {
      return Colors.green.shade200;
    }
    final entryInt = entry.truncate();
    final specialInt = specialValue.truncate();
    if (entryInt == specialInt) {
      return Colors.amber.shade200;
    }
    return Colors.red.shade200;
  }

  Color? _totalMatchColor(String? entryTotal, double? specialAmount) {
    final entry = _parseNullable(entryTotal);
    if (entry == null || specialAmount == null) return null;
    if (entry.round() == specialAmount.round()) {
      return Colors.green.shade200;
    }
    if ((entry - specialAmount).abs() <= 2) {
      return Colors.amber.shade200;
    }
    return Colors.red.shade200;
  }

  Future<void> _submitEntry() async {
    if (_isSubmitting) return;
    final plantId = _selectedPlantId;
    final vehicleId = _selectedVehicleId;
    if (plantId == null || vehicleId == null) {
      _showMessage('Select plant and vehicle first.', isError: true);
      return;
    }

    if (_finalController.text.trim().isEmpty) {
      _showMessage('Final reading is required.', isError: true);
      return;
    }

    if (_selectedDriver == null) {
      _showMessage('Select driver name.', isError: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final payload = {
      'plant_id': plantId.toString(),
      'vehicle_id': vehicleId.toString(),
      'driver_id': _selectedDriver!.id.toString(),
      'entry_date': _entryDateController.text.trim(),
      'name': _nameController.text.trim(),
      'initial_reading': _initialController.text.replaceAll(',', '').trim(),
      'final_reading': _finalController.text.replaceAll(',', '').trim(),
      'running': _runningController.text.replaceAll(',', '').trim(),
      'avg_value': _avgValueController.text.trim(),
      'fuel_qty': _fuelQtyController.text.trim(),
      'fuel_taken': _fuelTakenController.text.trim(),
      'diesel_diff': _dieselDiffController.text.trim(),
      'fuel_price': _fuelPriceController.text.trim(),
      'amount': _amountController.text.trim(),
      'current_avg': _currentAvgController.text.trim(),
      'total': _totalController.text.trim(),
      'avg_fuel_amount': _avgFuelAmountController.text.trim(),
    };

    try {
      final response = await _repository.addEntry(payload);
      if (!mounted) return;
    if (response['status'] == 'success') {
      _showMessage(response['message']?.toString() ?? 'Entry added.');
      setState(() {
        _selectedDriver = null;
        _nameController.clear();
        _driverSearchController.clear();
        _filteredDrivers = _drivers;
        _showDriverList = false;
      });
      await _loadEntries(vehicleId, silent: true);
      await _loadSpecialBounds(vehicleId);
      _resetEntryFormDefaults();
    } else {
        _showMessage(
          response['message']?.toString() ?? 'Failed to add entry.',
          isError: true,
        );
      }
    } catch (_) {
      _showMessage('Network error while adding entry.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _deleteEntry(AverageEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await _repository.deleteEntry(entry.id);
      if (!mounted) return;
      if (response['status'] == 'success') {
        _showMessage(response['message']?.toString() ?? 'Entry deleted.');
        await _refreshEntries();
      } else {
        _showMessage(
          response['message']?.toString() ?? 'Failed to delete entry.',
          isError: true,
        );
      }
    } catch (_) {
      _showMessage('Network error while deleting entry.', isError: true);
    }
  }

  Future<void> _openEditEntry(AverageEntry entry) async {
    final dateController = TextEditingController(
      text: entry.entryDate.substring(0, 10),
    );
    final nameController = TextEditingController(text: entry.name ?? '');
    final initialController =
        TextEditingController(text: entry.initialReading ?? '');
    final finalController =
        TextEditingController(text: entry.finalReading ?? '');
    final runningController =
        TextEditingController(text: entry.running ?? '');
    final avgValueController =
        TextEditingController(text: entry.avgValue ?? '');
    final fuelQtyController =
        TextEditingController(text: entry.fuelQty ?? '0.00');
    final fuelTakenController =
        TextEditingController(text: entry.fuelTaken ?? '');
    final dieselDiffController =
        TextEditingController(text: entry.dieselDiff ?? '0.00');
    final fuelPriceController =
        TextEditingController(text: entry.fuelPrice ?? '');
    final amountController =
        TextEditingController(text: entry.amount ?? '0.0000');
    final currentAvgController =
        TextEditingController(text: entry.currentAvg ?? '0.00');
    final totalController =
        TextEditingController(text: entry.total ?? '0.00');
    final avgFuelAmountController =
        TextEditingController(text: entry.avgFuelAmount ?? '0.00');

    void calcEditFields() {
      final running = _parseNumber(runningController.text);
      final avgValue = _parseDouble(avgValueController.text);
      final fuelTaken = _parseDouble(fuelTakenController.text);
      final fuelPrice = _parseDouble(fuelPriceController.text);

      final fuelQty = avgValue > 0 ? (running / avgValue) : 0;
      fuelQtyController.text = fuelQty.toStringAsFixed(2);

      final avgFuelAmount = fuelQty * fuelPrice;
      avgFuelAmountController.text = avgFuelAmount.isFinite
          ? avgFuelAmount.toStringAsFixed(2)
          : '0.00';

      final dieselDiff = fuelTaken - fuelQty;
      dieselDiffController.text = dieselDiff.isFinite
          ? dieselDiff.toStringAsFixed(2)
          : '0.00';

      final currentAvg = fuelTaken > 0 ? (running / fuelTaken) : 0;
      currentAvgController.text = currentAvg.isFinite
          ? currentAvg.toStringAsFixed(2)
          : '0.00';

      final total =
          (fuelPrice > 0 && fuelTaken > 0) ? fuelPrice * fuelTaken : 0;
      totalController.text =
          total.isFinite ? total.toStringAsFixed(2) : '0.00';

      final amount = (fuelPrice > 0 && dieselDiff.isFinite)
          ? fuelPrice * dieselDiff
          : 0;
      amountController.text =
          amount.isFinite ? amount.toStringAsFixed(4) : '0.0000';
    }

    void updateEditRunning() {
      final initial = _parseNumber(initialController.text);
      final finalVal = _parseNumber(finalController.text);
      final running = finalVal > initial ? finalVal - initial : 0;
      runningController.text = running.toStringAsFixed(0);
      calcEditFields();
    }

    initialController.addListener(updateEditRunning);
    finalController.addListener(updateEditRunning);
    avgValueController.addListener(calcEditFields);
    fuelTakenController.addListener(calcEditFields);
    fuelPriceController.addListener(calcEditFields);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useTwoColumns = constraints.maxWidth >= 360;
            final rowGap = useTwoColumns ? 12.0 : 10.0;

            Widget wrapRow(Widget left, Widget right) {
              if (!useTwoColumns) {
                return Column(
                  children: [
                    left,
                    SizedBox(height: rowGap),
                    right,
                  ],
                );
              }
              return _buildTwoColumnRow(left, right, gap: 12);
            }

            InputDecoration buildUnderlineDecoration(String label) {
              return InputDecoration(
                labelText: label,
                isDense: true,
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black38),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black87),
                ),
              );
            }

            Widget buildEditField({
              required TextEditingController controller,
              required String label,
              TextInputType inputType = TextInputType.number,
              bool enabled = true,
              bool highlight = false,
              Widget? suffixIcon,
              VoidCallback? onTap,
              bool readOnly = false,
            }) {
              return TextField(
                controller: controller,
                keyboardType: inputType,
                enabled: enabled,
                readOnly: readOnly,
                onTap: onTap,
                style: const TextStyle(color: Colors.black),
                decoration: buildUnderlineDecoration(label).copyWith(
                  suffixIcon: suffixIcon,
                  filled: highlight,
                  fillColor: highlight ? const Color(0xFFD4F8D4) : null,
                ),
              );
            }

            return ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'Edit Entry',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                wrapRow(
                  buildEditField(
                    controller: dateController,
                    label: 'Entry Date',
                    inputType: TextInputType.datetime,
                    readOnly: true,
                    onTap: () async {
                      final picked = await _pickDate(
                        initial: DateTime.tryParse(dateController.text) ??
                            DateTime.now(),
                      );
                      if (picked != null) {
                        dateController.text = _formatDate(picked);
                      }
                    },
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                  buildEditField(
                    controller: nameController,
                    label: 'Name',
                    inputType: TextInputType.text,
                  ),
                ),
                SizedBox(height: rowGap),
                wrapRow(
                  buildEditField(
                    controller: initialController,
                    label: 'Initial Reading',
                  ),
                  buildEditField(
                    controller: finalController,
                    label: 'Final Reading',
                  ),
                ),
                SizedBox(height: rowGap),
                wrapRow(
                  buildEditField(
                    controller: runningController,
                    label: 'Running',
                    enabled: false,
                    highlight: true,
                  ),
                  buildEditField(
                    controller: avgValueController,
                    label: 'Average Value',
                  ),
                ),
                SizedBox(height: rowGap),
                wrapRow(
                  buildEditField(
                    controller: fuelQtyController,
                    label: 'Fuel Quantity',
                    enabled: false,
                    highlight: true,
                  ),
                  buildEditField(
                    controller: fuelTakenController,
                    label: 'Fuel Taken',
                  ),
                ),
                SizedBox(height: rowGap),
                wrapRow(
                  buildEditField(
                    controller: dieselDiffController,
                    label: 'Diesel Diff',
                    enabled: false,
                    highlight: true,
                  ),
                  buildEditField(
                    controller: fuelPriceController,
                    label: 'Fuel Price',
                  ),
                ),
                SizedBox(height: rowGap),
                wrapRow(
                  buildEditField(
                    controller: amountController,
                    label: 'Amount',
                    enabled: false,
                    highlight: true,
                  ),
                  buildEditField(
                    controller: currentAvgController,
                    label: 'Current Average',
                    enabled: false,
                    highlight: true,
                  ),
                ),
                SizedBox(height: rowGap),
                wrapRow(
                  buildEditField(
                    controller: totalController,
                    label: 'Total',
                    enabled: false,
                    highlight: true,
                  ),
                  buildEditField(
                    controller: avgFuelAmountController,
                    label: 'Average Fuel Amount',
                    enabled: false,
                    highlight: true,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () async {
                      final payload = {
                        'id': entry.id.toString(),
                        'entry_date': dateController.text.trim(),
                        'name': nameController.text.trim(),
                        'initial_reading':
                            initialController.text.replaceAll(',', '').trim(),
                        'final_reading':
                            finalController.text.replaceAll(',', '').trim(),
                        'running':
                            runningController.text.replaceAll(',', '').trim(),
                        'avg_value': avgValueController.text.trim(),
                        'fuel_qty': fuelQtyController.text.trim(),
                        'fuel_taken': fuelTakenController.text.trim(),
                        'diesel_diff': dieselDiffController.text.trim(),
                        'fuel_price': fuelPriceController.text.trim(),
                        'amount': amountController.text.trim(),
                        'current_avg': currentAvgController.text.trim(),
                        'total': totalController.text.trim(),
                        'avg_fuel_amount': avgFuelAmountController.text.trim(),
                      };

                      try {
                        final response = await _repository.updateEntry(payload);
                        if (!mounted) return;
                        if (response['status'] == 'success') {
                          _showMessage(
                            response['message']?.toString() ??
                                'Entry updated.',
                          );
                          Navigator.of(context).pop();
                          await _refreshEntries();
                        } else {
                          _showMessage(
                            response['message']?.toString() ??
                                'Failed to update entry.',
                            isError: true,
                          );
                        }
                      } catch (_) {
                        _showMessage(
                          'Network error while updating entry.',
                          isError: true,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Changes'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );

    dateController.dispose();
    nameController.dispose();
    initialController.dispose();
    finalController.dispose();
    runningController.dispose();
    avgValueController.dispose();
    fuelQtyController.dispose();
    fuelTakenController.dispose();
    dieselDiffController.dispose();
    fuelPriceController.dispose();
    amountController.dispose();
    currentAvgController.dispose();
    totalController.dispose();
    avgFuelAmountController.dispose();
  }

  Future<DateTime?> _pickDate({DateTime? initial}) {
    final initialDate = initial ?? DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _minEntryDate,
      lastDate: _maxEntryDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: Colors.white,
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
            datePickerTheme: const DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor: Colors.white,
              headerForegroundColor: Colors.black,
              surfaceTintColor: Colors.white,
              dayForegroundColor: MaterialStatePropertyAll(Colors.black),
              weekdayStyle: TextStyle(color: Colors.black),
              dayStyle: TextStyle(color: Colors.black),
              yearStyle: TextStyle(color: Colors.black),
              todayForegroundColor: MaterialStatePropertyAll(Colors.black),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
    bool highlightWhenDisabled = true,
  }) {
    final shouldHighlight = !enabled && highlightWhenDisabled;
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(color: Colors.black),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        filled: !enabled,
        fillColor: shouldHighlight ? const Color(0xFFD4F8D4) : null,
        labelStyle: !enabled ? const TextStyle(color: Colors.black) : null,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: const InputDecoration(
        labelText: 'Entry Date',
        suffixIcon: Icon(Icons.calendar_today),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child, Color? backgroundColor}) {
    return Card(
      color: backgroundColor ?? Colors.white,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _buildTwoColumnRow(Widget left, Widget right, {double gap = 12}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );
  }

  InputDecoration _buildDropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildDriverPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _driverSearchController,
          enabled: !_isLoadingDrivers,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: _isLoadingDrivers
                ? 'Loading drivers...'
                : (_driversError ?? 'Type driver name to search...'),
            border: const OutlineInputBorder(),
            prefixIcon: _driversError != null
                ? const Icon(Icons.error_outline, color: Colors.red)
                : _isLoadingDrivers
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: AppLoader(size: 18),
                        ),
                      )
                    : const Icon(Icons.search),
            suffixIcon: _selectedDriver != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _selectedDriver = null;
                        _nameController.clear();
                        _driverSearchController.clear();
                        _filteredDrivers = _drivers;
                        _showDriverList = false;
                      });
                    },
                  )
                : null,
          ),
          onTap: () {
            if (_drivers.isEmpty) return;
            setState(() => _showDriverList = true);
          },
          onChanged: (value) {
            if (_drivers.isEmpty) return;
            setState(() {
              _showDriverList = true;
              _filteredDrivers = _drivers
                  .where(
                    (driver) => driver.name
                        .toLowerCase()
                        .contains(value.toLowerCase()),
                  )
                  .toList(growable: false);
            });
          },
        ),
        if (_showDriverList && _filteredDrivers.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredDrivers.length,
              itemBuilder: (context, index) {
                final driver = _filteredDrivers[index];
                final isSelected =
                    _selectedDriver?.id == driver.id;
                return ListTile(
                  dense: true,
                  title: Text(driver.name),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: Colors.green.shade600,
                          size: 18,
                        )
                      : null,
                  onTap: () => _selectDriver(driver),
                );
              },
            ),
          ),
        if (_showDriverList &&
            _filteredDrivers.isEmpty &&
            _driverSearchController.text.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Text(
              'No drivers found for "${_driverSearchController.text}"',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (_selectedDriver != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              _selectedDriver!.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _buildEntryFormFields(double width) {
    final useTwoColumns = width >= 300;

    final rowGap = useTwoColumns ? 12.0 : 10.0;
    final columnGap = useTwoColumns ? 12.0 : 0.0;

    Widget wrapRow(Widget left, Widget right) {
      if (!useTwoColumns) {
        return Column(
          children: [
            left,
            SizedBox(height: rowGap),
            right,
          ],
        );
      }
      return _buildTwoColumnRow(left, right, gap: columnGap);
    }

    return Column(
      children: [
        DropdownButtonFormField<int>(
          value: _selectedPlantId,
          dropdownColor: Colors.white,
          style: _dropdownTextStyle,
          isExpanded: true,
          decoration: _buildDropdownDecoration('Plant'),
          items: _plants
              .map(
                (plant) => DropdownMenuItem(
                  value: plant.id,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_florist,
                        size: 14,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          plant.name,
                          style: _dropdownTextStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: _isLoading ? null : _selectPlant,
        ),
        SizedBox(height: rowGap),
        DropdownButtonFormField<int>(
          value: _selectedVehicleId,
          dropdownColor: Colors.white,
          style: _dropdownTextStyle,
          isExpanded: true,
          decoration: _buildDropdownDecoration('Vehicle No'),
          items: _vehicles
              .map(
                (vehicle) => DropdownMenuItem(
                  value: vehicle.id,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping,
                        size: 14,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vehicle.vehicleNo,
                          style: _dropdownTextStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: _vehicles.isEmpty ? null : _selectVehicle,
        ),
        SizedBox(height: rowGap),
        wrapRow(
          _buildDateField(
            controller: _entryDateController,
            onTap: () async {
              final picked = await _pickDate(initial: _entryDate);
              if (picked != null) {
                setState(() {
                  _entryDate = picked;
                  _entryDateController.text = _formatDate(picked);
                });
                _markFormDirty();
              }
            },
          ),
          _buildDriverPicker(),
        ),
        if (_specialBounds?.minDate != null ||
            _specialBounds?.maxDate != null) ...[
          SizedBox(height: rowGap),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Special Ledger Dates: '
              '${_formatDateDisplay(_specialBounds?.minDate ?? '—')}'
              ' to '
              '${_formatDateDisplay(_specialBounds?.maxDate ?? '—')}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        SizedBox(height: rowGap),
        wrapRow(
          _buildNumberField(
            controller: _initialController,
            label: 'Initial Reading',
          ),
          _buildNumberField(
            controller: _finalController,
            label: 'Final Reading',
          ),
        ),
        SizedBox(height: rowGap),
        wrapRow(
          _buildNumberField(
            controller: _runningController,
            label: 'Running',
            enabled: false,
          ),
          _buildNumberField(
            controller: _avgValueController,
            label: 'Average Value',
          ),
        ),
        SizedBox(height: rowGap),
        wrapRow(
          _buildNumberField(
            controller: _fuelQtyController,
            label: 'Fuel Quantity',
            enabled: false,
          ),
          _buildNumberField(
            controller: _fuelTakenController,
            label: 'Fuel Taken',
          ),
        ),
        SizedBox(height: rowGap),
        wrapRow(
          _buildNumberField(
            controller: _dieselDiffController,
            label: 'Diesel Diff',
            enabled: false,
          ),
          _buildNumberField(
            controller: _fuelPriceController,
            label: 'Fuel Price',
          ),
        ),
        SizedBox(height: rowGap),
        wrapRow(
          _buildNumberField(
            controller: _amountController,
            label: 'Amount',
            enabled: false,
          ),
          _buildNumberField(
            controller: _currentAvgController,
            label: 'Current Average',
            enabled: false,
          ),
        ),
        SizedBox(height: rowGap),
        wrapRow(
          _buildNumberField(
            controller: _totalController,
            label: 'Total',
            enabled: false,
          ),
          _buildNumberField(
            controller: _avgFuelAmountController,
            label: 'Average Fuel Amount',
            enabled: false,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader() {
    final currentMonth = _monthKeyFromDate(_formatDate(DateTime.now()));
    final currentEntries = _entries
        .where((entry) => _monthKeyFromDate(entry.entryDate) == currentMonth)
        .toList();

    double avgValueSum = 0;
    int avgValueCount = 0;
    double currentAvgSum = 0;
    int currentAvgCount = 0;

    for (final entry in currentEntries) {
      final avgValue = _parseNullable(entry.avgValue);
      if (avgValue != null) {
        avgValueSum += avgValue;
        avgValueCount++;
      }
      final currentAvg = _parseNullable(entry.currentAvg);
      if (currentAvg != null) {
        currentAvgSum += currentAvg;
        currentAvgCount++;
      }
    }

    final avgValueDisplay = avgValueCount > 0
        ? (avgValueSum / avgValueCount).toStringAsFixed(2)
        : '—';
    final currentAvgDisplay = currentAvgCount > 0
        ? (currentAvgSum / currentAvgCount).toStringAsFixed(2)
        : '—';

    if (currentEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'R.Average / C.Average ($currentMonth)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$avgValueDisplay / $currentAvgDisplay',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyReport() {
    if (_entries.isEmpty) {
      return const Text('Month wise Current Avg will appear here.');
    }

    final Map<String, List<double>> buckets = {};
    for (final entry in _entries) {
      final month = _monthKeyFromDate(entry.entryDate);
      final currentAvg = _parseNullable(entry.currentAvg);
      if (month.isEmpty || currentAvg == null) continue;
      buckets.putIfAbsent(month, () => []).add(currentAvg);
    }

    final months = buckets.keys.toList()..sort();
    final tiles = months.reversed.map((month) {
      final values = buckets[month] ?? [];
      final avg = values.isNotEmpty
          ? (values.reduce((a, b) => a + b) / values.length)
          : 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              _monthLabel(month),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              avg.toStringAsFixed(2),
              style: const TextStyle(color: Colors.blue),
            ),
          ],
        ),
      );
    }).toList();

    return Column(children: tiles);
  }

  Widget _buildEntriesList() {
    if (_filteredEntries.isEmpty) {
      return const Text('Select Plant and Vehicle to see entries');
    }

    final totalToShow = _shownCount.clamp(0, _filteredEntries.length);
    final visibleEntries = _filteredEntries.take(totalToShow).toList();

    final widgets = <Widget>[];
    String? currentMonth;
    Map<String, double> monthTotals = {};

    void resetTotals() {
      monthTotals = {
        'running': 0,
        'fuel_qty': 0,
        'fuel_taken': 0,
        'diesel_diff': 0,
        'fuel_price': 0,
        'amount': 0,
        'total': 0,
        'avg_fuel_amount': 0,
        'avg_sum': 0,
        'avg_count': 0,
        'cur_avg_sum': 0,
        'cur_avg_count': 0,
      };
    }

    void addTotals(AverageEntry entry) {
      monthTotals['running'] = monthTotals['running']! + _parseNumber(entry.running ?? '0');
      monthTotals['fuel_qty'] = monthTotals['fuel_qty']! + _parseNumber(entry.fuelQty ?? '0');
      monthTotals['fuel_taken'] = monthTotals['fuel_taken']! + _parseNumber(entry.fuelTaken ?? '0');
      monthTotals['diesel_diff'] = monthTotals['diesel_diff']! + _parseNumber(entry.dieselDiff ?? '0');
      monthTotals['fuel_price'] = monthTotals['fuel_price']! + _parseNumber(entry.fuelPrice ?? '0');
      monthTotals['amount'] = monthTotals['amount']! + _parseNumber(entry.amount ?? '0');
      monthTotals['total'] = monthTotals['total']! + _parseNumber(entry.total ?? '0');
      monthTotals['avg_fuel_amount'] = monthTotals['avg_fuel_amount']! + _parseNumber(entry.avgFuelAmount ?? '0');

      final avgValue = _parseNullable(entry.avgValue);
      if (avgValue != null) {
        monthTotals['avg_sum'] = monthTotals['avg_sum']! + avgValue;
        monthTotals['avg_count'] = monthTotals['avg_count']! + 1;
      }

      final currentAvg = _parseNullable(entry.currentAvg);
      if (currentAvg != null) {
        monthTotals['cur_avg_sum'] = monthTotals['cur_avg_sum']! + currentAvg;
        monthTotals['cur_avg_count'] = monthTotals['cur_avg_count']! + 1;
      }
    }

    void addTotalsRow(String monthKey) {
      final avgDisplay = monthTotals['avg_count']! > 0
          ? (monthTotals['avg_sum']! / monthTotals['avg_count']!).toStringAsFixed(2)
          : '0.00';
      final curDisplay = monthTotals['cur_avg_count']! > 0
          ? (monthTotals['cur_avg_sum']! / monthTotals['cur_avg_count']!).toStringAsFixed(2)
          : '0.00';

      final metrics = [
        ('Running', monthTotals['running']!.toStringAsFixed(2)),
        ('Average Value', avgDisplay),
        ('Fuel Qty', monthTotals['fuel_qty']!.toStringAsFixed(2)),
        ('Fuel Taken', monthTotals['fuel_taken']!.toStringAsFixed(2)),
        ('Diesel Diff', monthTotals['diesel_diff']!.toStringAsFixed(2)),
        ('Fuel Price', monthTotals['fuel_price']!.toStringAsFixed(2)),
        ('Amount', monthTotals['amount']!.toStringAsFixed(4)),
        ('Current Avg', curDisplay),
        ('Total', monthTotals['total']!.toStringAsFixed(2)),
      ];

      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueGrey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_monthLabel(monthKey)} Totals',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 0,
                childAspectRatio: 3.2,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: metrics.map((item) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        item.$2,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                'Avg Fuel Amount: ${monthTotals['avg_fuel_amount']!.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    resetTotals();

    for (int i = 0; i < visibleEntries.length; i++) {
      final entry = visibleEntries[i];
      final monthKey = _monthKeyFromDate(entry.entryDate);
      final nextEntry =
          i + 1 < visibleEntries.length ? visibleEntries[i + 1] : null;
      final nextMonth =
          nextEntry != null ? _monthKeyFromDate(nextEntry.entryDate) : null;

      if (currentMonth != monthKey) {
        currentMonth = monthKey;
        resetTotals();
      }

      addTotals(entry);

      final specialRow = _pickBestSpecialRow(entry);
      final fuelTakenColor =
          _fuelMatchColor(entry.fuelTaken, specialRow?.volume);
      final fuelPriceColor =
          _fuelMatchColor(entry.fuelPrice, specialRow?.price);
      final totalColor = _totalMatchColor(entry.total, specialRow?.amount);

      widgets.add(
        Card(
          color: const Color(0xFFFFFDD0),
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.vehicleNo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    Text(
                      '${_formatDateDisplay(entry.entryDate)} #${entry.id}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: specialRow != null
                            ? Colors.green
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
                if (_showValues && specialRow != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatDateDisplay(specialRow.date),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    Widget metricTile(
                      String label,
                      String value, {
                      Color? background,
                      String? special,
                    }) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            Text(
                              value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (special != null)
                              Text(
                                special,
                                style: const TextStyle(fontSize: 10),
                              ),
                          ],
                        ),
                      );
                    }

                    final metrics = <Widget>[
                      metricTile('Initial', entry.initialReading ?? ''),
                      metricTile('Final', entry.finalReading ?? ''),
                      metricTile('Running', entry.running ?? ''),
                      metricTile('Avg', entry.avgValue ?? ''),
                      metricTile('Fuel Qty', entry.fuelQty ?? ''),
                      metricTile(
                        'Fuel Taken',
                        entry.fuelTaken ?? '',
                        background: fuelTakenColor,
                        special: _showValues && specialRow?.volume != null
                            ? 'Special: ${specialRow!.volume!.toStringAsFixed(2)}'
                            : null,
                      ),
                      metricTile('Diesel Diff', entry.dieselDiff ?? ''),
                      metricTile(
                        'Fuel Price',
                        entry.fuelPrice ?? '',
                        background: fuelPriceColor,
                        special: _showValues && specialRow?.price != null
                            ? 'Special: ${specialRow!.price!.toStringAsFixed(4)}'
                            : null,
                      ),
                      metricTile('Amount', entry.amount ?? ''),
                      metricTile('Current Avg', entry.currentAvg ?? ''),
                      metricTile(
                        'Total',
                        entry.total ?? '',
                        background: totalColor,
                        special: _showValues && specialRow?.amount != null
                            ? 'Special: ${specialRow!.amount!.toStringAsFixed(2)}'
                            : null,
                      ),
                      metricTile('Avg Fuel Amt', entry.avgFuelAmount ?? ''),
                    ];

                    return GridView.count(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 4,
                      childAspectRatio: 2.6,
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      children: metrics,
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text('Name: ${entry.name ?? ''}'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () => _openEditEntry(entry),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.blue),
                          ),
                          child: const Text('Edit'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _deleteEntry(entry),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (nextMonth == null || nextMonth != monthKey) {
        addTotalsRow(monthKey);
      }
    }

    if (_shownCount < _filteredEntries.length) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _shownCount = (_shownCount + _stepCount)
                      .clamp(0, _filteredEntries.length);
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D2B57),
                foregroundColor: Colors.white,
              ),
              child: const Text('Load more'),
            ),
          ),
        ),
      );
    }

    return Column(children: widgets);
  }

  Widget _buildExportsSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Exports',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _exportMonth.isEmpty ? null : _exportMonth,
            dropdownColor: Colors.white,
            style: _dropdownTextStyle,
            isExpanded: true,
            items: _monthOptions
                .map(
                  (month) => DropdownMenuItem(
                    value: month,
                    child: Text(_monthLabel(month), style: _dropdownTextStyle),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _exportMonth = value ?? '';
              });
            },
            decoration: const InputDecoration(
              labelText: 'Export Month (CSV)',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () async {
                if (_exportMonth.isEmpty) {
                  _showMessage('Please select a month to export.', isError: true);
                  return;
                }
                final url =
                    'https://sstranswaysindia.com/AverageCalculator/export_csv.php?month=${Uri.encodeComponent(_exportMonth)}';
                await _openExternal(url);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Export Month CSV'),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () async {
                final date = await _pickDate(initial: DateTime.now());
                if (date == null) return;
                final formatted = _formatDate(date);
                final url =
                    'https://sstranswaysindia.com/AverageCalculator/export_by_date.php?date=${Uri.encodeComponent(formatted)}';
                await _openExternal(url);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Export by Date'),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () async {
                const url =
                    'https://sstranswaysindia.com/AverageCalculator/export_final_km.php';
                await _openExternal(url);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Export Final KM'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showMessage('Unable to open export link.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Average Calculator',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D2B57),
        foregroundColor: Colors.white,
        actions: const [],
      ),
      body: _isLoadingPlants
          ? const Center(child: AppLoader())
          : RefreshIndicator(
              onRefresh: () async {
                if (_selectedVehicleId != null) {
                  await _refreshEntries();
                }
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryHeader(),
                  _buildSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Entry Form',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return _buildEntryFormFields(constraints.maxWidth);
                          },
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitEntry,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Add Entry'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Text(
                                    'Special Ledger',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 4),
                                  Transform.scale(
                                    scale: 0.7,
                                    child: Switch(
                                      value: _showValues,
                                      activeColor: Colors.green,
                                      activeTrackColor: Colors.green.shade200,
                                      inactiveThumbColor: Colors.red,
                                      inactiveTrackColor: Colors.red.shade200,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (value) {
                                        setState(() {
                                          _showValues = value;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                value: _selectedMonth.isEmpty
                                    ? null
                                    : _selectedMonth,
                                dropdownColor: Colors.white,
                                style: _dropdownTextStyle,
                                isExpanded: true,
                                items: _monthOptions
                                    .map(
                                      (month) => DropdownMenuItem(
                                        value: month,
                                        child: Text(
                                          _monthLabel(month),
                                          style: _dropdownTextStyle,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMonth = value ?? '';
                                  });
                                  _applyMonthFilter();
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Filter by Month',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_isLoadingEntries)
                          const Center(child: AppLoader(size: 96))
                        else
                          _buildEntriesList(),
                      ],
                    ),
                  ),
                  _buildSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monthly Current Average Report',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        _buildMonthlyReport(),
                      ],
                    ),
                  ),
                  _buildExportsSection(),
                ],
              ),
            ),
    );
  }
}
