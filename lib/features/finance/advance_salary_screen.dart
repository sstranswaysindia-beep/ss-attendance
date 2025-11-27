import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../../core/models/advance_transaction.dart';
import '../../core/models/app_user.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/models/trip_vehicle.dart';
import '../../core/services/trip_repository.dart';
import '../../core/widgets/profile_photo_widget.dart';
import '../../core/services/notification_service.dart';

class AdvanceSalaryScreen extends StatefulWidget {
  final AppUser user;

  const AdvanceSalaryScreen({super.key, required this.user});

  @override
  State<AdvanceSalaryScreen> createState() => _AdvanceSalaryScreenState();
}

class _DescriptionOption {
  const _DescriptionOption({
    required this.label,
    this.vehicleMandatory = false,
  });

  final String label;
  final bool vehicleMandatory;
}

class _VehicleOption {
  const _VehicleOption({required this.id, required this.number});

  final int id;
  final String number;
}

class _AdvanceSalaryScreenState extends State<AdvanceSalaryScreen> {
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
  String? _descriptionLoadError;
  List<_VehicleOption> _vehicleOptions = const [];
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
      final driverId = widget.user.driverId ?? widget.user.id;
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
      final driverId = widget.user.driverId ?? widget.user.id;
      print('DEBUG: Loading transactions for driverId: $driverId');
      print('DEBUG: User driverId: ${widget.user.driverId}');
      print('DEBUG: User id: ${widget.user.id}');
      print(
        'DEBUG: Request body: ${jsonEncode({'driverId': driverId, 'limit': 50})}',
      );

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId, 'limit': 50}),
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

  List<_VehicleOption> _buildVehicleOptionsFromAvailable(Set<int> allowedPlants) {
    final unique = <int, _VehicleOption>{};
    for (final driverVehicle in widget.user.availableVehicles) {
      final id = int.tryParse(driverVehicle.id) ?? 0;
      final number = driverVehicle.vehicleNumber.trim();
      if (id <= 0 || number.isEmpty) {
        continue;
      }
      final plantId = driverVehicle.plantId;
      if (allowedPlants.isNotEmpty && plantId != null && !allowedPlants.contains(plantId)) {
        continue;
      }
      unique[id] = _VehicleOption(id: id, number: number);
    }
    return unique.values.toList(growable: false);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _onMonthSelected(String month) {
    _applyMonthYear(month: month, year: _selectedYear);
  }

  void _applyMonthYear({required String month, int? year}) {
    setState(() {
      _selectedMonth = month;
      _selectedYear = year;
    });
    _filterTransactions();
  }

  void _filterTransactions() {
    final currentDriverId = widget.user.driverId ?? widget.user.id;

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

    setState(() {
      _filteredTransactions = filtered;
    });
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
    if (label == null || label.isEmpty) {
      return false;
    }
    for (final option in _descriptionOptions) {
      if (option.label == label) {
        return option.vehicleMandatory;
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
    DateTime transactionDate,
  ) async {
    try {
      final driverId = widget.user.driverId ?? widget.user.id;
      final requestBody = {
        'driverId': driverId,
        'type': type,
        'amount': amount,
        'description': description,
        'timestamp': transactionDate.toIso8601String(),
      };

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
              return pw.Center(
                child: pw.Image(pdfImage),
              );
            },
          ),
        );
      }

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/receipts_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error generating PDF: $e');
      return null;
    }
  }

  Future<ImageSource?> _showReceiptSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                'Attach receipt',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Capture photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery (Multiple)'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
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
    required ImageSource source,
    required StateSetter setSheetState,
    required ValueChanged<String> onPathSelected,
  }) async {
    setSheetState(() {
      _isUploadingPhoto = true;
    });

    try {
      if (source == ImageSource.camera) {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          setSheetState(() {
            onPathSelected(image.path);
          });
        }
      } else {
        final images = await _pickGalleryReceipts();
        if (images.isEmpty) return;

        if (images.length == 1) {
          setSheetState(() {
            onPathSelected(images.first.path);
          });
        } else {
          final pdfPath = await _generatePdfFromImages(images);
          if (pdfPath != null) {
            setSheetState(() {
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
      showAppToast(
        context,
        'Error selecting image: $error',
        isError: true,
      );
    } finally {
      setSheetState(() {
        _isUploadingPhoto = false;
      });
    }
  }

  void _showAddTransactionDialog(bool isAdvanceReceived) {
    print('DEBUG: _showAddTransactionDialog called. isAdvanceReceived: $isAdvanceReceived');
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
    DateTime selectedDate = DateTime.now();
    String? selectedReceiptPath;
    String? selectedDescriptionLabel = _descriptionOptions.isNotEmpty
        ? _descriptionOptions.first.label
        : null;
    int? selectedVehicleId;
    String? selectedVehicleNumber;

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
              final ImageSource? source = await _showReceiptSourceSheet();
              if (source == null) return;
              await _handleReceiptSelection(
                source: source,
                setSheetState: setSheetState,
                onPathSelected: (path) {
                  selectedReceiptPath = path;
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

            final bool vehicleFieldNeeded = !isAdvanceReceived &&
                _isVehicleMandatory(selectedDescriptionLabel);
            final bool requiresVehicleSelection =
                vehicleFieldNeeded && widget.user.role != UserRole.supervisor;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
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
                              borderSide: BorderSide(color: Colors.blue, width: 2),
                            ),
                            suffixIcon: const Icon(Icons.arrow_drop_down),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onTap: _descriptionOptions.isEmpty
                              ? null
                              : () async {
                                  final selected = await showSelectionDialog<_DescriptionOption>(
                                    title: 'Select Description',
                                    items: _descriptionOptions,
                                    labelBuilder: (option) => option.label,
                                  );
                                  if (selected != null) {
                                    setSheetState(() {
                                      selectedDescriptionLabel = selected.label;
                                      // Reset vehicle selection when description changes
                                      selectedVehicleId = null;
                                      selectedVehicleNumber = null;
                                    });
                                  }
                                },
                        ),
                        if (vehicleFieldNeeded) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            readOnly: true,
                            controller: TextEditingController(text: selectedVehicleNumber),
                            decoration: InputDecoration(
                              labelText: 'Vehicle Number${requiresVehicleSelection ? ' *' : ''}',
                              border: const OutlineInputBorder(),
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.grey),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue, width: 2),
                              ),
                              helperText: requiresVehicleSelection
                                  ? 'Vehicle number is required for this description.'
                                  : (_vehicleOptions.isEmpty
                                      ? 'No vehicles available for your plant.'
                                      : null),
                              helperMaxLines: 2,
                              errorText: _vehicleLoadError,
                              suffixIcon: const Icon(Icons.arrow_drop_down),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onTap: _vehicleOptions.isEmpty
                                ? null
                                : () async {
                                    final selected = await showSelectionDialog<_VehicleOption>(
                                      title: 'Select Vehicle',
                                      items: _vehicleOptions,
                                      labelBuilder: (vehicle) => vehicle.number,
                                    );
                                    if (selected != null) {
                                      setSheetState(() {
                                        selectedVehicleId = selected.id;
                                        selectedVehicleNumber = selected.number;
                                      });
                                    }
                                  },
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: extraNotesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Additional description (optional)',
                            hintText: 'Add more details for this entry',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                                    if (selectedReceiptPath != null)
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: Colors.green.withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                selectedReceiptPath?.endsWith('.pdf') == true
                                                    ? Icons.picture_as_pdf
                                                    : Icons.receipt,
                                                size: 16,
                                                color: Colors.green,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                selectedReceiptPath?.endsWith('.pdf') == true
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
                                    if (selectedReceiptPath != null)
                                      const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: _isUploadingPhoto ? null : pickReceipt,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _isUploadingPhoto
                                              ? Colors.grey.withOpacity(0.3)
                                              : Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: _isUploadingPhoto
                                                ? Colors.grey.withOpacity(0.3)
                                                : Colors.blue.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_isUploadingPhoto)
                                              const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            else
                                              Icon(
                                                selectedReceiptPath != null
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
                                                  : (selectedReceiptPath != null
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
                                onPressed: () => Navigator.of(sheetContext).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  final amount =
                                      double.tryParse(amountController.text);
                                  if (amount == null || amount <= 0) {
                                    showAppToast(
                                      context,
                                      'Please enter a valid amount',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  final baseDescription =
                                      selectedDescriptionLabel?.trim() ?? '';
                                  final extraNotes =
                                      extraNotesController.text.trim();
                                  final combinedDescription = () {
                                    if (baseDescription.isEmpty &&
                                        extraNotes.isEmpty) {
                                      return '';
                                    }
                                    if (baseDescription.isEmpty) {
                                      return extraNotes;
                                    }
                                    if (extraNotes.isEmpty) {
                                      return baseDescription;
                                    }
                                    return '$baseDescription — $extraNotes';
                                  }();
                                  if (combinedDescription.isEmpty) {
                                    showAppToast(
                                      context,
                                      'Please provide a description',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  if (requiresVehicleSelection &&
                                      (selectedVehicleNumber == null ||
                                          selectedVehicleNumber!.isEmpty)) {
                                    showAppToast(
                                      context,
                                      'Vehicle number is required for this description.',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  var finalDescription = combinedDescription;
                                  if (!isAdvanceReceived &&
                                      (selectedVehicleNumber?.isNotEmpty ?? false)) {
                                    finalDescription = finalDescription.isEmpty
                                        ? 'Vehicle: $selectedVehicleNumber'
                                        : '$finalDescription (Vehicle: $selectedVehicleNumber)';
                                  }
                                  Navigator.of(sheetContext).pop();
                                  final type = isAdvanceReceived
                                      ? 'advance_received'
                                      : 'expense';
                                  print('🔵 CREATING TRANSACTION');
                                  print('🔵 Type: $type');
                                  print('🔵 Amount: $amount');
                                  print('🔵 Description: $finalDescription');
                                  print('🔵 Selected Receipt Path: $selectedReceiptPath');
                                  final transactionId = await _addTransactionWithDate(
                                    type,
                                    amount,
                                    finalDescription,
                                    selectedDate,
                                  );
                                  print('🔵 Transaction ID returned: $transactionId');
                                  if (!isAdvanceReceived &&
                                      selectedReceiptPath != null &&
                                      transactionId != null) {
                                    try {
                                      print('🔵 RECEIPT UPLOAD START');
                                      print('🔵 Transaction ID: $transactionId');
                                      print(
                                        '🔵 Driver ID: ${widget.user.driverId ?? widget.user.id}',
                                      );
                                      print('🔵 File path: $selectedReceiptPath');
                                      final file = File(selectedReceiptPath!);
                                      final fileExists = await file.exists();
                                      print('🔵 File exists: $fileExists');
                                      if (fileExists) {
                                        final fileSize = await file.length();
                                        print('🔵 File size: $fileSize bytes');
                                      }
                                      final response =
                                          await _financeRepository.uploadReceipt(
                                        transactionId: transactionId,
                                        driverId: widget.user.driverId ?? widget.user.id,
                                        filePath: selectedReceiptPath!,
                                      );
                                      print('🟢 Upload response: $response');
                                      if (response['status'] == 'ok') {
                                        showAppToast(
                                          context,
                                          'Receipt uploaded successfully',
                                        );
                                        print('🟢 Receipt upload SUCCESS');
                                        if (mounted) {
                                          await _loadData();
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
                                      print('🔴 Upload exception: $error');
                                      print('🔴 Exception type: ${error.runtimeType}');
                                      showAppToast(
                                        context,
                                        'Error uploading receipt: $error',
                                        isError: true,
                                      );
                                    }
                                    print('🔵 Receipt upload process completed');
                                  } else {
                                    print('🔵 Receipt upload SKIPPED');
                                    print('🔵 isAdvanceReceived: $isAdvanceReceived');
                                    print('🔵 selectedReceiptPath: $selectedReceiptPath');
                                    print('🔵 transactionId: $transactionId');
                                  }
                                },
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
    });
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khata Book'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMonth,
                dropdownColor: Colors.white,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                ),
                onChanged: (value) {
                  if (value != null) {
                    _onMonthSelected(value);
                  }
                },
                selectedItemBuilder: (context) {
                  return _monthOptions
                      .map(
                        (month) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            month == _selectedMonth
                                ? _currentFilterLabel()
                                : month,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList();
                },
                items: _monthOptions
                    .map(
                      (month) => DropdownMenuItem<String>(
                        value: month,
                        child: Text(
                          month,
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
              const Text(
                'View settings',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
              const Text(
                'You will get',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              TextButton.icon(
                onPressed: _showFundTransferDialog,
                style: TextButton.styleFrom(foregroundColor: Colors.blue),
                icon: const Icon(Icons.sync_alt, size: 18),
                label: const Text('Fund Transfer'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₹${_currentBalance.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showMonthSelector,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                ),
                icon: const Icon(Icons.calendar_today, size: 16),
                label: const Text('SET MONTH'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ENTRIES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const Row(
              children: [
                Text(
                  'YOU GAVE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                SizedBox(width: 20),
                Text(
                  'YOU GOT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (_selectedMonth != 'All Months' || _selectedYear != null)
              Text(
                _currentFilterLabel(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue,
                ),
              ),
          ],
        ),
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
        ],
      ),
    );
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
    var description = transaction.description.trim();
    description = _replaceDriverIdPlaceholders(description);
    return description;
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
    if (driverKey == null || driverKey.toString().isEmpty) {
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
            Text('Description:\n${transaction.description}'),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                                'ID: ${driver['id']}',
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
                  Text('Description: ${transaction.description}'),
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
        builder: (context) => const Center(child: CircularProgressIndicator()),
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
                  return _DescriptionOption(
                    label: label,
                    vehicleMandatory: mandatory,
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
          if (!mounted) return;
          setState(() {
            _descriptionOptions = descriptions;
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
    final supervisorPlantIds = isSupervisor ? _parseSupervisorPlantIds() : <int>{};

    setState(() {
      _isVehicleListLoading = true;
      _vehicleLoadError = null;
    });

    try {
      final repository = TripRepository();
      if (isSupervisor) {
        final cachedOptions = _buildVehicleOptionsFromAvailable(supervisorPlantIds);
        if (cachedOptions.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _vehicleOptions = cachedOptions;
            _vehicleLoadError = null;
            _isVehicleListLoading = false;
          });
          return;
        }

        final inferredPlantId = _inferPlantId();
        final targetPlantIds = supervisorPlantIds.isNotEmpty
            ? supervisorPlantIds
            : {
                if (inferredPlantId != null) inferredPlantId,
              };

        if (targetPlantIds.isEmpty) {
          if (!mounted) return;
          setState(() {
            _vehicleOptions = const [];
            _vehicleLoadError = 'No supervised plants assigned.';
            _isVehicleListLoading = false;
          });
          return;
        }

        final merged = <int, _VehicleOption>{};
        for (final plantId in targetPlantIds) {
          final vehicles = await repository.fetchVehiclesForPlant(
            user: widget.user,
            plantId: plantId.toString(),
          );
          for (final vehicle in vehicles) {
            if (vehicle.id > 0 && vehicle.number.isNotEmpty) {
              merged[vehicle.id] = _VehicleOption(
                id: vehicle.id,
                number: vehicle.number,
              );
            }
          }
        }

        if (!mounted) return;
        setState(() {
          _vehicleOptions = merged.values.toList(growable: false);
          _vehicleLoadError = _vehicleOptions.isEmpty
              ? 'No vehicles mapped to your supervised plants.'
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
              .map((v) => _VehicleOption(id: v.id, number: v.number))
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt'),
        content: imageUrl == null
            ? const Text('No receipt available for this entry.')
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
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'Unable to load receipt image.',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    imageUrl,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _MonthYearSelection {
  const _MonthYearSelection({required this.month, required this.year});

  final String month;
  final int? year;
}
