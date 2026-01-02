import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/admin_driver_master.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';
import 'tyre_layout_screen.dart';

class TyreVehiclePickerScreen extends StatefulWidget {
  const TyreVehiclePickerScreen({
    required this.user,
    required this.repository,
    required this.instructions,
    super.key,
  });

  final AppUser user;
  final SafetyRepository repository;
  final TyreInstructions instructions;

  @override
  State<TyreVehiclePickerScreen> createState() =>
      _TyreVehiclePickerScreenState();
}

class _TyreVehiclePickerScreenState extends State<TyreVehiclePickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<SafetyVehicle> _vehicles = const <SafetyVehicle>[];
  List<SafetyVehicle> _filteredVehicles = const <SafetyVehicle>[];
  List<_PlantOption> _plantOptions = const <_PlantOption>[];
  int? _selectedPlantId;
  int? _selectedDriverId;
  Map<int, List<AdminDriver>> _plantDrivers = const <int, List<AdminDriver>>{};
  bool _ascending = true;
  bool _isLoading = true;
  bool _isStarting = false;
  String? _error;
  int? _busyVehicleId;

  DateTime? _parseFlexibleDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.contains(' ') && !raw.contains('T')
        ? raw.replaceFirst(' ', 'T')
        : raw;
    return DateTime.tryParse(normalized);
  }

  String _formatLastInspection(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final dt = _parseFlexibleDateTime(raw);
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy').format(dt);
  }

  int? _daysPassedSince(String? raw) {
    final dt = _parseFlexibleDateTime(raw);
    if (dt == null) return null;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative) return 0;
    return diff.inDays;
  }

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _loadDrivers();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final vehicles = await widget.repository.fetchVehicles(user: widget.user);
      setState(() {
        _vehicles = vehicles;
        _plantOptions = _buildPlantOptions(vehicles);
        _selectedPlantId ??= _plantOptions.isNotEmpty
            ? _plantOptions.first.id
            : null;
      });
      _applyFilters();
    } catch (error, stackTrace) {
      debugPrint('TyreVehiclePicker: $error\n$stackTrace');
      setState(() {
        _error = error.toString();
        _vehicles = const <SafetyVehicle>[];
        _filteredVehicles = const <SafetyVehicle>[];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadDrivers() async {
    try {
      final directory = await widget.repository.fetchPlantDirectory(
        user: widget.user,
      );
      final driversMap = <int, List<AdminDriver>>{};
      for (final entry in directory) {
        final plantDrivers = entry.drivers
            .map(
              (driver) => AdminDriver(
                id: driver.id,
                empId: '',
                name: driver.name,
                role: '',
                status: 'Active',
                plantName: entry.name,
                contact: null,
                dlNumber: null,
                dlValidity: null,
                joiningDate: null,
                profilePhoto: null,
                plantId: entry.id,
              ),
            )
            .where((d) => d.id > 0 && d.name.isNotEmpty)
            .toList(growable: false);
        driversMap[entry.id] = plantDrivers;
      }
      if (mounted) {
        setState(() {
          _plantDrivers = driversMap;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('TyreVehiclePicker loadDrivers error: $error\n$stackTrace');
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    var list = _vehicles;

    if (_selectedPlantId != null) {
      list = list
          .where((vehicle) => vehicle.plantId == _selectedPlantId)
          .toList(growable: false);
    }

    if (query.isNotEmpty) {
      list = list
          .where(
            (vehicle) =>
                vehicle.vehicleNumber.toLowerCase().contains(query) ||
                (vehicle.plantName?.toLowerCase().contains(query) ?? false),
          )
          .toList(growable: false);
    }

    list = list.toList(growable: false);
    list.sort((a, b) => a.vehicleNumber.compareTo(b.vehicleNumber));
    if (!_ascending) {
      list = list.reversed.toList(growable: false);
    }

    setState(() {
      _filteredVehicles = list;
    });
  }

  List<_PlantOption> _buildPlantOptions(List<SafetyVehicle> vehicles) {
    final seen = <int, String>{};
    for (final v in vehicles) {
      if (v.plantId > 0) {
        seen.putIfAbsent(v.plantId, () => v.plantName ?? 'Plant ${v.plantId}');
      }
    }
    final options = seen.entries
        .map((e) => _PlantOption(id: e.key, name: e.value))
        .toList(growable: false);
    options.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return options;
  }

  Future<void> _handleVehicleSelected(SafetyVehicle vehicle) async {
    if (_selectedDriverId == null) {
      showAppToast(context, 'Please select a driver first');
      return;
    }
    if (vehicle.isInspectionLocked) {
      final remaining = vehicle.inspectionUnlockDays ?? 0;
      final message = remaining > 0
          ? 'Inspection already submitted. Check back in $remaining day${remaining == 1 ? '' : 's'}.'
          : 'Inspection already submitted. Unlocks soon.';
      showAppToast(context, message);
      return;
    }
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _busyVehicleId = vehicle.id;
    });

    try {
      final start = await widget.repository.startInspection(
        vehicleId: vehicle.id,
        user: widget.user,
        driverId: _selectedDriverId!,
      );
      if (!mounted) return;
      final submitted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TyreLayoutScreen(
            repository: widget.repository,
            instructions: widget.instructions,
            vehicle: vehicle,
            inspectionId: start.inspectionId,
            positions: start.positions,
          ),
        ),
      );

      if (submitted == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error, stackTrace) {
      debugPrint('TyreVehiclePicker start error: $error\n$stackTrace');
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        showAppToast(
          context,
          message.isNotEmpty ? message : 'Unable to start inspection',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _busyVehicleId = null;
        });
      }
    }
  }

  void _toggleSort() {
    setState(() => _ascending = !_ascending);
    _applyFilters();
  }

  List<AdminDriver> get _filteredDrivers {
    final plantId = _selectedPlantId;
    if (plantId != null) {
      final list = _plantDrivers[plantId];
      if (list != null && list.isNotEmpty) return list;
    }
    // fallback to all drivers across plants
    return _plantDrivers.values.expand((e) => e).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamp textScaler to prevent scaling from both font size and display size settings
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: AppGradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: const Color(
              0xFF12355B,
            ), // Dark blue (same as training/spot audit)
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Select Vehicle',
              style: GoogleFonts.josefinSans(
                textStyle: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: _ascending ? 'Sort Z → A' : 'Sort A → Z',
                onPressed: _toggleSort,
                icon: Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x140A0A0A),
                        blurRadius: 10,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search vehicle or plant',
                      hintStyle: GoogleFonts.josefinSans(
                        textStyle: theme.textTheme.bodyMedium,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    style: GoogleFonts.josefinSans(
                      textStyle: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              if (_plantOptions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: DropdownButtonFormField<int?>(
                    value: _selectedPlantId,
                    decoration: InputDecoration(
                      labelText: 'Plant',
                      labelStyle: GoogleFonts.josefinSans(
                        textStyle: theme.textTheme.bodyMedium,
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    dropdownColor: Colors.white,
                    style: GoogleFonts.josefinSans(
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.black87,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'All Plants',
                          style: GoogleFonts.josefinSans(
                            textStyle: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      ..._plantOptions.map(
                        (p) => DropdownMenuItem<int?>(
                          value: p.id,
                          child: Text(
                            p.name,
                            style: GoogleFonts.josefinSans(
                              textStyle: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedPlantId = value;
                        _selectedDriverId = null;
                      });
                      _applyFilters();
                    },
                  ),
                ),
              if (_filteredDrivers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: DropdownButtonFormField<int?>(
                    value: _selectedDriverId,
                    decoration: InputDecoration(
                      labelText: 'Driver',
                      labelStyle: GoogleFonts.josefinSans(
                        textStyle: theme.textTheme.bodyMedium,
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    dropdownColor: Colors.white,
                    style: GoogleFonts.josefinSans(
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.black87,
                      ),
                    ),
                    items: _filteredDrivers
                        .map(
                          (d) => DropdownMenuItem<int?>(
                            value: d.id,
                            child: Text(
                              d.name,
                              style: GoogleFonts.josefinSans(
                                textStyle: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedDriverId = value);
                    },
                  ),
                ),
              if (_filteredDrivers.isNotEmpty) const SizedBox(height: 8),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: AppLoader())
                    : _error != null
                    ? _VehicleError(message: _error!, onRetry: _loadVehicles)
                    : _filteredVehicles.isEmpty
                    ? const _VehicleEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _filteredVehicles.length,
                        itemBuilder: (context, index) {
                          final vehicle = _filteredVehicles[index];
                          final isBusy = _busyVehicleId == vehicle.id;
                          final isLocked = vehicle.isInspectionLocked;
                          final daysRemaining =
                              vehicle.inspectionUnlockDays ?? 0;
                          final gradient = isLocked
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFE8F9EF),
                                    Color(0xFFCFFADE),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFE6F3FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                );
                          return AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: isBusy ? 0.6 : 1,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                gradient: gradient,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x12000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                leading: CircleAvatar(
                                  radius: 22,
                                  backgroundColor:
                                      (isLocked
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFF1C7ED6))
                                          .withOpacity(0.18),
                                  child: Text(
                                    vehicle.tyreCount.toString(),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: isLocked
                                          ? const Color(0xFF0F5132)
                                          : const Color(0xFF1C7ED6),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  vehicle.vehicleNumber,
                                  style: GoogleFonts.josefinSans(
                                    textStyle: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: const Color(0xFF0F2949),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vehicle.plantName != null
                                          ? 'Plant: ${vehicle.plantName}'
                                          : 'Tyres: ${vehicle.tyreCount}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF3A5A84),
                                          ),
                                    ),
                                    Text(
                                      'Last inspection: ${_formatLastInspection(vehicle.latestInspectionSubmittedAt)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF3A5A84),
                                          ),
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final passed = _daysPassedSince(
                                          vehicle.latestInspectionSubmittedAt,
                                        );
                                        if (passed == null) {
                                          return const SizedBox.shrink();
                                        }
                                        final left =
                                            vehicle.inspectionUnlockDays ?? 0;
                                        return Text(
                                          'Days passed: $passed  •  Days left: $left',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF3A5A84),
                                              ),
                                        );
                                      },
                                    ),
                                    if (isLocked)
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          daysRemaining > 0
                                              ? 'Inspection submitted · $daysRemaining day${daysRemaining == 1 ? '' : 's'} left'
                                              : 'Inspection submitted · unlocks soon',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: const Color(0xFF166534),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: isBusy
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: AppLoader(size: 24),
                                      )
                                    : Icon(
                                        isLocked
                                            ? Icons.lock
                                            : Icons.chevron_right,
                                      ),
                                onTap: () => _handleVehicleSelected(vehicle),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantOption {
  const _PlantOption({required this.id, required this.name});
  final int id;
  final String name;
}

class _VehicleError extends StatelessWidget {
  const _VehicleError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 12),
            Text('Unable to load vehicles', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1C7ED6), Color(0xFF5AA9FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.all(Radius.circular(40)),
              ),
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleEmptyState extends StatelessWidget {
  const _VehicleEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_bus_filled_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'No vehicles available for tyre checklist',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
