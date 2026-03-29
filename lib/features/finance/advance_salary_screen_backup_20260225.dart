import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/advance_transaction.dart';
import '../../core/models/app_user.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/services/trip_repository.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_loader.dart';
import 'khata_all_expenses_screen.dart';

class AdvanceSalaryScreen extends StatefulWidget {
  final AppUser user;

  const AdvanceSalaryScreen({super.key, required this.user});

  @override
  State<AdvanceSalaryScreen> createState() => _AdvanceSalaryScreenState();
}

enum _ReceiptSource { camera, gallery, pdf }

class _DescriptionOption {
  const _DescriptionOption({
    required this.label,
    this.vehicleMandatory = false,
    this.driverMandatory = false,
  });

  final String label;
  final bool vehicleMandatory;
  final bool driverMandatory;
}

class _VehicleOption {
  const _VehicleOption({
    required this.id,
    required this.number,
    this.plantId,
    this.plantName = '',
  });

  final int id;
  final String number;
  final int? plantId;
  final String plantName;

  String get displayLabel =>
      plantName.trim().isEmpty ? number : '$number (${plantName.trim()})';
}

class _AdvanceSalaryScreenState extends State<AdvanceSalaryScreen> {
  static final NumberFormat _inrNumber = NumberFormat.decimalPattern('en_IN');
  static const String _prefHideChargesInDescriptionPicker =
      'khata_hide_charges_description_picker';

  bool _hideChargesInDescriptionPicker = true;
  String? _selectedReceiptPath;
  Uint8List? _selectedReceiptBytes;
  String? _selectedReceiptName;

  String _selectedMonthCompactLabel() {
    if (_selectedMonth == 'All Months') return 'All';
    final year = (_selectedYear ?? DateTime.now().year) % 100;
    final yy = year.toString().padLeft(2, '0');
    final m = _selectedMonth.length >= 3
        ? _selectedMonth.substring(0, 3)
        : _selectedMonth;
    return '$m $yy';
  }

  String _formatInrSigned(double value) {
    final absValue = value.abs();
    final rounded = absValue.round();
    final formatted = _inrNumber.format(rounded);
    return value < 0 ? '-₹$formatted' : '₹$formatted';
  }

  String _formatInr(double value) {
    final rounded = value.round();
    return '₹${_inrNumber.format(rounded)}';
  }

  String _normalizeCategoryKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  bool _isHiddenInDescriptionPicker(_DescriptionOption option) {
    final key = _normalizeCategoryKey(option.label);
    if (key == 'drivetrack') return true;
    if (_hideChargesInDescriptionPicker && key == 'charges') return true;
    return false;
  }

