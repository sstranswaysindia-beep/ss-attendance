import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_user.dart';
import '../../core/models/trip_driver.dart';
import '../../core/models/trip_helper.dart';
import '../../core/models/trip_plant.dart';
import '../../core/models/trip_record.dart';
import '../../core/models/trip_summary.dart';
import '../../core/models/trip_vehicle.dart';
import '../../core/services/gps_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/trip_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/glowing_badge.dart';

class TripScreen extends StatefulWidget {
  const TripScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final TripRepository _repository = TripRepository();
  final GpsService _gpsService = GpsService();
  final LocalStorageService _localStorage = LocalStorageService();
  final FocusNode _driverFocusNode = FocusNode();
  final FocusNode _helperFocusNode = FocusNode();
  Timer? _autoSaveTimer;

  TripOverviewResponse? _overview;
  bool _isLoading = false;
  String? _error;

  bool _isLoadingPlants = false;
  bool _isLoadingVehicles = false;
  bool _isLoadingMeta = false;
  bool _isLoadingHelpers = false;
  bool _isCreatingTrip = false;
  List<TripPlant> _plants = const <TripPlant>[];
  TripPlant? _selectedPlant;
  List<TripVehicle> _vehicles = const <TripVehicle>[];
  TripVehicle? _selectedVehicle;
  List<TripDriver> _allDrivers = const <TripDriver>[];
  List<TripDriver> _filteredDrivers = const <TripDriver>[];
  List<TripDriver> _selectedDrivers = const <TripDriver>[];
  List<TripHelper> _metaHelpers = const <TripHelper>[];
  List<TripHelper> _helpersForPlant = const <TripHelper>[];
  List<TripHelper> _selectedHelpers = const <TripHelper>[];
  List<String> _globalCustomerSuggestions = const <String>[];
  List<String> _customerSuggestions = const <String>[];
  List<String> _customerNames = const <String>[];
  late final TextEditingController _startDateController;
  final TextEditingController _startKmController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _customerController = TextEditingController();
  DateTime _selectedStartDate = DateTime.now();

  // Ongoing trip variables
  bool _hasOngoingTrip = false;
  TripRecord? _ongoingTrip;
  bool _isCheckingOngoingTrip = false;

  final GlobalKey<FormFieldState<int?>> _driverDropdownKey =
      GlobalKey<FormFieldState<int?>>();
  final GlobalKey<FormFieldState<int?>> _helperDropdownKey =
      GlobalKey<FormFieldState<int?>>();

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String _status = 'All';
  String? _selectedPlantId;
  int? _lastSuggestedStartKm;
  String? _savedVehicleId;

  @override
  void initState() {
    super.initState();

    _selectedPlantId =
        widget.user.plantId ??
        widget.user.assignmentPlantId ??
        widget.user.defaultPlantId;
    _selectedStartDate = DateTime.now();
    _startDateController = TextEditingController(
      text: _formatDate(_selectedStartDate),
    );
    _startKmController.addListener(_handleStartKmChanged);

    // Debug user assignment data
    print('User assignment data:');
    print('  driverId: ${widget.user.driverId}');
    print('  assignmentVehicleId: ${widget.user.assignmentVehicleId}');
    print('  assignmentPlantId: ${widget.user.assignmentPlantId}');
    print('  plantId: ${widget.user.plantId}');
    print('  selectedPlantId: $_selectedPlantId');

    _loadMeta();
    _loadTrips();
    _loadPlants();
    _findOngoingTrip();
    _restoreSavedSelections();
    _startAutoSave();
  }

