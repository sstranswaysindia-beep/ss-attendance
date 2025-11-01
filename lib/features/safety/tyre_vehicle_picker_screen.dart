import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/app_user.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
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
  State<TyreVehiclePickerScreen> createState() => _TyreVehiclePickerScreenState();
}

class _TyreVehiclePickerScreenState extends State<TyreVehiclePickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<SafetyVehicle> _vehicles = const <SafetyVehicle>[];
  List<SafetyVehicle> _filteredVehicles = const <SafetyVehicle>[];
  bool _ascending = true;
  bool _isLoading = true;
  bool _isStarting = false;
  String? _error;
  int? _busyVehicleId;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
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

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    var list = _vehicles;
    if (query.isNotEmpty) {
      list = list
          .where(
            (vehicle) => vehicle.vehicleNumber.toLowerCase().contains(query) ||
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

  Future<void> _handleVehicleSelected(SafetyVehicle vehicle) async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _busyVehicleId = vehicle.id;
    });

    try {
      final start = await widget.repository.startInspection(
        vehicleId: vehicle.id,
        user: widget.user,
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
        showAppToast(context, 'Unable to start inspection: $error', isError: true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Select Vehicle',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: _ascending ? 'Sort Z → A' : 'Sort A → Z',
              onPressed: _toggleSort,
              icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
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
                                return AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: isBusy ? 0.6 : 1,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
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
                                        backgroundColor: const Color(0xFF1C7ED6).withOpacity(0.12),
                                        child: Text(
                                          vehicle.tyreCount.toString(),
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            color: const Color(0xFF1C7ED6),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        vehicle.vehicleNumber,
                                        style: GoogleFonts.josefinSans(
                                          textStyle: theme.textTheme.titleMedium?.copyWith(
                                            color: const Color(0xFF0F2949),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      subtitle: Text(
                                        vehicle.plantName != null
                                            ? 'Plant: ${vehicle.plantName}'
                                            : 'Tyres: ${vehicle.tyreCount}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFF3A5A84),
                                        ),
                                      ),
                                      trailing: isBusy
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.chevron_right),
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
    );
  }
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
          Icon(Icons.directions_bus_filled_outlined,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('No vehicles available for tyre checklist',
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