  Future<void> _loadHideChargesPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefHideChargesInDescriptionPicker);
      if (!mounted) return;
      setState(() {
        _hideChargesInDescriptionPicker = saved ?? true;
      });
    } catch (_) {
      // Ignore preference failures and keep default.
    }
  }

  Future<void> _setHideChargesPreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefHideChargesInDescriptionPicker, value);
    } catch (_) {
      // Ignore preference failures.
    }
  }

  bool _isEditLockedTransaction(AdvanceTransaction transaction) {
    final raw = (transaction.category ?? '').trim();
    final key = _normalizeCategoryKey(raw);
    if (key.isEmpty) return false;
    const blocked = <String>{'home', 'charges', 'advanceoffice', 'advance'};
    return blocked.contains(key);
  }

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

  static const List<String> _monthOptions = <String>[
    'All Months',
    ..._monthNames,
  ];

  List<AdvanceTransaction> _transactions = [];
  List<AdvanceTransaction> _filteredTransactions = [];
  double _currentBalance = 0.0;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  late String _selectedMonth;
  int? _selectedYear;
  List<int> _availableYears = <int>[];
  final ProfileRepository _profileRepository = ProfileRepository();
  final FinanceRepository _financeRepository = FinanceRepository();
  final ImagePicker _imagePicker = ImagePicker();
  List<_DescriptionOption> _descriptionOptions = const [];
  bool _isDescriptionLoading = false;
  // Used in _loadTransactionDescriptions() for debugging / future UI use.
  // ignore: unused_field
  String? _descriptionLoadError;
  List<_VehicleOption> _vehicleOptions = const [];
  // Used in _loadVehiclesForKhata() for debugging / future UI use.
  // ignore: unused_field
  bool _isVehicleListLoading = false;
  String? _vehicleLoadError;

  // Fund transfer modal state
  String? _selectedDriverId;
  String _selectedDriverName = '';
  final TextEditingController _transferAmountController =
      TextEditingController();
  final TextEditingController _transferDescriptionController =
      TextEditingController();
  final TextEditingController _driverSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _driversList = [];
  List<Map<String, dynamic>> _filteredDriversList = [];
  bool _showDriverList = false;
  String? _driverLoadErrorMessage;
  final Map<String, String> _driverNameCache = {};
  bool _requestedBellHide = false;

  @override
  void initState() {
    super.initState();
    NotificationService().requestBellHide();
    _requestedBellHide = true;
    _loadHideChargesPreference();
    final now = DateTime.now();
    _selectedMonth = _monthNames[now.month - 1];
    _selectedYear = now.year;
    _loadData();

    // Add listener to search controller for debugging
    _driverSearchController.addListener(() {
      print(
        'DEBUG: Controller listener - text: "${_driverSearchController.text}"',
      );
    });
  }

  @override
  void dispose() {
    if (_requestedBellHide) {
      NotificationService().releaseBellHide();
      _requestedBellHide = false;
    }
    _transferAmountController.dispose();
    _transferDescriptionController.dispose();
    _driverSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadBalance(),
      _loadTransactions(),
      _loadDriversList(),
      _loadTransactionDescriptions(),
      _loadVehiclesForKhata(),
    ]);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadBalance() async {
    try {
      final driverId = (widget.user.driverId ?? '').toString();
      if (driverId.trim().isEmpty) {
        setState(() {
          _currentBalance = 0.0;
        });
        return;
      }
      print('DEBUG: Loading balance for driverId: $driverId');

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_advance_balance.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId}),
      );

      print('DEBUG: Balance API response status: ${response.statusCode}');
      print('DEBUG: Balance API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['status'] == 'ok') {
            setState(() {
              _currentBalance = (data['balance'] ?? 0.0).toDouble();
            });
            print('DEBUG: Balance loaded: $_currentBalance');
          } else {
            print('DEBUG: API returned error: ${data['error']}');
          }
        } catch (jsonError) {
          print('DEBUG: Balance JSON decode error: $jsonError');
          print('DEBUG: Balance response body: ${response.body}');
        }
      }
    } catch (e) {
      print('Error loading balance: $e');
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final driverId = (widget.user.driverId ?? '').toString();
      if (driverId.trim().isEmpty) {
        setState(() {
          _transactions = [];
          _filteredTransactions = [];
          _currentBalance = 0.0;
        });
        return;
      }
      print('DEBUG: Loading transactions for driverId: $driverId');
      print('DEBUG: User driverId: ${widget.user.driverId}');
      print('DEBUG: User id: ${widget.user.id}');
      print(
        'DEBUG: Request body: ${jsonEncode({'driverId': driverId, 'limit': 5000})}',
      );

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId, 'limit': 5000}),
      );

      print('DEBUG: Transactions API response status: ${response.statusCode}');
      print('DEBUG: Transactions API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          print('DEBUG: Parsed JSON data: $data');
          if (data['status'] == 'ok') {
            final transactionsList = data['transactions'] as List?;
            print('DEBUG: Raw transactions list: $transactionsList');
            if (transactionsList != null) {
              final transactions = transactionsList
                  .map(
                    (json) => AdvanceTransaction.fromJson(
                      json as Map<String, dynamic>,
                    ),
                  )
                  .toList();
              setState(() {
                _transactions = transactions;
                _updateAvailableYears(transactions);
              });
              _filterTransactions();
            }
          }
        } catch (jsonError) {
          // Handle JSON decode error silently
        }
      }
    } catch (e) {
      print('Error loading transactions: $e');
    }
  }

  int? _inferPlantId() {
    final candidates = <String?>[
      widget.user.assignmentPlantId,
      widget.user.plantId,
      widget.user.defaultPlantId,
    ];
    for (final candidate in candidates) {
      if (candidate == null) continue;
      final parsed = int.tryParse(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  // Previously used to filter supervisor vehicles by supervised plants.
  // Kept for potential future use.
  // ignore: unused_element
  Set<int> _parseSupervisorPlantIds() {
    final ids = <int>{};
    for (final raw in widget.user.supervisedPlantIds) {
      if (raw == null) continue;
      if (raw is int) {
        if (raw > 0) ids.add(raw);
        continue;
      }
      final parsed = int.tryParse(raw.toString());
      if (parsed != null && parsed > 0) {
        ids.add(parsed);
      }
    }
    return ids;
  }

  String _plantNameForId(int? plantId) {
    if (plantId == null || plantId <= 0) {
      return '';
    }

    // Try supervisedPlants array (for supervisors)
    for (final p in widget.user.supervisedPlants) {
      final rawId = p['id'] ?? p['plantId'] ?? p['plant_id'];
      final id = int.tryParse(rawId?.toString() ?? '');
      if (id == plantId) {
        final name =
            (p['name'] ?? p['plantName'] ?? p['plant_name'] ?? p['plant'] ?? '')
                .toString()
                .trim();
        if (name.isNotEmpty) return name;
      }
    }

    // Try current user fields (for drivers)
    final inferred = _inferPlantId();
    if (inferred == plantId) {
      final nameCandidates = <String?>[
        widget.user.assignmentPlantName,
        widget.user.plantName,
        widget.user.defaultPlantName,
      ];
      for (final n in nameCandidates) {
        final name = (n ?? '').trim();
        if (name.isNotEmpty) return name;
      }
    }

    return 'Plant $plantId';
  }

  List<_VehicleOption> _buildVehicleOptionsFromAvailable(
    Set<int> allowedPlants,
  ) {
    final unique = <int, _VehicleOption>{};
    for (final driverVehicle in widget.user.availableVehicles) {
      final id = int.tryParse(driverVehicle.id) ?? 0;
      final number = driverVehicle.vehicleNumber.trim();
      if (id <= 0 || number.isEmpty) {
        continue;
      }
      final plantId = driverVehicle.plantId;
      if (allowedPlants.isNotEmpty &&
          plantId != null &&
          !allowedPlants.contains(plantId)) {
        continue;
      }
      unique[id] = _VehicleOption(
        id: id,
        number: number,
        plantId: plantId,
        plantName: _plantNameForId(plantId),
      );
    }
    return unique.values.toList(growable: false);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _applyMonthYear({required String month, int? year}) {
    setState(() {
      _selectedMonth = month;
      _selectedYear = year;
    });
    _filterTransactions();
  }

  void _filterTransactions() {
    final currentDriverId = (widget.user.driverId ?? '').toString();
    if (currentDriverId.trim().isEmpty) {
      setState(() {
        _filteredTransactions = const [];
      });
      return;
    }

    // First filter by driver ID to ensure only current driver's transactions
    final driverFilteredTransactions = _transactions.where((transaction) {
      // Try multiple comparison methods to handle data type mismatches
      final directMatch = transaction.driverId == currentDriverId;
      final stringMatch =
          transaction.driverId.toString() == currentDriverId.toString();
      final intMatch =
          int.tryParse(transaction.driverId.toString()) ==
          int.tryParse(currentDriverId.toString());

      final matches = directMatch || stringMatch || intMatch;
      return matches;
    }).toList();

    var filtered = driverFilteredTransactions;

    if (_selectedMonth != 'All Months') {
      final monthIndex = _getMonthIndex(_selectedMonth);
      filtered = filtered.where((transaction) {
        final date = _parseTransactionDate(transaction.createdAt);
        return date.month == monthIndex;
      }).toList();
    }

    final selectedYear = _selectedYear;
    if (selectedYear != null) {
      filtered = filtered.where((transaction) {
        final date = _parseTransactionDate(transaction.createdAt);
        return date.year == selectedYear;
      }).toList();
    }

    filtered.sort(
      (a, b) => _parseTransactionDate(
        b.createdAt,
      ).compareTo(_parseTransactionDate(a.createdAt)),
    );

    // IMPORTANT: Month-wise balance should NOT include previous months.
    // Recompute running balance within the currently filtered set
    // (which is already month/year constrained).
    final recomputed = _recomputeRunningBalanceForFilteredMonth(filtered);

    double monthBalance = 0.0;
    for (final t in recomputed) {
      if (t.type == 'advance_received') {
        monthBalance += t.amount;
      } else if (t.type == 'expense') {
        monthBalance -= t.amount;
      }
    }

    setState(() {
      _filteredTransactions = recomputed;
      // Show balance for the currently selected month/year (default: current month).
      _currentBalance = monthBalance;
    });
  }

  List<AdvanceTransaction> _recomputeRunningBalanceForFilteredMonth(
    List<AdvanceTransaction> txns,
  ) {
    if (txns.isEmpty) return txns;

    int idAsInt(AdvanceTransaction t) => int.tryParse(t.id) ?? 0;

    // Compute balances in chronological order (oldest -> newest) so "Bal."
    // is the cumulative month balance up to that transaction.
    final asc = List<AdvanceTransaction>.from(txns)
      ..sort((a, b) {
        final d = _parseTransactionDate(
          a.createdAt,
        ).compareTo(_parseTransactionDate(b.createdAt));
        if (d != 0) return d;
        return idAsInt(a).compareTo(idAsInt(b));
      });

    final balanceById = <String, double>{};
    double running = 0.0;
    for (final t in asc) {
      if (t.type == 'advance_received') {
        running += t.amount;
      } else if (t.type == 'expense') {
        running -= t.amount;
      }
      balanceById[t.id] = running;
    }

    // Keep UI order (DESC) but replace runningBalance with month-wise values.
    return txns
        .map(
          (t) => AdvanceTransaction(
            id: t.id,
            driverId: t.driverId,
            type: t.type,
            amount: t.amount,
            description: t.description,
            createdAt: t.createdAt,
            vehicleId: t.vehicleId,
            vehiclePlantId: t.vehiclePlantId,
            counterpartyDriverId: t.counterpartyDriverId,
            counterpartyPlantId: t.counterpartyPlantId,
            runningBalance: balanceById[t.id],
            receiptPath: t.receiptPath,
            category: t.category,
          ),
        )
        .toList(growable: false);
  }

  int _getMonthIndex(String month) {
    final index = _monthNames.indexOf(month);
    if (index == -1) {
      return DateTime.now().month;
    }
    return index + 1;
  }

  DateTime _parseTransactionDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  void _updateAvailableYears(List<AdvanceTransaction> transactions) {
    final years = <int>{};
    for (final transaction in transactions) {
      final date = _parseTransactionDate(transaction.createdAt);
      if (date.year > 0) {
        years.add(date.year);
      }
    }
    if (years.isEmpty) {
      years.add(DateTime.now().year);
    }
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    _availableYears = sorted;
    if (_selectedYear != null && !_availableYears.contains(_selectedYear)) {
      _selectedYear = sorted.first;
    }
  }

  String _currentFilterLabel() {
    final yearSuffix = _selectedYear != null ? ' ${_selectedYear!}' : '';
    if (_selectedMonth == 'All Months') {
      return _selectedYear != null ? 'All Months$yearSuffix' : 'All Months';
    }
    return '$_selectedMonth$yearSuffix';
  }

  bool _isVehicleMandatory(String? label) {
    if (label == null || label.isEmpty) return false;
    for (final option in _descriptionOptions) {
      if (option.label == label) return option.vehicleMandatory;
    }
    return false;
  }

  bool _isDriverMandatory(String? label, {required bool isAdvanceReceived}) {
    if (label == null || label.isEmpty) return false;
    for (final option in _descriptionOptions) {
      if (option.label == label) {
        // explicit driver flag or legacy heuristics (advance or incentive when you gave)
        final lower = option.label.toLowerCase();
        final isAdvance = lower.contains('advance');
        final isIncentive = lower.contains('incentive');
        final isDa = lower.trim() == 'da';
        final isMedical = lower.trim() == 'medical';
        final isExtra = lower.trim() == 'extra';
        return option.driverMandatory ||
            (!isAdvanceReceived &&
                (isIncentive || isDa || isMedical || isExtra)) ||
            isAdvance;
      }
    }
    return false;
  }

  Future<void> _showMonthSelector() async {
    final yearOptions = _availableYears.isNotEmpty
        ? _availableYears
        : <int>[_selectedYear ?? DateTime.now().year];

    final selection = await showModalBottomSheet<_MonthYearSelection>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        String tempMonth = _selectedMonth;
        int? tempYear = _selectedYear;

        return StatefulBuilder(
          builder: (context, modalSetState) {
            final maxHeight = MediaQuery.of(context).size.height * 0.6;
            return SafeArea(
              child: SizedBox(
                height: maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Month',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              value: tempYear,
                              dropdownColor: Colors.white,
                              onChanged: (value) {
                                modalSetState(() {
                                  tempYear = value;
                                });
                              },
                              items: <DropdownMenuItem<int?>>[
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('All Years'),
                                ),
                                ...yearOptions.map(
                                  (year) => DropdownMenuItem<int?>(
                                    value: year,
                                    child: Text(year.toString()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _monthOptions.length,
                        itemBuilder: (context, index) {
                          final month = _monthOptions[index];
                          final isSelected = month == tempMonth;
                          return ListTile(
                            dense: true,
                            title: Text(month),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: Colors.blue)
                                : null,
                            onTap: () => Navigator.of(context).pop(
                              _MonthYearSelection(month: month, year: tempYear),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 12,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(
                            _MonthYearSelection(
                              month: tempMonth,
                              year: tempYear,
                            ),
                          ),
                          child: const Text('Apply'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selection != null) {
      _applyMonthYear(month: selection.month, year: selection.year);
    }
  }

  Future<void> _handlePhotoSelected(File file) async {
    setState(() => _isUploadingPhoto = true);
    try {
      String url;
      final driverId = widget.user.driverId;

      if (driverId != null && driverId.isNotEmpty) {
        // Driver with driverId - use driver-specific upload
        url = await _profileRepository.uploadProfilePhoto(
          driverId: driverId,
          file: file,
        );
      } else {
        // Supervisor or user without driverId - use user-specific upload
        url = await _profileRepository.uploadUserProfilePhoto(
          userId: widget.user.id,
          file: file,
        );
      }

      if (!mounted) return;

      setState(() {
        widget.user.profilePhoto = url;
      });
      showAppToast(context, 'Profile photo updated.');
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to upload profile photo.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<String?> _addTransactionWithDate(
    String type,
    double amount,
    String description,
    DateTime transactionDate, {
    String? targetDriverId,
    int? counterpartyDriverId,
    int? counterpartyPlantId,
    int? vehicleId,
    int? vehiclePlantId,
    String? category,
  }) async {
    try {
      final driverId = targetDriverId ?? widget.user.driverId ?? widget.user.id;
      final requestBody = {
        'driverId': driverId,
        'userId': widget.user.id,
        'type': type,
        'amount': amount,
        'description': description,
        'timestamp': transactionDate.toIso8601String(),
      };
      // Also send the base category (selected description label) separately,
      // so backend can store it in advance_transactions.category.
      if (category != null && category.trim().isNotEmpty) {
        requestBody['category'] = category.trim();
      }
      if (vehicleId != null && vehicleId > 0) {
        requestBody['vehicleId'] = vehicleId;
      }
      if (vehiclePlantId != null && vehiclePlantId > 0) {
        requestBody['vehiclePlantId'] = vehiclePlantId;
      }
      if (counterpartyDriverId != null && counterpartyDriverId > 0) {
        requestBody['counterpartyDriverId'] = counterpartyDriverId;
      }
      if (counterpartyPlantId != null && counterpartyPlantId > 0) {
        requestBody['counterpartyPlantId'] = counterpartyPlantId;
      }

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/add_advance_transaction.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['status'] == 'ok') {
            showAppToast(context, 'Transaction added successfully');
            await _loadData(); // Refresh data
            return data['transactionId']?.toString();
          } else {
            showAppToast(
              context,
              data['error'] ?? 'Failed to add transaction',
              isError: true,
            );
            return null;
          }
        } catch (jsonError) {
          showAppToast(context, 'Invalid response from server', isError: true);
          return null;
        }
      } else {
        showAppToast(
          context,
          'Server error (${response.statusCode})',
          isError: true,
        );
        return null;
      }
    } catch (e) {
      showAppToast(context, 'Error adding transaction: $e', isError: true);
      return null;
    }
  }

  Future<String?> _generatePdfFromImages(List<XFile> images) async {
    try {
      final pdf = pw.Document();

      for (final image in images) {
        final imageBytes = await image.readAsBytes();
        final pdfImage = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Center(child: pw.Image(pdfImage));
            },
          ),
        );
      }

      final output = await getTemporaryDirectory();
      final file = File(
        '${output.path}/receipts_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error generating PDF: $e');
      return null;
    }
  }

  Future<_ReceiptSource?> _showReceiptSourceSheet() {
    return showModalBottomSheet<_ReceiptSource>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Material(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Text(
                  'Attach receipt',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Capture photo'),
                onTap: () => Navigator.pop(sheetContext, _ReceiptSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery (Multiple)'),
                onTap: () =>
                    Navigator.pop(sheetContext, _ReceiptSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Choose PDF file'),
                onTap: () => Navigator.pop(sheetContext, _ReceiptSource.pdf),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<XFile>> _pickGalleryReceipts() async {
    try {
      final images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      return images;
    } on UnimplementedError {
      final single = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (single != null) {
        return [single];
      }
      return const [];
    }
  }

  Future<void> _handleReceiptSelection({
    required _ReceiptSource source,
    required StateSetter setSheetState,
    required ValueChanged<String> onPathSelected,
  }) async {
    setSheetState(() {
      _isUploadingPhoto = true;
    });

    try {
      if (source == _ReceiptSource.pdf) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          withData: true,
        );
        final file = result?.files.single;
        final bytes = file?.bytes;
        final name = file?.name;
        final path = file?.path;
        if ((path == null || path.isEmpty) &&
            (bytes == null || bytes.isEmpty)) {
          showAppToast(
            context,
            'Unable to pick PDF on this device.',
            isError: true,
          );
          return;
        }
        setSheetState(() {
          final displayName = (path != null && path.isNotEmpty)
              ? path
              : (name ?? 'PDF receipt');
          _selectedReceiptPath = displayName;
          _selectedReceiptBytes = (path == null || path.isEmpty) ? bytes : null;
          _selectedReceiptName = (path == null || path.isEmpty) ? name : null;
          onPathSelected(displayName);
        });
        return;
      }

      if (source == _ReceiptSource.camera) {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          setSheetState(() {
            _selectedReceiptPath = image.path;
            _selectedReceiptBytes = null;
            _selectedReceiptName = null;
            onPathSelected(image.path);
          });
        }
      } else {
        final images = await _pickGalleryReceipts();
        if (images.isEmpty) return;

        if (images.length == 1) {
          setSheetState(() {
            _selectedReceiptPath = images.first.path;
            _selectedReceiptBytes = null;
            _selectedReceiptName = null;
            onPathSelected(images.first.path);
          });
        } else {
          final pdfPath = await _generatePdfFromImages(images);
          if (pdfPath != null) {
            setSheetState(() {
              _selectedReceiptPath = pdfPath;
              _selectedReceiptBytes = null;
              _selectedReceiptName = null;
              onPathSelected(pdfPath);
            });
          } else {
            showAppToast(
              context,
              'Failed to generate PDF from images',
              isError: true,
            );
          }
        }
      }
    } on PlatformException catch (error) {
      var message = 'Unable to access the selected source.';
      if (error.code == 'camera_access_denied' ||
          error.code == 'camera_access_restricted') {
        message =
            'Camera permission is denied. Please enable it in Settings and try again.';
      } else if (error.code == 'photo_access_denied' ||
          error.code == 'photo_access_restricted') {
        message =
            'Photo library permission is denied. Please allow gallery access.';
      } else if (error.message != null && error.message!.isNotEmpty) {
        message = error.message!;
      }
      showAppToast(context, message, isError: true);
    } catch (error) {
      showAppToast(context, 'Error selecting image: $error', isError: true);
    } finally {
      setSheetState(() {
        _isUploadingPhoto = false;
      });
    }
  }

  void _showAddTransactionDialog(bool isAdvanceReceived) {
    print(
      'DEBUG: _showAddTransactionDialog called. isAdvanceReceived: $isAdvanceReceived',
    );
    print('DEBUG: _isDescriptionLoading: $_isDescriptionLoading');
    print('DEBUG: _descriptionOptions length: ${_descriptionOptions.length}');

    if (_isDescriptionLoading) {
      print('DEBUG: Descriptions are loading, showing toast');
      showAppToast(
        context,
        'Loading transaction descriptions, try again shortly.',
        isError: true,
      );
      return;
    }
    if (_descriptionOptions.isEmpty) {
      print('DEBUG: Description options are empty, showing toast');
      showAppToast(
        context,
        'Transaction descriptions are unavailable. Pull to refresh and try again.',
        isError: true,
      );
      return;
    }
    print('DEBUG: Proceeding to show modal bottom sheet');

    final amountController = TextEditingController();
    final extraNotesController = TextEditingController();
    final advanceDriverSearchController = TextEditingController();
    final vehicleSearchController = TextEditingController();
    bool isVehicleRemoteLoading = false;
    String? vehicleRemoteError;
    Timer? vehicleDebounce;
    String? advanceSelectedDriverId;
    String advanceSelectedDriverName = '';
    String advanceSelectedDriverPlant = '';
    int? advanceSelectedDriverPlantId;
    bool showAdvanceDriverList = false;
    List<Map<String, dynamic>> advanceFilteredDrivers = List.from(_driversList);
    bool showVehicleList = false;
    List<_VehicleOption> filteredVehicles = List.from(_vehicleOptions);
    DateTime selectedDate = DateTime.now();
    String? selectedDescriptionLabel;
    if (_descriptionOptions.isNotEmpty) {
      final visible = _descriptionOptions
          .where((opt) => !_isHiddenInDescriptionPicker(opt))
          .toList(growable: false);
      selectedDescriptionLabel =
          (visible.isNotEmpty ? visible.first : _descriptionOptions.first)
              .label;
    }
    // ignore: unused_local_variable
    int? selectedVehicleId;
    String? selectedVehicleNumber;
    int? selectedVehiclePlantId;
    String? selectedVehiclePlantName;

    // Try to unfocus to prevent MouseTracker issues
    FocusScope.of(context).unfocus();

    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white, // Changed to white for visibility
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> pickReceipt() async {
                final _ReceiptSource? source = await _showReceiptSourceSheet();
                if (source == null) return;
                await _handleReceiptSelection(
                  source: source,
                  setSheetState: setSheetState,
                  onPathSelected: (path) {
                    _selectedReceiptPath = path;
                  },
                );
              }

              Future<void> handleDateChange() async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedDate),
                  );
                  if (time != null) {
                    setSheetState(() {
                      selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              }

              Future<T?> showSelectionDialog<T>({
                required String title,
                required List<T> items,
                required String Function(T) labelBuilder,
              }) async {
                return showDialog<T>(
                  context: context,
                  builder: (context) => Dialog(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 400),
                      color: Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const Divider(height: 1),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return ListTile(
                                  title: Text(labelBuilder(item)),
                                  onTap: () => Navigator.pop(context, item),
                                );
                              },
                            ),
                          ),
                          const Divider(height: 1),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final bool vehicleFieldNeeded =
                  !isAdvanceReceived &&
                  _isVehicleMandatory(selectedDescriptionLabel);
              final bool isAdvanceCategory = (selectedDescriptionLabel ?? '')
                  .toLowerCase()
                  .contains('advance');
              final bool needsDriverSelection = _isDriverMandatory(
                selectedDescriptionLabel,
                isAdvanceReceived: isAdvanceReceived,
              );
              final bool requiresVehicleSelection =
                  vehicleFieldNeeded ||
                  _isVehicleMandatory(selectedDescriptionLabel);
              final bool vehicleSelectedOk = !requiresVehicleSelection
                  ? true
                  : ((selectedVehicleNumber ?? '').trim().isNotEmpty &&
                        selectedVehicleId != null);
              void clearAdvanceDriver() {
                advanceSelectedDriverId = null;
                advanceSelectedDriverName = '';
                advanceSelectedDriverPlant = '';
                advanceSelectedDriverPlantId = null;
                advanceDriverSearchController.clear();
                advanceFilteredDrivers = List.from(_driversList);
                showAdvanceDriverList = false;
                setSheetState(() {});
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isAdvanceReceived ? 'You Got ₹' : 'You Gave ₹',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              prefixText: '₹',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            readOnly: true,
                            controller: TextEditingController(
                              text: selectedDescriptionLabel,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Description',
                              border: const OutlineInputBorder(),
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.grey),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                              suffixIcon: const Icon(Icons.arrow_drop_down),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onTap: _descriptionOptions.isEmpty
                                ? null
                                : () async {
                                    final visibleDescriptions =
                                        _descriptionOptions
                                            .where(
                                              (opt) =>
                                                  !_isHiddenInDescriptionPicker(
                                                    opt,
                                                  ),
                                            )
                                            .toList(growable: false);
                                    final selected =
                                        await showSelectionDialog<
                                          _DescriptionOption
                                        >(
                                          title: 'Select Description',
                                          items: visibleDescriptions,
                                          labelBuilder: (option) =>
                                              option.label,
                                        );
                                    if (selected != null) {
                                      setSheetState(() {
                                        selectedDescriptionLabel =
                                            selected.label;
                                        // Reset vehicle selection when description changes
                                        selectedVehicleId = null;
                                        selectedVehicleNumber = null;
                                        selectedVehiclePlantId = null;
                                        selectedVehiclePlantName = null;
                                        vehicleSearchController.clear();
                                        filteredVehicles = List.from(
                                          _vehicleOptions,
                                        );
                                        showVehicleList = false;
                                        // Keep/clear driver selection in sync with the same rule used by the UI + submit validation.
                                        final newlyNeedsDriver =
                                            _isDriverMandatory(
                                              selected.label,
                                              isAdvanceReceived:
                                                  isAdvanceReceived,
                                            );
                                        if (!newlyNeedsDriver) {
                                          clearAdvanceDriver();
                                        }
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                final next = !_hideChargesInDescriptionPicker;
                                setSheetState(() {
                                  _hideChargesInDescriptionPicker = next;
                                  if (next &&
                                      selectedDescriptionLabel != null &&
                                      _normalizeCategoryKey(
                                            selectedDescriptionLabel!,
                                          ) ==
                                          'charges') {
                                    final visible = _descriptionOptions
                                        .where(
                                          (opt) =>
                                              !_isHiddenInDescriptionPicker(
                                                opt,
                                              ),
                                        )
                                        .toList(growable: false);
                                    if (visible.isNotEmpty) {
                                      selectedDescriptionLabel =
                                          visible.first.label;
                                    }
                                  }
                                });
                                _setHideChargesPreference(next);
                              },
                              child: Text(
                                _hideChargesInDescriptionPicker
                                    ? 'Show CHARGES'
                                    : 'Hide CHARGES',
                              ),
                            ),
                          ),
                          if (vehicleFieldNeeded) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Select Vehicle *',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: vehicleSearchController,
                              enabled:
                                  !_isVehicleListLoading &&
                                  _vehicleLoadError == null &&
                                  _vehicleOptions.isNotEmpty,
                              decoration: InputDecoration(
                                hintText:
                                    _vehicleLoadError ??
                                    (_isVehicleListLoading ||
                                            _vehicleOptions.isEmpty
                                        ? 'Loading vehicles...'
                                        : 'Type vehicle number to search...'),
                                border: const OutlineInputBorder(),
                                prefixIcon: _vehicleLoadError != null
                                    ? const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                      )
                                    : (isVehicleRemoteLoading ||
                                          _isVehicleListLoading ||
                                          _vehicleOptions.isEmpty)
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: AppLoader(size: 20),
                                        ),
                                      )
                                    : const Icon(Icons.search),
                                suffixIcon: selectedVehicleId != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          setSheetState(() {
                                            selectedVehicleId = null;
                                            selectedVehicleNumber = null;
                                            selectedVehiclePlantId = null;
                                            selectedVehiclePlantName = null;
                                            vehicleSearchController.clear();
                                            filteredVehicles = List.from(
                                              _vehicleOptions,
                                            );
                                            showVehicleList = false;
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              onTap: () {
                                showVehicleList = true;
                                filteredVehicles = List.from(_vehicleOptions);
                                setSheetState(() {});
                              },
                              onChanged: (value) {
                                showVehicleList = true;
                                final q = value.trim().toLowerCase();
                                if (q.isEmpty) {
                                  filteredVehicles = List<_VehicleOption>.from(
                                    _vehicleOptions,
                                  );
                                } else {
                                  filteredVehicles = _vehicleOptions
                                      .where(
                                        (v) =>
                                            v.number.toLowerCase().contains(
                                              q,
                                            ) ||
                                            v.plantName.toLowerCase().contains(
                                              q,
                                            ),
                                      )
                                      .toList(growable: false);
                                }
                                vehicleRemoteError = null;
                                setSheetState(() {});

                                // Supervisor: also search vehicles across ALL plants using backend search (plantId=0).
                                if (widget.user.role == UserRole.supervisor) {
                                  final query = value.trim();
                                  final isNumeric = RegExp(
                                    r'^\d+$',
                                  ).hasMatch(query);
                                  if (query.isNotEmpty &&
                                      (query.length >= 2 ||
                                          (isNumeric && query.isNotEmpty))) {
                                    vehicleDebounce?.cancel();
                                    vehicleDebounce = Timer(
                                      const Duration(milliseconds: 350),
                                      () async {
                                        isVehicleRemoteLoading = true;
                                        vehicleRemoteError = null;
                                        setSheetState(() {});
                                        try {
                                          final response = await http.post(
                                            Uri.parse(
                                              'https://sstranswaysindia.com/TripDetails/api/mobile/vehicles.php',
                                            ),
                                            headers: const {
                                              'Content-Type':
                                                  'application/json',
                                            },
                                            body: jsonEncode(<String, dynamic>{
                                              'role': 'supervisor',
                                              'userId': int.tryParse(
                                                widget.user.id,
                                              ),
                                              'driverId': int.tryParse(
                                                widget.user.driverId ?? '',
                                              ),
                                              'plantId': 0,
                                              'q': query,
                                            }),
                                          );
                                          if (response.statusCode < 300) {
                                            final data =
                                                jsonDecode(response.body)
                                                    as Map<String, dynamic>? ??
                                                const <String, dynamic>{};
                                            final status =
                                                (data['status'] ?? '')
                                                    .toString()
                                                    .trim()
                                                    .toLowerCase();
                                            if (status == 'ok') {
                                              final rows =
                                                  data['vehicles']
                                                      as List<dynamic>? ??
                                                  const [];
                                              final remote = <_VehicleOption>[];
                                              for (final row in rows) {
                                                if (row
                                                    is! Map<String, dynamic>)
                                                  continue;
                                                final id =
                                                    int.tryParse(
                                                      row['id']?.toString() ??
                                                          '',
                                                    ) ??
                                                    0;
                                                final number =
                                                    (row['vehicle_no'] ??
                                                            row['number'] ??
                                                            row['vehicleNumber'] ??
                                                            '')
                                                        .toString()
                                                        .trim();
                                                if (id <= 0 || number.isEmpty)
                                                  continue;
                                                final plantId =
                                                    int.tryParse(
                                                      row['plant_id']
                                                              ?.toString() ??
                                                          '',
                                                    ) ??
                                                    0;
                                                final plantName =
                                                    (row['plant_name'] ??
                                                            row['plantName'] ??
                                                            '')
                                                        .toString()
                                                        .trim();
                                                remote.add(
                                                  _VehicleOption(
                                                    id: id,
                                                    number: number,
                                                    plantId: plantId > 0
                                                        ? plantId
                                                        : null,
                                                    plantName: plantName,
                                                  ),
                                                );
                                              }
                                              // Merge local + remote results
                                              final merged =
                                                  <int, _VehicleOption>{
                                                    for (final v
                                                        in filteredVehicles)
                                                      v.id: v,
                                                    for (final v in remote)
                                                      v.id: v,
                                                  };
                                              filteredVehicles = merged.values
                                                  .toList(growable: false);
                                            }
                                          }
                                        } catch (e) {
                                          vehicleRemoteError = e.toString();
                                        } finally {
                                          isVehicleRemoteLoading = false;
                                          setSheetState(() {});
                                        }
                                      },
                                    );
                                  }
                                }
                              },
                            ),
                            if (_vehicleLoadError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _vehicleLoadError!,
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            if (vehicleRemoteError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  vehicleRemoteError!,
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            if (showVehicleList && filteredVehicles.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filteredVehicles.length,
                                  itemBuilder: (context, index) {
                                    final v = filteredVehicles[index];
                                    final isSelected =
                                        selectedVehicleId == v.id;
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        Icons.directions_bus,
                                        color: isSelected
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 20,
                                      ),
                                      title: Text(
                                        v.displayLabel,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? Colors.green.shade700
                                              : Colors.black,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? Icon(
                                              Icons.check_circle,
                                              color: Colors.green.shade600,
                                              size: 20,
                                            )
                                          : null,
                                      onTap: () {
                                        selectedVehicleId = v.id;
                                        selectedVehicleNumber = v.number;
                                        selectedVehiclePlantId = v.plantId;
                                        selectedVehiclePlantName = v.plantName;
                                        vehicleSearchController.text =
                                            v.displayLabel;
                                        showVehicleList = false;
                                        setSheetState(() {});
                                      },
                                    );
                                  },
                                ),
                              ),
                            if (showVehicleList &&
                                filteredVehicles.isEmpty &&
                                vehicleSearchController.text.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey.shade50,
                                ),
                                child: Text(
                                  'No vehicles found for "${vehicleSearchController.text}"',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                          if (needsDriverSelection) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Select Driver *',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: advanceDriverSearchController,
                              enabled:
                                  _driversList.isNotEmpty &&
                                  _driverLoadErrorMessage == null,
                              decoration: InputDecoration(
                                hintText:
                                    _driverLoadErrorMessage ??
                                    (_driversList.isEmpty
                                        ? 'Loading drivers...'
                                        : 'Type driver name to search...'),
                                border: const OutlineInputBorder(),
                                prefixIcon: _driverLoadErrorMessage != null
                                    ? const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                      )
                                    : _driversList.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: AppLoader(size: 20),
                                        ),
                                      )
                                    : const Icon(Icons.search),
                                suffixIcon: advanceSelectedDriverId != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: clearAdvanceDriver,
                                      )
                                    : null,
                              ),
                              onTap: () {
                                showAdvanceDriverList = true;
                                setSheetState(() {});
                              },
                              onChanged: (value) {
                                showAdvanceDriverList = true;
                                advanceFilteredDrivers = _driversList
                                    .where(
                                      (driver) => driver['name']
                                          .toString()
                                          .toLowerCase()
                                          .contains(value.toLowerCase()),
                                    )
                                    .toList();
                                setSheetState(() {});
                              },
                            ),
                            if (_driverLoadErrorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _driverLoadErrorMessage!,
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            if (showAdvanceDriverList &&
                                advanceFilteredDrivers.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: advanceFilteredDrivers.length,
                                  itemBuilder: (context, index) {
                                    final driver =
                                        advanceFilteredDrivers[index];
                                    final isSelected =
                                        advanceSelectedDriverId ==
                                        driver['id'].toString();
                                    final plantName = (driver['plant'] ?? '')
                                        .toString();
                                    final rawPlantId =
                                        driver['plant_id'] ??
                                        driver['plantId'] ??
                                        driver['plantID'] ??
                                        driver['plant_id_fk'];
                                    final plantId = int.tryParse(
                                      rawPlantId?.toString() ?? '',
                                    );
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        Icons.person,
                                        color: isSelected
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 20,
                                      ),
                                      title: Text(
                                        driver['name'],
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? Colors.green.shade700
                                              : Colors.black,
                                        ),
                                      ),
                                      subtitle: Text(
                                        plantName.isNotEmpty
                                            ? 'ID: ${driver['id']} • Plant: $plantName'
                                            : 'ID: ${driver['id']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: isSelected
                                          ? Icon(
                                              Icons.check_circle,
                                              color: Colors.green.shade600,
                                              size: 20,
                                            )
                                          : null,
                                      onTap: () {
                                        advanceSelectedDriverId = driver['id']
                                            .toString();
                                        advanceSelectedDriverName =
                                            driver['name'].toString();
                                        advanceSelectedDriverPlant = plantName;
                                        advanceSelectedDriverPlantId =
                                            (plantId != null && plantId > 0)
                                            ? plantId
                                            : null;
                                        showAdvanceDriverList = false;
                                        setSheetState(() {});
                                      },
                                    );
                                  },
                                ),
                              ),
                            if (showAdvanceDriverList &&
                                advanceFilteredDrivers.isEmpty &&
                                advanceDriverSearchController.text.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey.shade50,
                                ),
                                child: Text(
                                  'No drivers found for "${advanceDriverSearchController.text}"',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (advanceSelectedDriverId != null &&
                                advanceSelectedDriverName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.person, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            advanceSelectedDriverPlant
                                                    .isNotEmpty
                                                ? '$advanceSelectedDriverName (ID: $advanceSelectedDriverId • Plant: $advanceSelectedDriverPlant)'
                                                : '$advanceSelectedDriverName (ID: $advanceSelectedDriverId)',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 16),
                          if (!isAdvanceCategory)
                            TextField(
                              controller: extraNotesController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Additional description (optional)',
                                hintText: 'Add more details for this entry',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          if (!isAdvanceCategory) const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: const Icon(Icons.calendar_today),
                              title: Text('Date: ${_formatDate(selectedDate)}'),
                              subtitle: Text(_formatTime(selectedDate)),
                              trailing: const Icon(Icons.edit),
                              onTap: handleDateChange,
                            ),
                          ),
                          if (!isAdvanceReceived) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Receipt (Optional)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (_selectedReceiptPath != null)
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(
                                                0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.green.withOpacity(
                                                  0.3,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _selectedReceiptPath
                                                              ?.endsWith(
                                                                '.pdf',
                                                              ) ==
                                                          true
                                                      ? Icons.picture_as_pdf
                                                      : Icons.receipt,
                                                  size: 16,
                                                  color: Colors.green,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _selectedReceiptPath
                                                              ?.endsWith(
                                                                '.pdf',
                                                              ) ==
                                                          true
                                                      ? 'PDF Selected'
                                                      : 'Receipt Selected',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (_selectedReceiptPath != null)
                                        const SizedBox(width: 12),
                                      GestureDetector(
                                        onTap: _isUploadingPhoto
                                            ? null
                                            : pickReceipt,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isUploadingPhoto
                                                ? Colors.grey.withOpacity(0.3)
                                                : Colors.blue.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: _isUploadingPhoto
                                                  ? Colors.grey.withOpacity(0.3)
                                                  : Colors.blue.withOpacity(
                                                      0.3,
                                                    ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_isUploadingPhoto)
                                                const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: AppLoader(size: 12),
                                                )
                                              else
                                                Icon(
                                                  _selectedReceiptPath != null
                                                      ? Icons.edit
                                                      : Icons.attach_file,
                                                  size: 16,
                                                  color: _isUploadingPhoto
                                                      ? Colors.grey
                                                      : Colors.blue,
                                                ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _isUploadingPhoto
                                                    ? 'Selecting...'
                                                    : (_selectedReceiptPath !=
                                                              null
                                                          ? 'Change'
                                                          : 'Attach Receipt'),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: _isUploadingPhoto
                                                      ? Colors.grey
                                                      : Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: vehicleSelectedOk
                                      ? () async {
                                          final amount = double.tryParse(
                                            amountController.text,
                                          );
                                          if (amount == null || amount <= 0) {
                                            showAppToast(
                                              context,
                                              'Please enter a valid amount',
                                              isError: true,
                                            );
                                            return;
                                          }
                                          final extraNotes =
                                              extraNotesController.text.trim();

                                          // Description stored in DB should now be ONLY the extra notes
                                          // (or an auto-generated text for advance driver flows), not the
                                          // selected category label. Category itself is stored separately.
                                          var descriptionText = extraNotes;

                                          if (descriptionText.isEmpty &&
                                              isAdvanceCategory) {
                                            final plantSuffix =
                                                advanceSelectedDriverPlant
                                                    .isNotEmpty
                                                ? ' ($advanceSelectedDriverPlant)'
                                                : '';
                                            descriptionText =
                                                'Advance for $advanceSelectedDriverName$plantSuffix';
                                          }
                                          if (requiresVehicleSelection &&
                                              (selectedVehicleNumber == null ||
                                                  selectedVehicleNumber!
                                                      .isEmpty)) {
                                            showAppToast(
                                              context,
                                              'Vehicle number is required for this description.',
                                              isError: true,
                                            );
                                            return;
                                          }
                                          if (needsDriverSelection &&
                                              (_driverLoadErrorMessage !=
                                                      null ||
                                                  _driversList.isEmpty)) {
                                            showAppToast(
                                              context,
                                              _driverLoadErrorMessage ??
                                                  'Driver list is unavailable. Please refresh and try again.',
                                              isError: true,
                                            );
                                            return;
                                          }
                                          if (needsDriverSelection &&
                                              advanceSelectedDriverId == null) {
                                            showAppToast(
                                              context,
                                              'Select a driver for this entry.',
                                              isError: true,
                                            );
                                            return;
                                          }
                                          var finalDescription =
                                              descriptionText;
                                          if (!isAdvanceReceived &&
                                              (selectedVehicleNumber
                                                      ?.isNotEmpty ??
                                                  false)) {
                                            final plantPart =
                                                (selectedVehiclePlantName ?? '')
                                                    .trim();
                                            final vehiclePart =
                                                plantPart.isNotEmpty
                                                ? '$selectedVehicleNumber ($plantPart)'
                                                : '$selectedVehicleNumber';
                                            finalDescription =
                                                finalDescription.isEmpty
                                                ? 'Vehicle: $vehiclePart'
                                                : '$finalDescription (Vehicle: $vehiclePart)';
                                          }

                                          // Ensure "ADVANCE" prefix for advance entries
                                          if (isAdvanceCategory) {
                                            var rest = finalDescription.trim();

                                            // If "advance" is already at start, drop it (we'll re-add as uppercase).
                                            rest = rest.replaceFirst(
                                              RegExp(
                                                r'^advance\b\s*[-–—:]*\s*',
                                                caseSensitive: false,
                                              ),
                                              '',
                                            );

                                            // If "advance" is at end (e.g. "... - ADVANCE"), drop it and move to start.
                                            rest = rest.replaceFirst(
                                              RegExp(
                                                r'[-–—:]*\s*advance\b\s*$',
                                                caseSensitive: false,
                                              ),
                                              '',
                                            );

                                            rest = rest.trim();
                                            finalDescription = rest.isEmpty
                                                ? 'ADVANCE -'
                                                : 'ADVANCE - $rest';
                                          }
                                          Navigator.of(sheetContext).pop();
                                          final type = isAdvanceReceived
                                              ? 'advance_received'
                                              : 'expense';
                                          print('🔵 CREATING TRANSACTION');
                                          print('🔵 Type: $type');
                                          print('🔵 Amount: $amount');
                                          print(
                                            '🔵 Description: $finalDescription',
                                          );
                                          print(
                                            '🔵 Selected Receipt Path: $_selectedReceiptPath',
                                          );

                                          // If this is an advance entry with a target driver, treat it like a fund transfer
                                          if (isAdvanceCategory &&
                                              advanceSelectedDriverId != null) {
                                            final currentDriverId =
                                                widget.user.driverId ??
                                                widget.user.id;
                                            final receiverId = isAdvanceReceived
                                                ? currentDriverId
                                                : advanceSelectedDriverId!;
                                            final transferSenderId =
                                                isAdvanceReceived
                                                ? advanceSelectedDriverId!
                                                : currentDriverId;

                                            try {
                                              final transferDescription =
                                                  isAdvanceCategory
                                                  ? 'Advance'
                                                  : finalDescription;
                                              await _financeRepository
                                                  .submitFundTransfer(
                                                    driverId: receiverId,
                                                    senderId: transferSenderId,
                                                    amount: amount,
                                                    description:
                                                        transferDescription,
                                                    category: isAdvanceCategory
                                                        ? selectedDescriptionLabel
                                                        : null,
                                                    senderName:
                                                        widget.user.displayName,
                                                    timestamp: selectedDate
                                                        .toIso8601String(),
                                                  );
                                              await _loadData();
                                              showAppToast(
                                                context,
                                                'Advance recorded for $advanceSelectedDriverName',
                                              );
                                            } catch (e) {
                                              showAppToast(
                                                context,
                                                'Failed to save advance: $e',
                                                isError: true,
                                              );
                                            }
                                            return;
                                          }

                                          final transactionId = await _addTransactionWithDate(
                                            type,
                                            amount,
                                            descriptionText.isEmpty
                                                ? finalDescription
                                                : descriptionText,
                                            selectedDate,
                                            // For driver-required categories like SALARY/UNIFORM,
                                            // store the entry in the current user's Khata Book,
                                            // and attach the selected driver as counterparty.
                                            counterpartyDriverId:
                                                needsDriverSelection
                                                ? int.tryParse(
                                                    advanceSelectedDriverId ??
                                                        '',
                                                  )
                                                : null,
                                            counterpartyPlantId:
                                                needsDriverSelection
                                                ? advanceSelectedDriverPlantId
                                                : null,
                                            vehicleId: selectedVehicleId,
                                            vehiclePlantId:
                                                selectedVehiclePlantId,
                                            // Store the base description label separately as category
                                            category: selectedDescriptionLabel,
                                          );
                                          print(
                                            '🔵 Transaction ID returned: $transactionId',
                                          );
                                          if (!isAdvanceReceived &&
                                              (transactionId != null) &&
                                              (_selectedReceiptPath != null ||
                                                  _selectedReceiptBytes !=
                                                      null)) {
                                            try {
                                              print('🔵 RECEIPT UPLOAD START');
                                              print(
                                                '🔵 Transaction ID: $transactionId',
                                              );
                                              print(
                                                '🔵 Driver ID: ${widget.user.driverId ?? widget.user.id}',
                                              );
                                              if (_selectedReceiptPath !=
                                                  null) {
                                                print(
                                                  '🔵 File path: $_selectedReceiptPath',
                                                );
                                                try {
                                                  final file = File(
                                                    _selectedReceiptPath!,
                                                  );
                                                  final fileExists = await file
                                                      .exists();
                                                  print(
                                                    '🔵 File exists: $fileExists',
                                                  );
                                                  if (fileExists) {
                                                    final fileSize = await file
                                                        .length();
                                                    print(
                                                      '🔵 File size: $fileSize bytes',
                                                    );
                                                  }
                                                } catch (_) {
                                                  // Ignore on web/no file access
                                                }
                                              }
                                              final response = await _financeRepository
                                                  .uploadReceipt(
                                                    transactionId:
                                                        transactionId,
                                                    driverId:
                                                        widget.user.driverId ??
                                                        widget.user.id,
                                                    filePath:
                                                        _selectedReceiptBytes ==
                                                            null
                                                        ? _selectedReceiptPath
                                                        : null,
                                                    bytes:
                                                        _selectedReceiptBytes,
                                                    fileName:
                                                        _selectedReceiptName,
                                                  );
                                              print(
                                                '🟢 Upload response: $response',
                                              );
                                              if (response['status'] == 'ok') {
                                                showAppToast(
                                                  context,
                                                  'Receipt uploaded successfully',
                                                );
                                                print(
                                                  '🟢 Receipt upload SUCCESS',
                                                );
                                                if (mounted) {
                                                  final path =
                                                      response['receiptPath']
                                                          ?.toString();
                                                  if (path != null &&
                                                      path.isNotEmpty) {
                                                    final transactionIdStr =
                                                        transactionId
                                                            .toString();
                                                    var updated = false;
                                                    setState(() {
                                                      _transactions =
                                                          _transactions.map((
                                                            txn,
                                                          ) {
                                                            if (txn.id ==
                                                                transactionIdStr) {
                                                              updated = true;
                                                              return txn
                                                                  .copyWith(
                                                                    receiptPath:
                                                                        path,
                                                                  );
                                                            }
                                                            return txn;
                                                          }).toList();
                                                      _filteredTransactions =
                                                          _filteredTransactions.map((
                                                            txn,
                                                          ) {
                                                            if (txn.id ==
                                                                transactionIdStr) {
                                                              updated = true;
                                                              return txn
                                                                  .copyWith(
                                                                    receiptPath:
                                                                        path,
                                                                  );
                                                            }
                                                            return txn;
                                                          }).toList();
                                                    });
                                                    _filterTransactions();
                                                    Future.delayed(
                                                      const Duration(
                                                        milliseconds: 600,
                                                      ),
                                                      () {
                                                        if (mounted) {
                                                          _loadData();
                                                        }
                                                      },
                                                    );
                                                  }
                                                }
                                              } else {
                                                print(
                                                  '🔴 Receipt upload FAILED: ${response['error']}',
                                                );
                                                showAppToast(
                                                  context,
                                                  'Receipt upload failed: ${response['error'] ?? 'Unknown error'}',
                                                  isError: true,
                                                );
                                              }
                                            } catch (error) {
                                              print(
                                                '🔴 Upload exception: $error',
                                              );
                                              print(
                                                '🔴 Exception type: ${error.runtimeType}',
                                              );
                                              showAppToast(
                                                context,
                                                'Error uploading receipt: $error',
                                                isError: true,
                                              );
                                            }
                                            print(
                                              '🔵 Receipt upload process completed',
                                            );
                                          } else {
                                            print('🔵 Receipt upload SKIPPED');
                                            print(
                                              '🔵 isAdvanceReceived: $isAdvanceReceived',
                                            );
                                            print(
                                              '🔵 selectedReceiptPath: $_selectedReceiptPath',
                                            );
                                            print(
                                              '🔵 transactionId: $transactionId',
                                            );
                                          }
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Add'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        amountController.dispose();
        extraNotesController.dispose();
        advanceDriverSearchController.dispose();
        vehicleSearchController.dispose();
        vehicleDebounce?.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.book, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Khata Book', style: TextStyle(color: Colors.white)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF12355B),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (widget.user.canViewDocuments)
            IconButton(
              tooltip: 'All User Expenses',
              icon: const Icon(Icons.public),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => KhataAllExpensesScreen(user: widget.user),
                  ),
                );
              },
            ),
        ],
      ),
      body: Container(
        color: Colors.grey[200],
        child: _isLoading
            ? const Center(child: AppLoader())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfileSection(),
                      const SizedBox(height: 16),
                      _buildBalanceCard(),
                      const SizedBox(height: 16),
                      _buildTransactionHistory(),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _buildBottomButtons(),
    );
  }

  Widget _buildProfileSection() {
    return Row(
      children: [
        ProfilePhotoWithUpload(
          user: widget.user,
          radius: 30,
          onPhotoSelected: _handlePhotoSelected,
          isUploading: _isUploadingPhoto,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.user.displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Driver',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            // TODO: Implement call functionality
          },
          icon: const Icon(Icons.phone),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    final isPositive = _currentBalance >= 0;
    final bgColor = isPositive
        ? const Color(0xFFE8F5E9) // light green
        : const Color(0xFFFFEBEE); // light red

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPositive ? 'You will get' : 'You will give',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatInrSigned(_currentBalance),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _showFundTransferDialog,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.sync_alt, size: 18),
                    label: const Text('Fund Transfer'),
                  ),
                  const SizedBox(height: 6),
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
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_selectedMonthCompactLabel()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory() {
    if (_filteredTransactions.isEmpty) {
      return Center(
        child: Text(
          _transactions.isEmpty
              ? 'No transactions found'
              : 'No transactions found for ${_currentFilterLabel()}',
        ),
      );
    }

    // Group transactions by date with the latest entries first
    final groupedTransactions = <DateTime, List<AdvanceTransaction>>{};
    for (final transaction in _filteredTransactions) {
      final createdAt = _parseTransactionDate(transaction.createdAt);
      final dateKey = DateTime(createdAt.year, createdAt.month, createdAt.day);
      groupedTransactions.putIfAbsent(dateKey, () => []).add(transaction);
    }

    final sortedDates = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    double youGaveTotal = 0.0;
    double youGotTotal = 0.0;
    for (final t in _filteredTransactions) {
      if (t.type == 'expense') {
        youGaveTotal += t.amount;
      } else if (t.type == 'advance_received') {
        youGotTotal += t.amount;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ENTRIES (${_filteredTransactions.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'YOU GAVE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatInr(youGaveTotal),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'YOU GOT',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatInr(youGotTotal),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const SizedBox(height: 8),
        // Display transactions grouped by date
        ...sortedDates.map((dateKey) {
          final transactions = groupedTransactions[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDateHeaderWithTodayYesterday(dateKey),
              const SizedBox(height: 8),
              // Display each transaction individually
              ...transactions.map((transaction) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showTransactionDetail(transaction),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ENTRIES Column (Left) - Date, Time, Balance, Description
                        Expanded(flex: 3, child: _buildEntryCard(transaction)),
                        const SizedBox(width: 8),
                        // YOU GAVE Column (Middle) - Red amounts
                        Expanded(
                          flex: 1,
                          child: transaction.type == 'expense'
                              ? _buildAmountCard(transaction, isYouGot: false)
                              : const SizedBox(height: 60),
                        ),
                        const SizedBox(width: 8),
                        // YOU GOT Column (Right) - Green amounts
                        Expanded(
                          flex: 1,
                          child: transaction.type == 'advance_received'
                              ? _buildAmountCard(transaction, isYouGot: true)
                              : const SizedBox(height: 60),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          );
        }),
      ],
    );
  }

  String _formatDateKey(DateTime date) {
    return '${date.day} ${_getMonthName(date.month)} ${date.year}';
  }

  String _getMonthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  Widget _buildDateHeaderWithTodayYesterday(DateTime date) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    final displayKey = _formatDateKey(date);
    final entryDate = DateTime(date.year, date.month, date.day);
    final todayDate = DateTime(now.year, now.month, now.day);
    final yesterdayDate = DateTime(
      yesterday.year,
      yesterday.month,
      yesterday.day,
    );

    String displayText = displayKey;
    if (entryDate.isAtSameMomentAs(todayDate)) {
      displayText = '$displayKey - Today';
    } else if (entryDate.isAtSameMomentAs(yesterdayDate)) {
      displayText = '$displayKey - Yesterday';
    }

    return Text(
      displayText,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  // ENTRIES Column Card (Left) - Date, Time, Balance, Description
  Widget _buildEntryCard(AdvanceTransaction transaction) {
    // Get current user's driver ID - use driverId if available, otherwise use user ID
    final currentDriverId = widget.user.driverId ?? widget.user.id;
    final canDelete = _canDeleteTransaction(transaction, currentDriverId);

    String buildMetaLine() {
      final parts = <String>[];
      if (transaction.vehicleId != null && transaction.vehicleId! > 0) {
        parts.add('Vehicle ID: ${transaction.vehicleId}');
      }
      if (transaction.vehiclePlantId != null &&
          transaction.vehiclePlantId! > 0) {
        parts.add('Vehicle Plant ID: ${transaction.vehiclePlantId}');
      }
      if (transaction.counterpartyDriverId != null &&
          transaction.counterpartyDriverId! > 0) {
        parts.add('Driver ID: ${transaction.counterpartyDriverId}');
      }
      if (transaction.counterpartyPlantId != null &&
          transaction.counterpartyPlantId! > 0) {
        parts.add('Driver Plant ID: ${transaction.counterpartyPlantId}');
      }
      return parts.join(' • ');
    }

    final metaLine = buildMetaLine();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with date-time and delete button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _formatDateTime(transaction.createdAt),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (canDelete)
                IconButton(
                  onPressed: () => _confirmDeleteTransaction(transaction),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  tooltip: _getDeleteTooltip(transaction),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Balance
          if (transaction.runningBalance != null)
            Text(
              'Bal. ${transaction.formattedBalance}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 4),
          if (_isFundTransferTransaction(transaction))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildFundTransferLabel(transaction),
            ),
          // Description (full text with smaller font)
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatTransactionDescription(transaction),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
              // Show receipt attachment icon if receipt exists
              if (transaction.receiptPath != null &&
                  transaction.receiptPath!.isNotEmpty)
                GestureDetector(
                  onTap: () => _viewReceipt(transaction.receiptPath!),
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.receipt,
                      size: 16,
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
          if (metaLine.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              metaLine,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showTransactionDetail(AdvanceTransaction transaction) {
    final createdAt = _parseTransactionDate(transaction.createdAt);
    final isEditLocked = _isEditLockedTransaction(transaction);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        transaction.type == 'expense'
                            ? 'Expense'
                            : 'Advance Received',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Amount: ${_formatInr(transaction.amount)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Date: ${_formatDateTime(transaction.createdAt)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  if (transaction.runningBalance != null)
                    Text(
                      'Running Balance: ${transaction.formattedBalance}',
                      style: const TextStyle(fontSize: 14, color: Colors.red),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Description:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTransactionDescription(transaction),
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (transaction.category != null &&
                      transaction.category!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Category: ${transaction.category}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (transaction.vehicleId != null ||
                      transaction.vehiclePlantId != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Vehicle: '
                      '${transaction.vehicleId ?? '-'}'
                      '${transaction.vehiclePlantId != null ? ' • Plant ${transaction.vehiclePlantId}' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (transaction.counterpartyDriverId != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Counterparty Driver ID: ${transaction.counterpartyDriverId}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (transaction.receiptPath != null &&
                      transaction.receiptPath!.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _viewReceipt(transaction.receiptPath!),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('View Receipt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isEditLocked
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  _showEditTransactionSheet(
                                    transaction,
                                    createdAt,
                                  );
                                },
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit Transaction'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _confirmDeleteTransaction(transaction);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEditTransactionSheet(
    AdvanceTransaction transaction,
    DateTime initialDate,
  ) {
    if (_isEditLockedTransaction(transaction)) {
      showAppToast(context, 'This category cannot be edited.', isError: true);
      return;
    }
    final amountController = TextEditingController(
      text: transaction.amount.toStringAsFixed(0),
    );
    final descriptionController = TextEditingController(
      text: transaction.description,
    );
    DateTime selectedDate = initialDate;
    String? selectedDescriptionLabel =
        transaction.category?.trim().isNotEmpty == true
        ? transaction.category
        : (_descriptionOptions.isNotEmpty
              ? _descriptionOptions.first.label
              : transaction.description);

    Future<_DescriptionOption?> pickCategory() async {
      if (_descriptionOptions.isEmpty) return null;
      final hasVehicle =
          transaction.vehicleId != null && transaction.vehicleId! > 0;
      final hasCounterpartyDriver =
          transaction.counterpartyDriverId != null &&
          transaction.counterpartyDriverId! > 0;
      final hasCounterparty = hasCounterpartyDriver;

      // Rules requested:
      // - If vehicle is present: show only vehicle_mandatory=Y categories.
      // - Else if counterparty driver is present: show only the same driver-required
      //   categories used in "You Gave" flow.
      // - Else (no vehicle + no driver): show only the current category (e.g. EXTRA).
      final options = hasVehicle
          ? _descriptionOptions.where((opt) => opt.vehicleMandatory).toList()
          : (hasCounterparty
                ? _descriptionOptions
                      .where(
                        (opt) => _isDriverMandatory(
                          opt.label,
                          isAdvanceReceived: false, // "You Gave" rules
                        ),
                      )
                      .toList()
                : () {
                    final current = (selectedDescriptionLabel ?? '').trim();
                    if (current.isEmpty) return _descriptionOptions.toList();
                    final match = _descriptionOptions
                        .where((opt) => opt.label == current)
                        .toList();
                    return match.isNotEmpty
                        ? match
                        : <_DescriptionOption>[
                            _DescriptionOption(label: current),
                          ];
                  }());

      if (options.isEmpty) {
        // Fallback: if vehicle categories are not configured, don't block editing.
        // (Better than showing an empty dialog.)
        return showDialog<_DescriptionOption>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Select Category'),
            children: _descriptionOptions
                .map(
                  (opt) => SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(opt),
                    child: Text(opt.label),
                  ),
                )
                .toList(),
          ),
        );
      }
      return showDialog<_DescriptionOption>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(
            hasVehicle
                ? 'Select Category (Vehicle)'
                : (hasCounterparty
                      ? 'Select Category (Driver)'
                      : 'Select Category'),
          ),
          children: options
              .map(
                (opt) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(opt),
                  child: Text(opt.label),
                ),
              )
              .toList(),
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> pickDateTime() async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedDate),
                  );
                  if (time != null) {
                    setSheetState(() {
                      selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                }
              }

              String? vehicleLabelFor(int? id) {
                if (id == null || id <= 0) return null;
                final match = _vehicleOptions.where((v) => v.id == id).toList();
                if (match.isNotEmpty) return match.first.displayLabel;
                return 'Vehicle #$id';
              }

              String? driverLabelFor(String? id) {
                if (id == null || id.isEmpty) return null;
                final match = _driversList.firstWhere(
                  (d) =>
                      d['id']?.toString() == id ||
                      d['driver_id']?.toString() == id ||
                      d['driverId']?.toString() == id,
                  orElse: () => {},
                );
                if (match.isEmpty) return 'Driver #$id';
                return match['name']?.toString() ??
                    match['driver_name']?.toString() ??
                    match['driverName']?.toString() ??
                    'Driver #$id';
              }

              final vehicleLabel = vehicleLabelFor(transaction.vehicleId);
              final driverLabel = driverLabelFor(
                (transaction.counterpartyDriverId ?? transaction.driverId)
                    .toString(),
              );
              final driverIdDisplay =
                  (transaction.counterpartyDriverId ??
                          int.tryParse(transaction.driverId))
                      ?.toString();
              final vehicleIdDisplay =
                  transaction.vehicleId != null && transaction.vehicleId! > 0
                  ? transaction.vehicleId.toString()
                  : null;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Transaction',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₹ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: selectedDescriptionLabel,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        suffixIcon: _descriptionOptions.isNotEmpty
                            ? const Icon(Icons.arrow_drop_down)
                            : null,
                      ),
                      onTap: _descriptionOptions.isEmpty
                          ? null
                          : () async {
                              final selected = await pickCategory();
                              if (selected != null) {
                                setSheetState(
                                  () =>
                                      selectedDescriptionLabel = selected.label,
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    if (vehicleLabel != null || driverLabel != null)
                      const SizedBox(height: 12),
                    if (vehicleLabel != null)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.directions_bus, size: 20),
                        title: const Text(
                          'Vehicle',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          vehicleIdDisplay != null
                              ? '$vehicleLabel (ID: $vehicleIdDisplay)'
                              : vehicleLabel,
                        ),
                      ),
                    if (driverLabel != null)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person, size: 20),
                        title: const Text(
                          'Driver',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          driverIdDisplay != null
                              ? '$driverLabel (ID: $driverIdDisplay)'
                              : driverLabel,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Date: ${_formatDateTime(selectedDate.toIso8601String())}',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: pickDateTime,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text('Change'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final amount = double.tryParse(
                            amountController.text.trim(),
                          );
                          final description = descriptionController.text.trim();
                          if (amount == null || amount <= 0) {
                            showAppToast(
                              context,
                              'Enter a valid amount',
                              isError: true,
                            );
                            return;
                          }
                          if (description.isEmpty) {
                            showAppToast(
                              context,
                              'Enter a description',
                              isError: true,
                            );
                            return;
                          }

                          Navigator.of(context).pop(); // close sheet
                          await _replaceTransaction(
                            transaction,
                            type: transaction.type,
                            amount: amount,
                            description: description,
                            date: selectedDate,
                            category: selectedDescriptionLabel,
                          );
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _replaceTransaction(
    AdvanceTransaction original, {
    required String type,
    required double amount,
    required String description,
    required DateTime date,
    String? category,
  }) async {
    try {
      setState(() => _isLoading = true);
      await _financeRepository.deleteTransaction(original.id);
      await _addTransactionWithDate(
        type,
        amount,
        description,
        date,
        targetDriverId: original.driverId,
        vehicleId: original.vehicleId,
        vehiclePlantId: original.vehiclePlantId,
        category: category ?? original.category,
      );
      await _loadData();
      if (mounted) {
        showAppToast(context, 'Transaction updated.');
      }
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          'Failed to update transaction: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Amount Card for YOU GAVE/YOU GOT columns
  Widget _buildAmountCard(
    AdvanceTransaction transaction, {
    bool isYouGot = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          transaction.formattedAmount.trim(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isYouGot ? Colors.green : Colors.red,
          ),
        ),
      ),
    );
  }

  Widget _buildFundTransferLabel(AdvanceTransaction transaction) {
    final isReceived = transaction.type == 'advance_received';
    final counterpartyName = _extractFundTransferCounterpartyName(transaction);
    final actionColor = isReceived
        ? Colors.green.shade700
        : Colors.red.shade700;
    final highlightColor = (isReceived ? Colors.green : Colors.red).withOpacity(
      0.12,
    ); // subtle background

    final buttons = <Widget>[
      TextButton.icon(
        onPressed: () => _showFundTransferDetails(transaction),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          backgroundColor: highlightColor,
          foregroundColor: actionColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: Icon(
          isReceived ? Icons.call_received : Icons.call_made,
          size: 16,
        ),
        label: Text(
          isReceived ? 'Fund Transfer · Received' : 'Fund Transfer · Sent',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    ];

    if (counterpartyName != null && counterpartyName.isNotEmpty) {
      buttons.add(
        OutlinedButton(
          onPressed: () => _showFundTransferDetails(transaction),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            foregroundColor: Colors.blue.shade700,
            side: BorderSide(color: Colors.blue.shade200),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            isReceived ? 'From $counterpartyName' : 'To $counterpartyName',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 4, children: buttons);
  }

  bool _isFundTransferTransaction(AdvanceTransaction transaction) {
    final description = transaction.description.toLowerCase();
    return description.contains('fund transfer to') ||
        description.contains('fund transfer from');
  }

  String _formatTransactionDescription(AdvanceTransaction transaction) {
    // Base description comes from DB (extra notes / auto text).
    var description = transaction.description.trim();
    description = _replaceDriverIdPlaceholders(description);
    description = _normalizeAdvanceLabel(description);

    // If category is present, show it before the description (for UI only).
    final category = transaction.category?.trim() ?? '';
    if (category.isNotEmpty) {
      if (description.isEmpty) return category;
      return '$category - $description';
    }
    return description;
  }

  String _normalizeAdvanceLabel(String description) {
    var text = description.trim();
    if (text.isEmpty) return text;

    final hasAdvance = RegExp(
      r'\badvance\b',
      caseSensitive: false,
    ).hasMatch(text);
    if (!hasAdvance) return text;

    // Remove ALL "advance" tokens anywhere, then prefix once at start.
    text = text.replaceAll(RegExp(r'\badvance\b', caseSensitive: false), '');

    // Clean up leftover separators/spaces (common patterns: " - ", ":", "—")
    text = text.replaceAll(RegExp(r'\s*[-–—:]\s*'), ' ');
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    return text.isEmpty ? 'ADVANCE -' : 'ADVANCE - $text';
  }

  String _replaceDriverIdPlaceholders(String description) {
    final idPattern = RegExp(r'Driver ID (\d+)', caseSensitive: false);
    return description.replaceAllMapped(idPattern, (match) {
      final driverId = match.group(1);
      final resolvedName = _lookupDriverName(driverId);
      if (resolvedName != null) {
        return resolvedName;
      }
      return match.group(0)!;
    });
  }

  String? _extractFundTransferCounterpartyName(AdvanceTransaction transaction) {
    if (!_isFundTransferTransaction(transaction)) {
      return null;
    }

    final description = transaction.description;
    final lower = description.toLowerCase();
    final marker = transaction.type == 'advance_received'
        ? 'fund transfer from '
        : 'fund transfer to ';
    final markerIndex = lower.indexOf(marker);
    if (markerIndex == -1) {
      return null;
    }

    final startIndex = markerIndex + marker.length;
    final endIndex = lower.indexOf(' - ', startIndex);
    final rawName =
        (endIndex == -1
                ? description.substring(startIndex)
                : description.substring(startIndex, endIndex))
            .trim();
    if (rawName.isEmpty) {
      return null;
    }

    final resolvedByName = _lookupDriverNameByName(rawName);
    if (resolvedByName != null) {
      return resolvedByName;
    }

    final sanitized = rawName.toLowerCase();
    if (sanitized == 'sender' || sanitized == 'receiver') {
      return null;
    }

    return rawName;
  }

  String? _lookupDriverName(String? driverId) {
    if (driverId == null) {
      return null;
    }
    final name = _driverNameCache[driverId];
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return null;
  }

  String? _lookupDriverNameByName(String rawName) {
    final search = rawName.trim().toLowerCase();
    if (search.isEmpty) {
      return null;
    }
    for (final entry in _driverNameCache.entries) {
      if (entry.value.toLowerCase() == search) {
        return entry.value;
      }
    }
    return null;
  }

  void _ensureCurrentUserCached() {
    final driverKey = widget.user.driverId ?? widget.user.id;
    final displayName = widget.user.displayName.trim();
    if (driverKey.toString().isEmpty) {
      return;
    }
    if (displayName.isEmpty) {
      return;
    }
    print(
      'DEBUG: Caching current user name - key: $driverKey, name: "$displayName"',
    );
    _driverNameCache[driverKey.toString()] = displayName;
  }

  void _showFundTransferDetails(AdvanceTransaction transaction) {
    final counterparty = _extractFundTransferCounterpartyName(transaction);
    final isReceived = transaction.type == 'advance_received';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isReceived ? 'Fund Transfer Received' : 'Fund Transfer Sent',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount: ${transaction.formattedAmount}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Counterparty: ${counterparty ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Description:\n${_formatTransactionDescription(transaction)}'),
            const SizedBox(height: 12),
            Text('Created at: ${_formatDateTime(transaction.createdAt)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final day = date.day.toString().padLeft(2, '0');
      final month = _getMonthName(date.month);
      final year = date.year.toString().substring(2); // Last 2 digits
      final minute = date.minute.toString().padLeft(2, '0');
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      final displayHour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);

      return '$day $month $year • ${displayHour.toString().padLeft(2, '0')}:$minute $ampm';
    } catch (e) {
      return 'Invalid Date';
    }
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showAddTransactionDialog(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('YOU GAVE ₹'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  showAppToast(
                    context,
                    'Ask Office to Make an Entry.',
                    isError: true,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('YOU GOT ₹'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFundTransferDialog() async {
    print('DEBUG: Opening fund transfer dialog');
    print('DEBUG: Drivers already loaded, total: ${_driversList.length}');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text(
                'YOU GOT - Fund Transfer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver Search Field
                    const Text(
                      'Search Driver',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Driver Search TextField
                    TextField(
                      controller: _driverSearchController,
                      focusNode: _searchFocusNode,
                      enabled:
                          _driversList.isNotEmpty &&
                          _driverLoadErrorMessage == null,
                      decoration: InputDecoration(
                        hintText:
                            _driverLoadErrorMessage ??
                            (_driversList.isEmpty
                                ? 'Loading drivers...'
                                : 'Type driver name to search...'),
                        border: const OutlineInputBorder(),
                        prefixIcon: _driverLoadErrorMessage != null
                            ? const Icon(Icons.error_outline, color: Colors.red)
                            : _driversList.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: AppLoader(size: 20),
                                ),
                              )
                            : const Icon(Icons.search),
                        suffixIcon: _selectedDriverId != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _selectedDriverId = null;
                                  _selectedDriverName = '';
                                  _driverSearchController.clear();
                                  _showDriverList = false;
                                  _filteredDriversList = List.from(
                                    _driversList,
                                  );
                                  setDialogState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        _filterDrivers(value);
                        setDialogState(() {}); // Trigger dialog rebuild
                      },
                      onTap: () {
                        if (_driverSearchController.text.isNotEmpty) {
                          _showDriverList = true;
                          setDialogState(() {});
                        }
                      },
                      textInputAction: TextInputAction.none,
                      keyboardType: TextInputType.text,
                    ),

                    if (_driverLoadErrorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _driverLoadErrorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    // Search Results List
                    if (_showDriverList && _filteredDriversList.isNotEmpty)
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
                          itemCount: _filteredDriversList.length,
                          itemBuilder: (context, index) {
                            final driver = _filteredDriversList[index];
                            final isSelected =
                                _selectedDriverId == driver['id'].toString();
                            final plantName = (driver['plant'] ?? '')
                                .toString();

                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.person,
                                color: isSelected ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                              title: Text(
                                driver['name'],
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.green.shade700
                                      : Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                plantName.isNotEmpty
                                    ? 'ID: ${driver['id']} • Plant: $plantName'
                                    : 'ID: ${driver['id']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade600,
                                      size: 20,
                                    )
                                  : null,
                              onTap: () => _selectDriver(
                                driver,
                                dialogSetState: setDialogState,
                              ),
                            );
                          },
                        ),
                      ),

                    // No Results Message
                    if (_showDriverList &&
                        _filteredDriversList.isEmpty &&
                        _driverSearchController.text.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(16),
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
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Transfer Amount
                    const Text(
                      'Transfer Amount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _transferAmountController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setDialogState(
                          () {},
                        ); // Trigger rebuild for button state
                      },
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Enter amount',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Transfer Description
                    const Text(
                      'Transfer Description',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _transferDescriptionController,
                      onChanged: (value) {
                        setDialogState(
                          () {},
                        ); // Trigger rebuild for button state
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'e.g., Advance payment, Salary advance',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Transfer Summary
                    if (_selectedDriverId != null &&
                        (double.tryParse(_transferAmountController.text) ?? 0) >
                            0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Transfer Summary',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Driver: $_selectedDriverName'),
                            Text(
                              'Transfer Amount: ₹ ${_transferAmountController.text}',
                            ),
                            Text(
                              'Description: ${_transferDescriptionController.text}',
                            ),
                            Text(
                              'Date: ${DateTime.now().toString().split(' ')[0]}',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _clearTransferForm();
                  },
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isTransferFormValid()
                      ? () async {
                          await _processFundTransfer();
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'TRANSFER FUND',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isTransferFormValid() {
    final amount = double.tryParse(_transferAmountController.text);
    return _driverLoadErrorMessage == null &&
        _selectedDriverId != null &&
        amount != null &&
        amount > 0 &&
        _transferDescriptionController.text.trim().isNotEmpty;
  }

  void _clearTransferForm() {
    _selectedDriverId = null;
    _selectedDriverName = '';
    _transferAmountController.clear();
    _transferDescriptionController.clear();
    _driverSearchController.clear();
    _showDriverList = false;
    _filteredDriversList = List.from(_driversList);
  }

  // Check if current user can delete this transaction
  bool _canDeleteTransaction(
    AdvanceTransaction transaction,
    String currentDriverId,
  ) {
    print(
      'DEBUG: _canDeleteTransaction called - CurrentDriverId: $currentDriverId, TransactionDriverId: ${transaction.driverId}, TransactionType: ${transaction.type}',
    );

    // Can't delete if no driver ID
    if (currentDriverId.isEmpty) {
      print('DEBUG: Cannot delete - no current driver ID');
      return false;
    }

    final description = transaction.description.toLowerCase();
    if (description.contains('advance office')) {
      return false;
    }

    // Check if this is a fund transfer transaction (very specific patterns)
    final isFundTransfer =
        description.contains('fund transfer to') ||
        description.contains('fund transfer from sender');

    if (isFundTransfer) {
      // For fund transfers, only the sender can delete
      // Sender has 'expense' type, receiver has 'advance_received' type
      if (transaction.type == 'expense') {
        // This is the sender's record - they can delete it
        return true;
      } else if (transaction.type == 'advance_received') {
        // This is the receiver's record - they cannot delete it
        return false;
      }
    }

    // For non-fund-transfer transactions, user can delete their own records
    final directMatch = transaction.driverId == currentDriverId;
    final stringMatch =
        transaction.driverId.toString() == currentDriverId.toString();
    final intMatch =
        int.tryParse(transaction.driverId.toString()) ==
        int.tryParse(currentDriverId.toString());
    final canDelete = directMatch || stringMatch || intMatch;

    return canDelete;
  }

  // Get appropriate tooltip for delete button
  String _getDeleteTooltip(AdvanceTransaction transaction) {
    final description = transaction.description.toLowerCase();
    final isFundTransfer =
        description.contains('fund transfer to') ||
        description.contains('fund transfer from sender');

    if (isFundTransfer) {
      return transaction.type == 'expense'
          ? 'Delete fund transfer (sender)'
          : 'Delete fund transfer (receiver)';
    }

    return 'Delete transaction';
  }

  // Confirm and delete transaction
  Future<void> _confirmDeleteTransaction(AdvanceTransaction transaction) async {
    // Determine if this is a fund transfer
    final description = transaction.description.toLowerCase();
    final isFundTransfer =
        description.contains('fund transfer to') ||
        description.contains('fund transfer from sender');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isFundTransfer ? 'Delete Fund Transfer' : 'Delete Transaction',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFundTransfer
                  ? 'Are you sure you want to delete this fund transfer?'
                  : 'Are you sure you want to delete this transaction?',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Amount: ${transaction.formattedAmount}'),
                  Text('Type: ${transaction.type}'),
                  Text(
                    'Description: ${_formatTransactionDescription(transaction)}',
                  ),
                  if (isFundTransfer) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        transaction.type == 'expense'
                            ? '⚠️ This will remove the fund transfer record'
                            : '⚠️ This is a received fund transfer',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _deleteTransaction(transaction);
  }

  // Delete transaction via API
  Future<void> _deleteTransaction(AdvanceTransaction transaction) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: AppLoader()),
      );

      // Call delete API
      await _financeRepository.deleteTransaction(transaction.id);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Reload data to refresh the list and balance
      await _loadData();

      // Show success message
      if (mounted) {
        showAppToast(context, 'Transaction deleted successfully');
      }
    } catch (error) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show error message
      if (mounted) {
        showAppToast(
          context,
          'Failed to delete transaction: ${error.toString()}',
          isError: true,
        );
      }
    }
  }

  Future<void> _processFundTransfer() async {
    final amount = double.tryParse(_transferAmountController.text);
    final description = _transferDescriptionController.text.trim();

    if (_selectedDriverId == null ||
        amount == null ||
        amount <= 0 ||
        description.isEmpty) {
      print(
        'DEBUG: Fund transfer validation failed - driverId: $_selectedDriverId, amount: ${_transferAmountController.text}, description: ${_transferDescriptionController.text}',
      );
      if (mounted) {
        showAppToast(
          context,
          'Enter a valid amount and description for the transfer.',
          isError: true,
        );
      }
      return;
    }

    if (_driverLoadErrorMessage != null) {
      if (mounted) {
        showAppToast(
          context,
          'Driver list is unavailable. Please refresh and try again.',
          isError: true,
        );
      }
      return;
    }

    try {
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });

      final senderId = widget.user.driverId ?? widget.user.id;

      print(
        'DEBUG: Starting fund transfer - driverId: $_selectedDriverId, senderId: $senderId, amount: $amount, description: $description',
      );
      print(
        'DEBUG: Sender display name: "${widget.user.displayName}" (driverKey: ${widget.user.driverId ?? widget.user.id})',
      );

      // Call API to save fund transfer
      await _financeRepository.submitFundTransfer(
        driverId: _selectedDriverId!,
        senderId: senderId,
        amount: amount,
        description: description,
        senderName: widget.user.displayName,
      );

      // Clear form
      _clearTransferForm();

      // Reload data to get updated transactions and balance
      await _loadData();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fund transfer of ₹${amount.toStringAsFixed(0)} to $_selectedDriverName completed successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Fund transfer error: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process fund transfer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Hide loading indicator
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDriversList() async {
    try {
      print('Loading drivers from API...');
      final response = await http.get(
        Uri.parse('https://sstranswaysindia.com/api/mobile/get_drivers.php'),
        headers: {'Content-Type': 'application/json'},
      );

      print('Driver API response status: ${response.statusCode}');
      print('Driver API response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok') {
          final driversData = data['drivers'] as List<dynamic>;
          print('DEBUG: Found ${driversData.length} drivers from API');
          for (var driver in driversData) {
            print('DEBUG: - ${driver['name']} (ID: ${driver['id']})');
          }
          if (!mounted) return;
          setState(() {
            _driverLoadErrorMessage = null;
            _driversList = driversData.cast<Map<String, dynamic>>();
            _filteredDriversList = List.from(_driversList);
            _driverNameCache
              ..clear()
              ..addEntries(
                _driversList.map(
                  (driver) => MapEntry(
                    driver['id'].toString(),
                    driver['name'].toString(),
                  ),
                ),
              );
            _ensureCurrentUserCached();
          });
        } else {
          print('DEBUG: API returned error: ${data['error']}');
          _handleDriverLoadFailure(data['error']?.toString());
        }
      } else {
        print('API request failed with status: ${response.statusCode}');
        _handleDriverLoadFailure(
          'Request failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error loading drivers: $e');
      _handleDriverLoadFailure(e.toString());
    }

    print('DEBUG: Drivers loaded at page start, total: ${_driversList.length}');
  }

  Future<void> _loadTransactionDescriptions() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isDescriptionLoading = true;
      _descriptionLoadError = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_transaction_descriptions.php',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok') {
          final descriptionsRaw =
              data['descriptions'] as List<dynamic>? ?? const [];
          final descriptions = descriptionsRaw
              .map((item) {
                if (item is Map<String, dynamic>) {
                  final label = item['label']?.toString().trim() ?? '';
                  if (label.isEmpty) {
                    return null;
                  }
                  final rawFlag = item['vehicleMandatory'];
                  final mandatory =
                      rawFlag == true ||
                      (rawFlag is String &&
                          rawFlag.trim().toLowerCase() == 'y');
                  final rawDriver = item['driverMandatory'];
                  final driverMandatory =
                      rawDriver == true ||
                      (rawDriver is String &&
                          rawDriver.trim().toLowerCase() == 'y');
                  return _DescriptionOption(
                    label: label,
                    vehicleMandatory: mandatory,
                    driverMandatory: driverMandatory,
                  );
                }
                final label = item.toString().trim();
                if (label.isEmpty) {
                  return null;
                }
                return _DescriptionOption(label: label);
              })
              .whereType<_DescriptionOption>()
              .toList(growable: false);

          // Apply client-side category rules:
          // - Force driver mandatory for incentive-like categories and the listed expense categories.
          // - Hide categories containing "safety" or "advance office".
          const _forceDriverKeywords = <String>[
            'incentive',
            'shoes',
            'salary',
            'training',
            'travel',
            'travel and uniform',
            'uniform',
            'driver name',
          ];
          const _hideKeywords = <String>[
            'safety',
            'advance office',
            // Hide both "DRIVETRACK" and variants like "DRIVE TRACK" / "DRIVE_TRACK".
            'drivetrack',
            'drive track',
            'drive_track',
          ];

          String _normalizeKey(String input) =>
              input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

          final _hideNormalized = _hideKeywords
              .map(_normalizeKey)
              .toList(growable: false);

          List<_DescriptionOption> normalized = descriptions
              .where((opt) {
                final rawLower = opt.label.toLowerCase();
                final compact = _normalizeKey(opt.label);
                // Keep legacy contains check + robust normalized check.
                final legacyHit = _hideKeywords.any(
                  (h) => rawLower.contains(h),
                );
                final normalizedHit = _hideNormalized.any(
                  (h) => h.isNotEmpty && compact.contains(h),
                );
                return !(legacyHit || normalizedHit);
              })
              .map((opt) {
                final lower = opt.label.toLowerCase();
                final forceDriver = _forceDriverKeywords.any(
                  (k) => lower.contains(k),
                );
                if (forceDriver && !opt.driverMandatory) {
                  return _DescriptionOption(
                    label: opt.label,
                    vehicleMandatory: opt.vehicleMandatory,
                    driverMandatory: true,
                  );
                }
                return opt;
              })
              .toList(growable: true);

          // Ensure stable alphabetical ordering in UI (case-insensitive).
          normalized.sort((a, b) {
            final la = a.label.toLowerCase();
            final lb = b.label.toLowerCase();
            final cmp = la.compareTo(lb);
            if (cmp != 0) return cmp;
            return a.label.compareTo(b.label);
          });
          normalized = normalized.toList(growable: false);

          if (!mounted) return;
          setState(() {
            _descriptionOptions = normalized;
          });
        } else {
          final errorMessage =
              data['error']?.toString() ?? 'Unable to load descriptions';
          if (!mounted) return;
          setState(() {
            _descriptionLoadError = errorMessage;
            _descriptionOptions = const <_DescriptionOption>[];
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _descriptionLoadError =
              'Request failed with status ${response.statusCode}';
          _descriptionOptions = const <_DescriptionOption>[];
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _descriptionLoadError = 'Failed to load descriptions: $error';
        _descriptionOptions = const <_DescriptionOption>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDescriptionLoading = false;
        });
      }
    }
  }

  Future<void> _loadVehiclesForKhata() async {
    final isSupervisor = widget.user.role == UserRole.supervisor;

    setState(() {
      _isVehicleListLoading = true;
      _vehicleLoadError = null;
    });

    try {
      final repository = TripRepository();
      if (isSupervisor) {
        // For supervisor role, show ALL vehicles across all plants.
        // 1) Start with cached vehicles from login (if any).
        final merged = <int, _VehicleOption>{
          for (final v in _buildVehicleOptionsFromAvailable(const <int>{}))
            v.id: v,
        };

        // 2) Fetch global list from backend (plantId=0, empty q) and merge.
        try {
          final response = await http.post(
            Uri.parse(
              'https://sstranswaysindia.com/TripDetails/api/mobile/vehicles.php',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'role': 'supervisor',
              'userId': int.tryParse(widget.user.id),
              'driverId': int.tryParse(widget.user.driverId ?? ''),
              'plantId': 0,
              // Use global search mode to get cross-plant vehicles even if the server
              // doesn't yet support plantId=0 listing without a query.
              // '%' matches everything and the API is capped (currently 200).
              'q': '%',
            }),
          );
          if (response.statusCode < 300) {
            final data =
                jsonDecode(response.body) as Map<String, dynamic>? ??
                const <String, dynamic>{};
            final status = (data['status'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (status == 'ok') {
              final rows = data['vehicles'] as List<dynamic>? ?? const [];
              for (final row in rows) {
                if (row is! Map<String, dynamic>) continue;
                final id = int.tryParse(row['id']?.toString() ?? '') ?? 0;
                final number =
                    (row['vehicle_no'] ??
                            row['number'] ??
                            row['vehicleNumber'] ??
                            '')
                        .toString()
                        .trim();
                if (id <= 0 || number.isEmpty) continue;
                final plantId =
                    int.tryParse(row['plant_id']?.toString() ?? '') ?? 0;
                final plantName = (row['plant_name'] ?? row['plantName'] ?? '')
                    .toString()
                    .trim();
                merged[id] = _VehicleOption(
                  id: id,
                  number: number,
                  plantId: plantId > 0 ? plantId : null,
                  plantName: plantName,
                );
              }
            }
          }
        } catch (_) {
          // Ignore; keep cached vehicles.
        }

        if (!mounted) return;
        setState(() {
          _vehicleOptions = merged.values.toList(growable: false);
          _vehicleLoadError = _vehicleOptions.isEmpty
              ? 'No vehicles found.'
              : null;
        });
      } else {
        final plantId = _inferPlantId();
        if (plantId == null) {
          if (!mounted) return;
          setState(() {
            _vehicleOptions = const [];
            _vehicleLoadError = 'No plant assigned';
          });
          return;
        }
        final vehicles = await repository.fetchVehiclesForPlant(
          user: widget.user,
          plantId: plantId.toString(),
        );

        if (!mounted) return;

        setState(() {
          _vehicleOptions = vehicles
              .map(
                (v) => _VehicleOption(
                  id: v.id,
                  number: v.number,
                  plantName: _plantNameForId(plantId),
                ),
              )
              .toList(growable: false);
          _vehicleLoadError = _vehicleOptions.isEmpty
              ? 'No vehicles mapped to this plant.'
              : null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _vehicleOptions = const [];
        _vehicleLoadError = 'Unable to load vehicles: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isVehicleListLoading = false);
      }
    }
  }

  void _filterDrivers(String searchText) {
    // Real-time filtering
    if (searchText.isEmpty) {
      _filteredDriversList = List.from(_driversList);
      _showDriverList = false;
    } else {
      // Instant filtering
      final searchLower = searchText.toLowerCase();
      _filteredDriversList = _driversList
          .where(
            (driver) =>
                driver['name'].toString().toLowerCase().contains(searchLower),
          )
          .toList();
      _showDriverList = true;
    }

    // Immediate setState for real-time results
    if (!mounted) return;
    setState(() {});
  }

  void _selectDriver(
    Map<String, dynamic> driver, {
    StateSetter? dialogSetState,
  }) {
    print('DEBUG: Driver selected: ${driver['name']}');
    _selectedDriverId = driver['id'].toString();
    _selectedDriverName = driver['name'];
    _driverSearchController.text = driver['name'];
    _showDriverList = false;
    dialogSetState?.call(() {});
    if (!mounted) return;
    setState(() {});
  }

  void _handleDriverLoadFailure([String? message]) {
    if (!mounted) {
      return;
    }
    final errorMessage = (message != null && message.trim().isNotEmpty)
        ? message.trim()
        : 'Unable to load drivers. Please try again later.';
    setState(() {
      _driverLoadErrorMessage = errorMessage;
      _driversList = [];
      _filteredDriversList = [];
      _driverNameCache.clear();
      _ensureCurrentUserCached();
    });
  }

  void _viewReceipt(String receiptPath) {
    final trimmedPath = receiptPath.trim();
    final imageUrl = trimmedPath.isEmpty
        ? null
        : trimmedPath.startsWith('http')
        ? trimmedPath
        : 'https://sstranswaysindia.com'
              '${trimmedPath.startsWith('/') ? trimmedPath : '/$trimmedPath'}';
    final isPdf =
        imageUrl != null &&
        imageUrl.toLowerCase().split('?').first.trim().endsWith('.pdf');

    showDialog(
      context: context,
      builder: (context) {
        int reloadKey = 0;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Receipt'),
              content: imageUrl == null
                  ? const Text('No receipt available for this entry.')
                  : isPdf
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('PDF receipt attached.'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri.tryParse(imageUrl);
                            if (uri == null) {
                              showAppToast(
                                context,
                                'Invalid PDF URL.',
                                isError: true,
                              );
                              return;
                            }
                            final ok = await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!ok && context.mounted) {
                              showAppToast(
                                context,
                                'Unable to open PDF.',
                                isError: true,
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open PDF'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 320,
                          child: InteractiveViewer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                imageUrl,
                                key: ValueKey('receipt_$reloadKey'),
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                    child: AppLoader(size: 20),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) =>
                                    Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.broken_image,
                                            size: 48,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Unable to load receipt image.',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              setDialogState(() {
                                                reloadKey++;
                                              });
                                            },
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Reload'),
                                          ),
                                        ],
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MonthYearSelection {
  const _MonthYearSelection({required this.month, required this.year});

  final String month;
  final int? year;
}