  @override
  void dispose() {
    _startKmController.removeListener(_handleStartKmChanged);
    _startDateController.dispose();
    _startKmController.dispose();
    _noteController.dispose();
    _customerController.dispose();
    _driverFocusNode.dispose();
    _helperFocusNode.dispose();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _repository.fetchOverview(
        from: _from,
        to: _to,
        status: _status,
        plantId: _selectedPlantId,
        vehicleId: _selectedVehicle?.id.toString(),
      );
      if (!mounted) return;
      setState(() => _overview = response);
    } on TripFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load trips.';
      setState(() => _error = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // Check for ongoing trip after loading trips
        _findOngoingTrip();
      }
    }
  }

  Future<void> _handleDeleteTrip(TripRecord trip) async {
    // Show confirmation dialog for delete trip
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: Text(
          'Are you sure you want to delete trip #${trip.id}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteTrip(trip.id);
      showAppToast(context, 'Trip deleted successfully');

      // Refresh the data
      await _loadTrips();
      _findOngoingTrip();
    } catch (e) {
      showAppToast(context, 'Failed to delete trip: $e', isError: true);
    }
  }

  void _handleStartKmChanged() {
    if (_lastSuggestedStartKm == null) {
      return;
    }
    final text = _startKmController.text.trim();
    if (text != _lastSuggestedStartKm.toString()) {
      _lastSuggestedStartKm = null;
    }
  }

  List<String> _buildCustomerSuggestions(
    TripVehicle? vehicle, {
    int limit = 12,
  }) {
    final seen = <String>{};
    final results = <String>[];

    void addName(String? raw) {
      if (raw == null) {
        return;
      }
      final name = raw.trim();
      if (name.isEmpty) {
        return;
      }
      final key = name.toLowerCase();
      if (seen.add(key)) {
        results.add(name);
      }
    }

    if (vehicle != null) {
      for (final name in vehicle.recentCustomers) {
        addName(name);
      }
    }

    for (final name in _globalCustomerSuggestions) {
      addName(name);
    }

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  List<String> _mergeRecentCustomerNames(
    List<String> existing,
    Iterable<String> additions, {
    int limit = 5,
  }) {
    final seen = <String>{};
    final results = <String>[];

    void add(String? raw) {
      if (raw == null) {
        return;
      }
      final name = raw.trim();
      if (name.isEmpty) {
        return;
      }
      final key = name.toLowerCase();
      if (seen.add(key)) {
        results.add(name);
      }
    }

    for (final name in additions) {
      add(name);
    }
    for (final name in existing) {
      add(name);
    }

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  List<String> _mergeGlobalCustomerNames(
    List<String> existing,
    Iterable<String> additions, {
    int limit = 30,
  }) {
    final merged = _mergeRecentCustomerNames(existing, additions, limit: limit);
    return merged;
  }

  void _applyVehicleSelection(TripVehicle? vehicle) {
    final mergedSuggestions = _buildCustomerSuggestions(vehicle);

    if (mounted) {
      setState(() {
        _selectedVehicle = vehicle;
        _customerSuggestions = mergedSuggestions;
      });
    }

    // Save vehicle selection to local storage
    if (vehicle != null) {
      _localStorage.saveVehicleId(vehicle.id.toString());
    }

    // Set suggested start KM from vehicle's last end KM
    if (vehicle != null) {
      _setSuggestedStartKm(vehicle);
    }

    // Auto-add assigned driver for the selected vehicle
    _autoAddAssignedDriver(vehicle);

    // Check if the selected vehicle has an ongoing trip
    _checkVehicleOngoingTrip(vehicle);
  }

  void _autoAddAssignedDriver(TripVehicle? vehicle) {
    if (vehicle == null) return;

    // Check if current user is assigned to this vehicle
    final currentDriverId = int.tryParse(widget.user.driverId ?? '');
    if (currentDriverId == null || currentDriverId <= 0) return;

    // Check if user's assigned vehicle matches the selected vehicle
    final assignedVehicleId = int.tryParse(
      widget.user.assignmentVehicleId ?? '',
    );
    if (assignedVehicleId == null || assignedVehicleId != vehicle.id) return;

    print(
      'Auto-adding assigned driver: $currentDriverId for vehicle: ${vehicle.id}',
    );

    // Check if driver is already selected
    final alreadySelected = _selectedDrivers.any(
      (driver) => driver.id == currentDriverId,
    );
    if (alreadySelected) {
      print('Driver already selected, skipping');
      return;
    }

    // Find the driver in the available drivers list
    TripDriver? driverMatch;
    for (final driver in _allDrivers) {
      if (driver.id == currentDriverId) {
        driverMatch = driver;
        break;
      }
    }

    // If not found in drivers list, create a new TripDriver
    driverMatch ??= TripDriver(
      id: currentDriverId,
      name: widget.user.displayName,
      plantId: int.tryParse(
        widget.user.plantId ?? widget.user.assignmentPlantId ?? '',
      ),
    );

    print('Adding driver: ${driverMatch.name} (ID: ${driverMatch.id})');

    // Add the driver to selected drivers
    if (mounted) {
      setState(() {
        _selectedDrivers = <TripDriver>[..._selectedDrivers, driverMatch!];
      });
    }
  }

  void _checkVehicleOngoingTrip(TripVehicle? vehicle) {
    if (vehicle == null) {
      // No vehicle selected - clear form
      _clearFormForNewTrip();
      return;
    }

    // Find ongoing trip for this vehicle
    if (_overview == null) {
      _clearFormForNewTrip();
      return;
    }

    final ongoingTrip = _overview!.trips.firstWhere(
      (trip) =>
          trip.vehicleNumber == vehicle.number && trip.status == 'ongoing',
      orElse: () => TripRecord(
        id: 0,
        startDate: '',
        endDate: '',
        vehicleNumber: '',
        status: '',
      ),
    );

    if (ongoingTrip.id > 0) {
      // Vehicle has ongoing trip - load the trip data into form
      _loadOngoingTripDataIntoForm(ongoingTrip);
    } else {
      // No ongoing trip - clear form and set suggested KM
      _clearFormForNewTrip();
      _setSuggestedStartKm(vehicle);
    }
  }

  void _clearFormForNewTrip() {
    // Clear all form fields
    _startKmController.clear();
    _noteController.clear();
    _customerController.clear();
    _customerNames = const <String>[];
    _selectedHelpers = const <TripHelper>[];
    _selectedDrivers = const <TripDriver>[];

    // Reset start date to today
    _selectedStartDate = DateTime.now();
    _startDateController.text = _formatDate(_selectedStartDate);
  }

  void _setSuggestedStartKm(TripVehicle vehicle) {
    // First try to get from vehicle's lastEndKm
    var lastEndKm = vehicle.lastEndKm;

    // If not available, find from trip history
    if (lastEndKm == null && _overview != null) {
      final lastEndedTrip = _overview!.trips.firstWhere(
        (trip) =>
            trip.vehicleNumber == vehicle.number &&
            trip.status.toLowerCase() == 'ended' &&
            trip.endKm != null,
        orElse: () => TripRecord(
          id: 0,
          startDate: '',
          endDate: '',
          vehicleNumber: '',
          status: '',
        ),
      );

      if (lastEndedTrip.id > 0) {
        lastEndKm = lastEndedTrip.endKm?.toInt();
      }
    }

    final currentText = _startKmController.text.trim();
    final suggestedText = _lastSuggestedStartKm?.toString();
    final shouldReplace =
        currentText.isEmpty ||
        (suggestedText != null && currentText == suggestedText);

    if (lastEndKm != null) {
      final text = lastEndKm.toString();
      if (shouldReplace || currentText != text) {
        _startKmController
          ..text = text
          ..selection = TextSelection.collapsed(offset: text.length);
      }
      _lastSuggestedStartKm = lastEndKm;
    } else {
      if (shouldReplace && _startKmController.text.isNotEmpty) {
        _startKmController.clear();
      }
      _lastSuggestedStartKm = null;
    }
  }

  void _findOngoingTrip() {
    if ((widget.user.role != UserRole.driver &&
            widget.user.role != UserRole.supervisor) ||
        _isCheckingOngoingTrip)
      return;

    if (_overview == null) return;

    _isCheckingOngoingTrip = true;

    // Get the current user's name for comparison
    final currentUserName = widget.user.displayName;
    final driverId = int.tryParse(widget.user.driverId ?? '');

    final ongoingTrip = _overview!.trips.firstWhere(
      (trip) {
        final isOngoing = trip.status == 'ongoing';

        if (widget.user.role == UserRole.driver) {
          // For drivers, check if they are assigned to this trip
          final hasDriverId =
              driverId != null &&
              trip.drivers?.contains(driverId.toString()) == true;
          final hasDriverName = trip.drivers?.contains(currentUserName) == true;
          return isOngoing && (hasDriverId || hasDriverName);
        } else if (widget.user.role == UserRole.supervisor) {
          // For supervisors, show any ongoing trip
          return isOngoing;
        }

        return false;
      },
      orElse: () => TripRecord(
        id: 0,
        status: '',
        startDate: '',
        endDate: '',
        vehicleNumber: '',
        plantId: 0,
        note: '',
        drivers: '',
        helper: '',
        customers: '',
      ),
    );

    if (ongoingTrip.id > 0) {
      setState(() {
        _hasOngoingTrip = true;
        _ongoingTrip = ongoingTrip;
      });

      // Load ongoing trip data into form
      _loadOngoingTripDataIntoForm(ongoingTrip);
    } else {
      setState(() {
        _hasOngoingTrip = false;
        _ongoingTrip = null;
      });

      // Check if selected vehicle has ongoing trip and load/clear form accordingly
      _checkVehicleOngoingTrip(_selectedVehicle);
    }

    _isCheckingOngoingTrip = false;
  }

  void _loadOngoingTripDataIntoForm(TripRecord trip) {
    // Load start KM
    if (trip.startKm != null) {
      _startKmController.text = trip.startKm.toString();
    }

    // Load start date
    if (trip.startDate.isNotEmpty) {
      try {
        final date = DateTime.parse(trip.startDate);
        _selectedStartDate = date;
        _startDateController.text = _formatDate(date);
      } catch (e) {
        // If parsing fails, use today's date
        _selectedStartDate = DateTime.now();
        _startDateController.text = _formatDate(_selectedStartDate);
      }
    }

    // Load note
    if (trip.note != null && trip.note!.isNotEmpty) {
      _noteController.text = trip.note!;
    }

    // Load customers
    if (trip.customers != null && trip.customers!.isNotEmpty) {
      _customerNames = trip.customers!.split(',').map((c) => c.trim()).toList();
    }

    // Load helper
    if (trip.helper != null && trip.helper!.isNotEmpty) {
      // Find helper in the loaded helpers list
      final helper = _metaHelpers.firstWhere(
        (h) => h.name == trip.helper,
        orElse: () => TripHelper(id: 0, name: trip.helper!, plantId: 0),
      );
      if (helper.id > 0) {
        _selectedHelpers = [helper];
      }
    }

    // Load drivers
    if (trip.drivers != null && trip.drivers!.isNotEmpty) {
      final driverNames = trip.drivers!
          .split(',')
          .map((d) => d.trim())
          .toList();
      _selectedDrivers = driverNames.map((name) {
        return TripDriver(
          id: 0, // We don't have driver IDs from the trip record
          name: name,
          plantId: 0,
        );
      }).toList();
    }
  }

  Future<void> _handleUpdateTrip() async {
    if (_ongoingTrip == null) return;

    try {
      // Prepare update data from current form values
      final driverIds = _selectedDrivers.map((driver) => driver.id).toList();
      final helperIds = _selectedHelpers.map((helper) => helper.id).toList();
      final customerNames = _customerNames;
      final note = _noteController.text.trim();

      // Call the update API
      await _repository.updateTrip(
        user: widget.user,
        tripId: _ongoingTrip!.id,
        setDriverIds: driverIds,
        helperId: helperIds.isNotEmpty ? helperIds.first : null,
        setCustomerNames: customerNames,
        note: note.isNotEmpty ? note : null,
      );

      // Show success message
      showAppToast(context, 'Trip updated successfully');

      // Reload trips to reflect changes
      await _loadTrips();
    } on TripFailure catch (error) {
      showAppToast(context, error.message, isError: true);
    } catch (error) {
      showAppToast(context, 'Failed to update trip', isError: true);
    }
  }

  Future<void> _handleEndTrip() async {
    if (_ongoingTrip == null) return;

    // Show end trip modal
    await _showEndTripModal();
  }

  Future<void> _showEndTripModal() async {
    final endKmController = TextEditingController();
    final endDateController = TextEditingController(
      text: DateTime.now().toIso8601String().split('T')[0],
    );

    final startKm = _ongoingTrip!.startKm ?? 0;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Trip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: endDateController,
                decoration: const InputDecoration(
                  labelText: 'End Date',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 30),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (date != null) {
                    endDateController.text = date.toIso8601String().split(
                      'T',
                    )[0];
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: endKmController,
                decoration: InputDecoration(
                  labelText: 'End KM',
                  hintText: 'Enter end KM (must be > $startKm)',
                  suffixText: 'km',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(
                'Start KM: $startKm km',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final endKmText = endKmController.text.trim();
                final endKm = int.tryParse(endKmText);

                if (endKm == null || endKm <= startKm) {
                  showAppToast(
                    context,
                    'End KM must be greater than start KM ($startKm)',
                    isError: true,
                  );
                  return;
                }

                Navigator.of(context).pop();
                await _performEndTrip(endKm, endDateController.text);
              },
              child: const Text('End Trip'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performEndTrip(int endKm, String endDate) async {
    try {
      await _repository.endTrip(
        tripId: _ongoingTrip!.id,
        endDate: endDate,
        endKm: endKm,
      );
      showAppToast(context, 'Trip ended successfully');

      // Clear form and refresh data
      _startKmController.clear();
      _noteController.clear();
      _customerController.clear();
      _customerNames = const <String>[];
      _selectedHelpers = const <TripHelper>[];
      _selectedDrivers = const <TripDriver>[];

      // Clear plant and vehicle selections
      _selectedPlant = null;
      _selectedVehicle = null;

      // Reset start date to today
      _selectedStartDate = DateTime.now();
      _startDateController.text = _formatDate(_selectedStartDate);

      // Refresh the data
      await _loadTrips();
      _findOngoingTrip();
    } catch (e) {
      showAppToast(context, 'Failed to end trip: $e', isError: true);
    }
  }

  Future<void> _loadPlants() async {
    setState(() {
      _isLoadingPlants = true;
      _plants = const <TripPlant>[];
      _selectedPlant = null;
      _vehicles = const <TripVehicle>[];
      _selectedVehicle = null;
    });

    try {
      final plants = await _repository.fetchPlantsForUser(widget.user);
      TripPlant? initial;
      if (_selectedPlantId != null) {
        for (final plant in plants) {
          if (plant.id.toString() == _selectedPlantId) {
            initial = plant;
            break;
          }
        }
      }
      initial ??= plants.isNotEmpty ? plants.first : null;

      setState(() {
        _plants = plants;
        _selectedPlant = initial;
        _selectedPlantId = initial?.id.toString();
      });

      if (initial != null) {
        _filterDriversForPlant(initial.id.toString());
        _primeHelpersForPlant(initial.id.toString());
        await _loadVehicles(initial.id.toString());
      }
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to load plants.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingPlants = false);
      }
    }
  }

  Future<void> _loadMeta() async {
    setState(() {
      _isLoadingMeta = true;
    });

    try {
      final meta = await _repository.fetchMetaForUser(widget.user);
      if (!mounted) return;

      final drivers = meta.drivers
          .where((driver) => driver.id > 0 && driver.name.isNotEmpty)
          .toList(growable: false);
      final helpers = meta.helpers
          .where((helper) => helper.id > 0 && helper.name.isNotEmpty)
          .toList(growable: false);
      final customers = meta.customers
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList(growable: false);

      setState(() {
        _allDrivers = drivers;
        _metaHelpers = helpers;
        _globalCustomerSuggestions = customers;
        _customerSuggestions = _buildCustomerSuggestions(_selectedVehicle);
      });

      _ensureDefaultDriverSelected();
      _filterDriversForPlant(_selectedPlantId);
      _primeHelpersForPlant(_selectedPlantId);
      if (_selectedPlantId != null) {
        unawaited(
          _loadHelpers(
            _selectedPlantId!,
            vehicleId: _selectedVehicle?.id.toString(),
          ),
        );
      }
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        'Unable to load drivers and helpers.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMeta = false);
      }
    }
  }

  Future<void> _loadVehicles(String plantId) async {
    if (_startKmController.text.isNotEmpty) {
      _startKmController.clear();
    }
    setState(() {
      _isLoadingVehicles = true;
      _vehicles = const <TripVehicle>[];
      _selectedVehicle = null;
      _customerSuggestions = _buildCustomerSuggestions(null);
      _lastSuggestedStartKm = null;
    });

    try {
      final vehicles = await _repository.fetchVehiclesForPlant(
        user: widget.user,
        plantId: plantId,
      );
      if (!mounted) return;

      setState(() {
        _vehicles = vehicles;
      });

      // Try to get assigned vehicle for driver/supervisor
      TripVehicle? initialVehicle;

      // For drivers, try to get assigned vehicle
      if (widget.user.role == UserRole.driver) {
        // First try to use user's assignmentVehicleId directly
        final userAssignedVehicleId = int.tryParse(
          widget.user.assignmentVehicleId ?? '',
        );
        if (userAssignedVehicleId != null) {
          print('Using user assignmentVehicleId: $userAssignedVehicleId');
          for (final vehicle in vehicles) {
            if (vehicle.id == userAssignedVehicleId) {
              initialVehicle = vehicle;
              print(
                'Found assigned vehicle from user data: ${vehicle.number} (ID: ${vehicle.id})',
              );
              break;
            }
          }
        }

        // If not found in user data, try API
        if (initialVehicle == null) {
          try {
            final assignedVehicleId = await _repository.getAssignedVehicleId(
              user: widget.user,
              plantId: plantId,
            );

            print('Assigned vehicle ID from API: $assignedVehicleId');

            if (assignedVehicleId != null) {
              // Find the assigned vehicle in the list
              for (final vehicle in vehicles) {
                if (vehicle.id == assignedVehicleId) {
                  initialVehicle = vehicle;
                  print(
                    'Found assigned vehicle from API: ${vehicle.number} (ID: ${vehicle.id})',
                  );
                  break;
                }
              }
            }
          } catch (e) {
            print('Error getting assigned vehicle from API: $e');
          }
        }
      }

      // For supervisors or if no assigned vehicle found, use the first available vehicle
      if (initialVehicle == null && vehicles.isNotEmpty) {
        initialVehicle = vehicles.first;
        if (widget.user.role == UserRole.supervisor) {
          print('Supervisor: Auto-selecting first available vehicle: ${initialVehicle.number}');
        } else {
          print('No assigned vehicle found, using first available: ${initialVehicle.number}');
        }
      }

      // Restore saved vehicle if available
      if (_savedVehicleId != null) {
        try {
          final savedVehicle = vehicles.firstWhere(
            (v) => v.id.toString() == _savedVehicleId,
          );
          _applyVehicleSelection(savedVehicle);
          _savedVehicleId = null; // Clear after use
        } catch (e) {
          // If saved vehicle not found, use initial vehicle
          _applyVehicleSelection(initialVehicle);
          _savedVehicleId = null;
        }
      } else {
        _applyVehicleSelection(initialVehicle);
      }

      unawaited(
        _loadHelpers(plantId, vehicleId: _selectedVehicle?.id.toString()),
      );
      await _loadTrips();
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to load vehicles.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingVehicles = false);
      }
    }
  }

  void _ensureDefaultDriverSelected() {
    final driverId = int.tryParse(widget.user.driverId ?? '');
    if (driverId == null || driverId <= 0) {
      return;
    }

    final alreadySelected = _selectedDrivers.any(
      (driver) => driver.id == driverId,
    );
    if (alreadySelected) {
      return;
    }

    TripDriver? match;
    for (final driver in _allDrivers) {
      if (driver.id == driverId) {
        match = driver;
        break;
      }
    }

    match ??= TripDriver(
      id: driverId,
      name: widget.user.displayName,
      plantId: int.tryParse(
        widget.user.plantId ?? widget.user.assignmentPlantId ?? '',
      ),
    );

    setState(() {
      _selectedDrivers = <TripDriver>[..._selectedDrivers, match!];
    });
  }

  void _filterDriversForPlant(String? plantId) {
    if (plantId == null) {
      setState(() => _filteredDrivers = const <TripDriver>[]);
      return;
    }

    final targetPlantId = int.tryParse(plantId);
    final helperIds = _helpersForPlant.map((helper) => helper.id).toSet();
    final youId = int.tryParse(widget.user.driverId ?? '');

    final filtered =
        _allDrivers.where((driver) {
          if (targetPlantId != null &&
              driver.plantId != null &&
              driver.plantId != targetPlantId) {
            return false;
          }
          final role = driver.role?.toLowerCase();
          if (role == 'helper') {
            return false;
          }
          if (helperIds.contains(driver.id)) {
            return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    if (youId != null &&
        youId > 0 &&
        !filtered.any((driver) => driver.id == youId)) {
      final me = _allDrivers.firstWhere(
        (driver) => driver.id == youId,
        orElse: () => TripDriver(
          id: youId,
          name: widget.user.displayName,
          plantId: targetPlantId,
        ),
      );
      filtered.insert(0, me);
    }

    setState(() => _filteredDrivers = filtered);
  }

  void _primeHelpersForPlant(String? plantId) {
    if (plantId == null) {
      setState(() => _helpersForPlant = const <TripHelper>[]);
      return;
    }

    final targetPlantId = int.tryParse(plantId);
    if (targetPlantId == null) {
      setState(() => _helpersForPlant = const <TripHelper>[]);
      return;
    }

    final helpers = _metaHelpers
        .where(
          (helper) => helper.plantId == null || helper.plantId == targetPlantId,
        )
        .toList(growable: false);

    setState(() {
      _helpersForPlant = helpers;
      _selectedHelpers = _selectedHelpers
          .where(
            (helper) => helpers.any((candidate) => candidate.id == helper.id),
          )
          .toList(growable: false);
    });
  }

  Future<void> _loadHelpers(String plantId, {String? vehicleId}) async {
    setState(() {
      _isLoadingHelpers = true;
    });

    _primeHelpersForPlant(plantId);

    try {
      final helpers = await _repository.fetchHelpersForPlant(
        user: widget.user,
        plantId: plantId,
        vehicleId: vehicleId,
      );
      if (!mounted) return;
      setState(() {
        _helpersForPlant = helpers;
        _selectedHelpers = _selectedHelpers
            .where(
              (helper) => helpers.any((candidate) => candidate.id == helper.id),
            )
            .toList(growable: false);
      });
      _filterDriversForPlant(plantId);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to load helpers.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingHelpers = false);
      }
    }
  }

  void _handleDriverAdded(TripDriver driver) {
    if (_selectedDrivers.any((selected) => selected.id == driver.id)) {
      return;
    }
    setState(() {
      _selectedDrivers = <TripDriver>[..._selectedDrivers, driver];
    });
  }

  void _handleDriverRemoved(TripDriver driver) {
    final currentDriverId = int.tryParse(widget.user.driverId ?? '');
    if (currentDriverId != null && currentDriverId == driver.id) {
      return;
    }
    setState(() {
      _selectedDrivers = _selectedDrivers
          .where((selected) => selected.id != driver.id)
          .toList(growable: false);
    });
  }

  void _handleHelperAdded(TripHelper helper) {
    if (_selectedHelpers.any((selected) => selected.id == helper.id)) {
      return;
    }
    setState(() {
      _selectedHelpers = <TripHelper>[..._selectedHelpers, helper];
    });
  }

  void _handleHelperRemoved(TripHelper helper) {
    setState(() {
      _selectedHelpers = _selectedHelpers
          .where((selected) => selected.id != helper.id)
          .toList(growable: false);
    });
  }

  void _handleCustomerAdded(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) {
      return;
    }
    final exists = _customerNames.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      return;
    }
    setState(() {
      _customerNames = <String>[..._customerNames, name];
    });
  }

  void _handleCustomerRemoved(String name) {
    setState(() {
      _customerNames = _customerNames
          .where((existing) => existing.toLowerCase() != name.toLowerCase())
          .toList(growable: false);
    });
  }

  void _handleCustomerSubmitted() {
    final value = _customerController.text;
    _handleCustomerAdded(value);
    _customerController.clear();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedStartDate = picked;
      _startDateController.text = _formatDate(picked);
    });
  }

  Future<void> _handleCreateTrip() async {
    final vehicle = _selectedVehicle;
    if (vehicle == null) {
      showAppToast(context, 'Select a vehicle first.', isError: true);
      return;
    }

    final startKmText = _startKmController.text.replaceAll(',', '').trim();
    final startKm = int.tryParse(startKmText);
    if (startKm == null) {
      showAppToast(context, 'Enter a valid start KM.', isError: true);
      return;
    }

    final startDate = _startDateController.text.trim();
    if (startDate.isEmpty) {
      showAppToast(context, 'Select a trip start date.', isError: true);
      return;
    }

    if (_selectedDrivers.isEmpty) {
      showAppToast(context, 'Select at least one driver.', isError: true);
      return;
    }

    if (_customerNames.isEmpty) {
      showAppToast(context, 'Add at least one customer.', isError: true);
      return;
    }

    final newCustomers = List<String>.from(_customerNames);

    setState(() => _isCreatingTrip = true);

    try {
      // Get GPS coordinates
      final gpsLocation = await _gpsService.getLocationWithPrompt();

      await _repository.createTrip(
        vehicleId: vehicle.id,
        startDate: startDate,
        startKm: startKm,
        driverIds: _selectedDrivers
            .map((driver) => driver.id)
            .toList(growable: false),
        helperIds: _selectedHelpers
            .map((helper) => helper.id)
            .toList(growable: false),
        customerNames: _customerNames,
        note: _noteController.text.trim(),
        gpsLat: gpsLocation?['lat'],
        gpsLng: gpsLocation?['lng'],
      );

      showAppToast(context, 'Trip started successfully.');

      _customerController.clear();
      _noteController.clear();
      _startKmController.clear();

      setState(() {
        _customerNames = const <String>[];
        _selectedHelpers = const <TripHelper>[];
        if (newCustomers.isNotEmpty) {
          _globalCustomerSuggestions = _mergeGlobalCustomerNames(
            _globalCustomerSuggestions,
            newCustomers,
          );
        }

        final vehicleIndex = _vehicles.indexWhere(
          (item) => item.id == vehicle.id,
        );
        if (vehicleIndex != -1 && newCustomers.isNotEmpty) {
          final updatedVehicle = _vehicles[vehicleIndex].copyWith(
            recentCustomers: _mergeRecentCustomerNames(
              _vehicles[vehicleIndex].recentCustomers,
              newCustomers,
            ),
          );
          final updatedVehicles = [..._vehicles];
          updatedVehicles[vehicleIndex] = updatedVehicle;
          _vehicles = updatedVehicles;
          _selectedVehicle = updatedVehicle;
        }

        _customerSuggestions = _buildCustomerSuggestions(_selectedVehicle);
        _lastSuggestedStartKm = null;
      });

      _ensureDefaultDriverSelected();
      await _loadTrips();
      if (_selectedPlantId != null) {
        unawaited(
          _loadHelpers(
            _selectedPlantId!,
            vehicleId: _selectedVehicle?.id.toString(),
          ),
        );
      }
    } on TripFailure catch (error) {
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      showAppToast(context, 'Unable to start trip.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isCreatingTrip = false);
      }
    }
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final overview = _overview;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(title: const Text('Trips')),
        body: AppGradientBackground(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([_loadTrips(), _loadPlants(), _loadMeta()]);
              if (_selectedPlantId != null) {
                await _loadHelpers(
                  _selectedPlantId!,
                  vehicleId: _selectedVehicle?.id.toString(),
                );
              }
            },
            child: Stack(
              children: [
                // Main content with bottom padding for sticky card
                Positioned.fill(
                  child: ListView(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: _hasOngoingTrip && _ongoingTrip != null
                          ? 120
                          : 16,
                    ),
                    children: [
                      _PlantVehicleCard(
                        plants: _plants,
                        vehicles: _vehicles,
                        isLoadingPlants: _isLoadingPlants,
                        isLoadingVehicles: _isLoadingVehicles,
                        selectedPlant: _selectedPlant,
                        selectedVehicle: _selectedVehicle,
                        onPlantChanged: (widget.user.role == UserRole.driver)
                            ? (plant) {} // Empty function for drivers
                            : (plant) {
                                setState(() {
                                  _selectedPlant = plant;
                                  _selectedPlantId = plant.id.toString();
                                  _selectedVehicle = null;
                                });
                                // Save plant selection to local storage
                                _localStorage.savePlantId(plant.id.toString());
                                _filterDriversForPlant(plant.id.toString());
                                _primeHelpersForPlant(plant.id.toString());
                                _loadVehicles(plant.id.toString());
                              },
                        onVehicleChanged: (vehicle) {
                          _applyVehicleSelection(vehicle);
                          if (_selectedPlantId != null) {
                            unawaited(
                              _loadHelpers(
                                _selectedPlantId!,
                                vehicleId: _selectedVehicle?.id.toString(),
                              ),
                            );
                          }
                          _loadTrips();
                        },
                        onReloadPlants: _loadPlants,
                        hasOngoingTrip: _hasOngoingTrip,
                        user: widget.user,
                      ),
                      const SizedBox(height: 16),
                      _DriverHelperCard(
                        drivers: _filteredDrivers,
                        selectedDrivers: _selectedDrivers,
                        helpers: _helpersForPlant,
                        selectedHelpers: _selectedHelpers,
                        isLoadingDrivers: _isLoadingMeta,
                        isLoadingHelpers: _isLoadingHelpers,
                        currentDriverId: int.tryParse(
                          widget.user.driverId ?? '',
                        ),
                        driverFieldKey: _driverDropdownKey,
                        helperFieldKey: _helperDropdownKey,
                        driverFocusNode: _driverFocusNode,
                        helperFocusNode: _helperFocusNode,
                        onDriverAdded: (driver) => _handleDriverAdded(driver),
                        onDriverRemoved: (driver) =>
                            _handleDriverRemoved(driver),
                        onHelperAdded: (helper) => _handleHelperAdded(helper),
                        onHelperRemoved: (helper) =>
                            _handleHelperRemoved(helper),
                        onReloadHelpers: () {
                          if (_selectedPlantId != null) {
                            return _loadHelpers(
                              _selectedPlantId!,
                              vehicleId: _selectedVehicle?.id.toString(),
                            );
                          }
                          return Future<void>.value();
                        },
                      ),
                      const SizedBox(height: 16),
                      _TripStartCard(
                        startDateController: _startDateController,
                        onPickStartDate: _pickStartDate,
                        startKmController: _startKmController,
                        noteController: _noteController,
                        customerController: _customerController,
                        customerSuggestions: _customerSuggestions,
                        selectedCustomers: _customerNames,
                        onCustomerAdded: _handleCustomerAdded,
                        onCustomerRemoved: _handleCustomerRemoved,
                        onCustomerSubmitted: _handleCustomerSubmitted,
                        onStartTrip: _handleCreateTrip,
                        isCreating: _isCreatingTrip,
                        hasVehicle: _selectedVehicle != null,
                        selectedDrivers: _selectedDrivers,
                        hasOngoingTrip: _hasOngoingTrip,
                      ),
                      const SizedBox(height: 16),

                      if (_isLoading && overview == null)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null && overview == null)
                        _ErrorState(message: _error!, onRetry: _loadTrips)
                      else if (overview != null) ...[
                        _SummarySection(summary: overview.summary),
                        const SizedBox(height: 16),
                        _TripsList(
                          trips: overview.trips,
                          onDeleteTrip: _handleDeleteTrip,
                        ),
                      ] else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),

                // Sticky ON-GOING TRIP CARD at the bottom
                if (_hasOngoingTrip && _ongoingTrip != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _OngoingTripCard(
                      trip: _ongoingTrip!,
                      onUpdate: _handleUpdateTrip,
                      onEnd: _handleEndTrip,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      // Check if focus is on driver or helper dropdown
      if (_driverFocusNode.hasFocus) {
        // Find the first available driver and add it
        if (_filteredDrivers.isNotEmpty) {
          _handleDriverAdded(_filteredDrivers.first);
        }
      } else if (_helperFocusNode.hasFocus) {
        // Find the first available helper and add it
        if (_helpersForPlant.isNotEmpty) {
          _handleHelperAdded(_helpersForPlant.first);
        }
      }
    }
  }

  Future<void> _restoreSavedSelections() async {
    try {
      // Restore plant selection
      final savedPlantId = await _localStorage.getPlantId();
      if (savedPlantId != null && _selectedPlantId != savedPlantId) {
        // Only restore if user has permission to change plant
        if (widget.user.role != UserRole.driver) {
          _selectedPlantId = savedPlantId;
        }
      }

      // Restore vehicle selection after plants are loaded
      final savedVehicleId = await _localStorage.getVehicleId();
      if (savedVehicleId != null && _selectedVehicle == null) {
        // This will be handled after vehicles are loaded
        _savedVehicleId = savedVehicleId;
      }
    } catch (e) {
      // Ignore storage errors
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _saveFormState();
    });
  }

  void _saveFormState() {
    try {
      // Save form state to local storage
      if (_selectedPlant != null) {
        _localStorage.savePlantId(_selectedPlant!.id.toString());
      }
      if (_selectedVehicle != null) {
        _localStorage.saveVehicleId(_selectedVehicle!.id.toString());
      }
    } catch (e) {
      // Ignore storage errors
    }
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary});

  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.directions_car_filled,
            label: 'Total Trips',
            value: summary.totalTrips.toString(),
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.check_circle,
            label: 'Completed',
            value: summary.completedTrips.toString(),
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.pending_actions,
            label: 'Open',
            value: summary.openTrips.toString(),
            color: Colors.orange.shade700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.alt_route,
            label: 'Total KM',
            value: summary.totalRunKm.toStringAsFixed(1),
            color: Colors.blueGrey.shade600,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripsList extends StatefulWidget {
  const _TripsList({required this.trips, required this.onDeleteTrip});

  final List<TripRecord> trips;
  final Function(TripRecord) onDeleteTrip;

  @override
  State<_TripsList> createState() => _TripsListState();
}

class _TripsListState extends State<_TripsList> {
  int _currentPage = 1;
  static const int _pageSize = 10;

  List<TripRecord> get _displayedTrips {
    final startIndex = (_currentPage - 1) * _pageSize;
    final endIndex = startIndex + _pageSize;
    return widget.trips.take(endIndex).toList();
  }

  bool get _hasMoreTrips => widget.trips.length > _currentPage * _pageSize;

  void _loadMore() {
    setState(() {
      _currentPage++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trips.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No trips found for the selected filters.'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._displayedTrips
            .map((trip) => _TripTile(trip: trip, onDelete: widget.onDeleteTrip))
            .toList(growable: false),
        if (_hasMoreTrips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ElevatedButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(
                'Load More (${widget.trips.length - _displayedTrips.length} remaining)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade100,
                foregroundColor: Colors.blue.shade800,
              ),
            ),
          ),
      ],
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({required this.trip, required this.onDelete});

  final TripRecord trip;
  final Function(TripRecord) onDelete;

  String _formatKm(double? value) {
    if (value == null) {
      return '—';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = trip.status.toLowerCase();
    Color statusColor;
    switch (status) {
      case 'ended':
      case 'completed':
        statusColor = Colors.green.shade600;
        break;
      case 'started':
      case 'in_progress':
        statusColor = Colors.orange.shade700;
        break;
      default:
        statusColor = theme.colorScheme.primary;
    }

    // Determine background color based on trip status
    final isOngoing = trip.status.toLowerCase() == 'ongoing';
    final isEnded = trip.status.toLowerCase() == 'ended';
    final backgroundColor = isOngoing
        ? Colors.yellow.shade50
        : isEnded
        ? const Color(0xFFC1E1C1) // Light green for ended trips
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${trip.id} • ${trip.vehicleNumber}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trip.startDate} → ${trip.endDate ?? 'Open'}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: (isOngoing || isEnded)
                            ? [
                                BoxShadow(
                                  color: statusColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: (isOngoing || isEnded)
                          ? GlowingBadge(
                              color: isOngoing ? Colors.orange : Colors.green,
                              child: Text(
                                trip.status.toUpperCase(),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Text(
                              trip.status.toUpperCase(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    // Run KM display
                    if (trip.startKm != null && trip.endKm != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          'Run: ${(trip.endKm! - trip.startKm!).toInt()} km',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => onDelete(trip),
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 20,
                      color: Colors.red.shade600,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'Delete trip',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plant and Run (km) side by side
            Row(
              children: [
                if (trip.plantName != null)
                  Expanded(
                    child: _InfoRow(
                      icon: Icons.factory,
                      label: 'Plant',
                      value: trip.plantName!,
                    ),
                  ),
                if (trip.plantName != null) const SizedBox(width: 16),
                Expanded(
                  child: _InfoRow(
                    icon: Icons.alt_route,
                    label: 'Run (km)',
                    value: _formatKm(trip.runKm),
                  ),
                ),
              ],
            ),

            // Drivers
            _InfoRow(
              icon: Icons.person,
              label: 'Drivers',
              value: trip.drivers?.isNotEmpty == true ? trip.drivers! : '—',
            ),

            // Customers
            if (trip.customers?.isNotEmpty == true)
              _InfoRow(
                icon: Icons.handshake,
                label: 'Customers',
                value: trip.customers!,
              ),

            // Start KM and End KM side by side
            Row(
              children: [
                Expanded(
                  child: _InfoRow(
                    icon: Icons.play_circle_fill,
                    label: 'Start KM',
                    value: _formatKm(trip.startKm),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _InfoRow(
                    icon: Icons.flag,
                    label: 'End KM',
                    value: _formatKm(trip.endKm),
                  ),
                ),
              ],
            ),

            if (trip.note?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(trip.note!, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlantVehicleCard extends StatelessWidget {
  const _PlantVehicleCard({
    required this.plants,
    required this.vehicles,
    required this.isLoadingPlants,
    required this.isLoadingVehicles,
    required this.selectedPlant,
    required this.selectedVehicle,
    required this.onPlantChanged,
    required this.onVehicleChanged,
    required this.onReloadPlants,
    required this.hasOngoingTrip,
    required this.user,
  });

  final List<TripPlant> plants;
  final List<TripVehicle> vehicles;
  final bool isLoadingPlants;
  final bool isLoadingVehicles;
  final TripPlant? selectedPlant;
  final TripVehicle? selectedVehicle;
  final ValueChanged<TripPlant> onPlantChanged;
  final ValueChanged<TripVehicle?> onVehicleChanged;
  final Future<void> Function() onReloadPlants;
  final bool hasOngoingTrip;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    InputDecoration buildDropdownDecoration(String label) {
      return InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.factory, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Plant & Vehicle',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: isLoadingPlants ? null : onReloadPlants,
                  icon: Icon(Icons.refresh, color: theme.colorScheme.primary),
                  tooltip: 'Reload plants',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Side-by-side Plant and Vehicle dropdowns
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TripPlant>(
                    value: plants.contains(selectedPlant)
                        ? selectedPlant
                        : null,
                    decoration: buildDropdownDecoration('Plant'),
                    isExpanded: true,
                    items: plants
                        .map(
                          (plant) => DropdownMenuItem(
                            value: plant,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.local_florist,
                                  size: 18,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    plant.name,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: isLoadingPlants || plants.isEmpty
                        ? null
                        : (user.role == UserRole.driver)
                        ? null
                        : (plant) {
                            if (plant != null) {
                              onPlantChanged(plant);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<TripVehicle>(
                    value: vehicles.contains(selectedVehicle)
                        ? selectedVehicle
                        : null,
                    decoration: buildDropdownDecoration('Vehicle'),
                    isExpanded: true,
                    items: vehicles
                        .map((vehicle) {
                          final details = <String>[];
                          if (vehicle.lastEndKm != null) {
                            details.add('${vehicle.lastEndKm} km');
                          }
                          if (vehicle.lastEndDate != null &&
                              vehicle.lastEndDate!.isNotEmpty) {
                            details.add(vehicle.lastEndDate!);
                          }
                          final subtitle = details.join(' • ');
                          return DropdownMenuItem(
                            value: vehicle,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.local_shipping,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    subtitle.isNotEmpty
                                        ? '${vehicle.number} • $subtitle'
                                        : vehicle.number,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          );
                        })
                        .toList(growable: false),
                    onChanged: isLoadingVehicles || vehicles.isEmpty
                        ? null
                        : (hasOngoingTrip && user.role == UserRole.driver)
                        ? null
                        : onVehicleChanged,
                  ),
                ),
              ],
            ),
            if (isLoadingPlants)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (!isLoadingPlants && plants.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No plants available for your account.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (isLoadingVehicles)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (!isLoadingVehicles && vehicles.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No vehicles mapped to the selected plant.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DriverHelperCard extends StatelessWidget {
  const _DriverHelperCard({
    required this.drivers,
    required this.selectedDrivers,
    required this.helpers,
    required this.selectedHelpers,
    required this.isLoadingDrivers,
    required this.isLoadingHelpers,
    required this.currentDriverId,
    required this.driverFieldKey,
    required this.helperFieldKey,
    required this.driverFocusNode,
    required this.helperFocusNode,
    required this.onDriverAdded,
    required this.onDriverRemoved,
    required this.onHelperAdded,
    required this.onHelperRemoved,
    required this.onReloadHelpers,
  });

  final List<TripDriver> drivers;
  final List<TripDriver> selectedDrivers;
  final List<TripHelper> helpers;
  final List<TripHelper> selectedHelpers;
  final bool isLoadingDrivers;
  final bool isLoadingHelpers;
  final int? currentDriverId;
  final GlobalKey<FormFieldState<int?>> driverFieldKey;
  final GlobalKey<FormFieldState<int?>> helperFieldKey;
  final FocusNode driverFocusNode;
  final FocusNode helperFocusNode;
  final ValueChanged<TripDriver> onDriverAdded;
  final ValueChanged<TripDriver> onDriverRemoved;
  final ValueChanged<TripHelper> onHelperAdded;
  final ValueChanged<TripHelper> onHelperRemoved;
  final Future<void> Function() onReloadHelpers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String driverLabel(TripDriver driver) {
      if (currentDriverId != null && driver.id == currentDriverId) {
        return '${driver.name} (You)';
      }
      return driver.name;
    }

    final driverChipColor = Colors.indigo.shade100;
    final driverChipText = Colors.indigo.shade900;
    final helperChipColor = Colors.purple.shade100;
    final helperChipText = Colors.purple.shade900;

    InputDecoration buildDropdownDecoration(String label) {
      return InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.groups, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Drivers & Helpers',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: isLoadingHelpers
                      ? null
                      : () {
                          unawaited(onReloadHelpers());
                        },
                  icon: Icon(Icons.refresh, color: theme.colorScheme.primary),
                  tooltip: 'Reload helpers',
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              key: driverFieldKey,
              focusNode: driverFocusNode,
              decoration: buildDropdownDecoration('Add Driver'),
              value: null,
              isExpanded: true,
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Select Driver'),
                ),
                ...drivers.map((driver) {
                  return DropdownMenuItem<int?>(
                    value: driver.id,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person,
                          size: 18,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(driverLabel(driver))),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: isLoadingDrivers || drivers.isEmpty
                  ? null
                  : (value) {
                      if (value == null) return;
                      final driver = drivers.firstWhere(
                        (candidate) => candidate.id == value,
                        orElse: () => TripDriver(id: value, name: ''),
                      );
                      if (driver.name.isNotEmpty) {
                        onDriverAdded(driver);
                      }
                      driverFieldKey.currentState?.reset();
                    },
            ),
            if (isLoadingDrivers)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (!isLoadingDrivers && drivers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No drivers available for this plant.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selectedDrivers
                  .map((driver) {
                    final isCurrent =
                        currentDriverId != null && driver.id == currentDriverId;
                    return InputChip(
                      avatar: const Icon(
                        Icons.directions_car,
                        size: 18,
                        color: Colors.indigo,
                      ),
                      backgroundColor: driverChipColor,
                      labelStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: driverChipText,
                        fontWeight: FontWeight.w600,
                      ),
                      deleteIconColor: driverChipText,
                      label: Text(driverLabel(driver)),
                      onDeleted: isCurrent
                          ? null
                          : () => onDriverRemoved(driver),
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int?>(
              key: helperFieldKey,
              focusNode: helperFocusNode,
              decoration: buildDropdownDecoration('Add Helper'),
              value: null,
              isExpanded: true,
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Select Helper'),
                ),
                ...helpers.map(
                  (helper) => DropdownMenuItem<int?>(
                    value: helper.id,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.volunteer_activism,
                          size: 18,
                          color: Colors.purple,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(helper.name)),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: isLoadingHelpers || helpers.isEmpty
                  ? null
                  : (value) {
                      if (value == null) return;
                      final helper = helpers.firstWhere(
                        (candidate) => candidate.id == value,
                        orElse: () => TripHelper(id: value, name: ''),
                      );
                      if (helper.name.isNotEmpty) {
                        onHelperAdded(helper);
                      }
                      helperFieldKey.currentState?.reset();
                    },
            ),
            if (isLoadingHelpers)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (!isLoadingHelpers && helpers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No helpers mapped to this plant.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selectedHelpers
                  .map((helper) {
                    return InputChip(
                      avatar: const Icon(
                        Icons.group,
                        size: 18,
                        color: Colors.purple,
                      ),
                      backgroundColor: helperChipColor,
                      labelStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: helperChipText,
                        fontWeight: FontWeight.w600,
                      ),
                      deleteIconColor: helperChipText,
                      label: Text(helper.name),
                      onDeleted: () => onHelperRemoved(helper),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripStartCard extends StatefulWidget {
  const _TripStartCard({
    required this.startDateController,
    required this.onPickStartDate,
    required this.startKmController,
    required this.noteController,
    required this.customerController,
    required this.customerSuggestions,
    required this.selectedCustomers,
    required this.onCustomerAdded,
    required this.onCustomerRemoved,
    required this.onCustomerSubmitted,
    required this.onStartTrip,
    required this.isCreating,
    required this.hasVehicle,
    required this.selectedDrivers,
    this.hasOngoingTrip = false,
  });

  final TextEditingController startDateController;
  final VoidCallback onPickStartDate;
  final TextEditingController startKmController;
  final TextEditingController noteController;
  final TextEditingController customerController;
  final List<String> customerSuggestions;
  final List<String> selectedCustomers;
  final ValueChanged<String> onCustomerAdded;
  final ValueChanged<String> onCustomerRemoved;
  final VoidCallback onCustomerSubmitted;
  final Future<void> Function() onStartTrip;
  final bool isCreating;
  final bool hasVehicle;
  final List<TripDriver> selectedDrivers;
  final bool hasOngoingTrip;

  @override
  State<_TripStartCard> createState() => _TripStartCardState();
}

class _TripStartCardState extends State<_TripStartCard> {
  List<String> _getFilteredSuggestions(
    String searchText,
    List<String> suggestions,
  ) {
    if (searchText.isEmpty) {
      return suggestions;
    }
    return suggestions.where((suggestion) {
      return suggestion.toLowerCase().contains(searchText.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canStart =
        !widget.isCreating &&
        widget.hasVehicle &&
        widget.selectedDrivers.isNotEmpty &&
        widget.selectedCustomers.isNotEmpty &&
        (widget.hasOngoingTrip ||
            (widget.startKmController.text.trim().isNotEmpty &&
                widget.startDateController.text.trim().isNotEmpty));
    final selectedChipColor = Colors.teal.shade100;
    final selectedChipTextColor = Colors.teal.shade900;
    final suggestionChipColor = Colors.orange.shade100;
    final suggestionChipTextColor = Colors.deepOrange.shade900;

    InputDecoration buildFieldDecoration(String label, {Widget? suffixIcon}) {
      return InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: suffixIcon,
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.rocket_launch, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.hasOngoingTrip ? 'Update Trip' : 'Start Trip',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.startDateController,
                    readOnly: true,
                    decoration: buildFieldDecoration(
                      'Start Date',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: widget.onPickStartDate,
                      ),
                    ),
                    onTap: widget.onPickStartDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: widget.startKmController,
                    keyboardType: TextInputType.number,
                    decoration: buildFieldDecoration('Start KM'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.customerController,
              decoration: buildFieldDecoration(
                'Add Customer',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: widget.onCustomerSubmitted,
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => widget.onCustomerSubmitted(),
              onChanged: (value) {
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            if (widget.selectedCustomers.isEmpty)
              Text(
                'No customers added yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.selectedCustomers
                    .map(
                      (name) => InputChip(
                        backgroundColor: selectedChipColor,
                        labelStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: selectedChipTextColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        deleteIconColor: selectedChipTextColor,
                        label: Text(name),
                        onDeleted: () => widget.onCustomerRemoved(name),
                      ),
                    )
                    .toList(growable: false),
              ),
            if (widget.customerSuggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Suggestions',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _getFilteredSuggestions(
                          widget.customerController.text,
                          widget.customerSuggestions,
                        )
                        .take(12)
                        .map(
                          (suggestion) => ActionChip(
                            backgroundColor: suggestionChipColor,
                            labelStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: suggestionChipTextColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                            avatar: const Icon(
                              Icons.bolt,
                              size: 18,
                              color: Colors.deepOrange,
                            ),
                            label: Text(suggestion),
                            onPressed: () => widget.onCustomerAdded(suggestion),
                          ),
                        )
                        .toList(growable: false),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: widget.noteController,
              maxLines: 2,
              decoration: buildFieldDecoration('Note (optional)'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: canStart ? () => widget.onStartTrip() : null,
                icon: widget.isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  widget.hasOngoingTrip ? 'Update Trip' : 'Start Trip',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OngoingTripCard extends StatefulWidget {
  const _OngoingTripCard({
    required this.trip,
    required this.onUpdate,
    required this.onEnd,
  });

  final TripRecord trip;
  final VoidCallback onUpdate;
  final VoidCallback onEnd;

  @override
  State<_OngoingTripCard> createState() => _OngoingTripCardState();
}

class _OngoingTripCardState extends State<_OngoingTripCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade50, Colors.orange.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with glowing tag-style "Ongoing Trip"
                Row(
                  children: [
                    GlowingBadge(
                      color: Colors.orange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "ONGOING",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onUpdate,
                          icon: const Icon(Icons.update, size: 16),
                          label: const Text('Update'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: widget.onEnd,
                          icon: const Icon(Icons.flag, size: 16),
                          label: const Text('End'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Trip info
                Row(
                  children: [
                    Text(
                      "#${widget.trip.id}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (widget.trip.vehicleNumber.isNotEmpty)
                      Text(
                        widget.trip.vehicleNumber,
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(width: 16),
                    if (widget.trip.startDate.isNotEmpty)
                      Text(
                        widget.trip.startDate,
                        style: const TextStyle(fontSize: 12),
                      ),
                    const Spacer(),
                    if (widget.trip.startKm != null)
                      Text(
                        "${widget.trip.startKm!.toInt()} km",
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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
  }
}
