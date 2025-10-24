import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/admin_vehicle_master.dart';
import '../../core/models/app_user.dart';
import '../../core/services/admin_master_repository.dart';
import '../../core/widgets/app_toast.dart';

const Color _adminPrimaryColor = Color(0xFF00296B);
const Color _adminAccentLight = Color(0xFFE3F2FD);

class AdminVehicleMasterScreen extends StatefulWidget {
  const AdminVehicleMasterScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AdminVehicleMasterScreen> createState() => _AdminVehicleMasterScreenState();
}

class _AdminVehicleMasterScreenState extends State<AdminVehicleMasterScreen> {
  final AdminMasterRepository _repository = AdminMasterRepository();
  final TextEditingController _searchController = TextEditingController();

  List<AdminVehicle> _vehicles = const [];
  String? _errorMessage;
  String _activeSearch = '';
  bool _isLoading = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles({
    String? search,
    bool showSpinner = true,
  }) async {
    final query = search ?? _activeSearch;
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _activeSearch = query;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _activeSearch = query;
      });
    }

    try {
      final results = await _repository.fetchVehicles(
        search: query.isEmpty ? null : query,
      );
      if (!mounted) return;
      setState(() {
        _vehicles = results;
        _errorMessage = null;
      });
    } on AdminMasterFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load vehicles. Please try again.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _onSearch() {
    final term = _searchController.text.trim();
    if (_isLoading && term == _activeSearch) {
      return;
    }
    _loadVehicles(search: term.isEmpty ? null : term);
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    if (_activeSearch.isEmpty) return;
    _loadVehicles(search: '');
  }

  Future<void> _handleRefresh() {
    return _loadVehicles(search: _activeSearch, showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _adminPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Vehicle Master',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Color(0x2200296B),
                color: _adminPrimaryColor,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _onSearch(),
                      decoration: InputDecoration(
                        labelText: 'Search by vehicle, plant or company',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _activeSearch.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear search',
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.close),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _onSearch,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('Search'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0088CC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isLoading ? null : () => _loadVehicles(search: _activeSearch),
                style: FilledButton.styleFrom(
                  backgroundColor: _adminPrimaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_vehicles.isEmpty) {
      return RefreshIndicator(
        color: _adminPrimaryColor,
        onRefresh: _handleRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 120, left: 24, right: 24),
              child: Text(
                _activeSearch.isEmpty
                    ? 'No vehicles available.'
                    : 'No vehicles found for "${_activeSearch}".',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _adminPrimaryColor,
      onRefresh: _handleRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final vehicle = _vehicles[index];
          return _VehicleMasterCard(vehicle: vehicle);
        },
      ),
    );
  }
}

class _VehicleMasterCard extends StatelessWidget {
  const _VehicleMasterCard({required this.vehicle});

  final AdminVehicle vehicle;

  Color _expiryColor(DateTime? date) {
    if (date == null) return _adminPrimaryColor;
    final now = DateTime.now();
    if (date.isBefore(now)) return Colors.red.shade600;
    if (date.difference(now).inDays <= 30) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'NA';
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, _adminAccentLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _adminPrimaryColor.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1400296B),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _adminPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    vehicle.displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _adminPrimaryColor,
                    ),
                  ),
                ),
                const Spacer(),
                Chip(
                  avatar: const Icon(Icons.apartment, size: 16, color: Colors.white),
                  label: Text(
                    vehicle.plantName.isEmpty ? 'Unassigned' : vehicle.plantName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: _adminPrimaryColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if ((vehicle.company ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.business,
                    label: vehicle.company!,
                  ),
                if ((vehicle.location ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.location_on,
                    label: vehicle.location!,
                  ),
                if ((vehicle.gps ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.gps_fixed,
                    label: 'GPS: ${vehicle.gps}',
                  ),
                if ((vehicle.modelNumber ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.directions_bus,
                    label: 'Model: ${vehicle.modelNumber}',
                  ),
                _ExpiryChip(
                  icon: Icons.assignment,
                  label: 'Registration ${_formatDate(vehicle.registrationDate)}',
                  color: _expiryColor(vehicle.registrationDate),
                ),
                _ExpiryChip(
                  icon: Icons.fitness_center,
                  label: 'Fitness ${_formatDate(vehicle.fitnessExpiry)}',
                  color: _expiryColor(vehicle.fitnessExpiry),
                ),
                _ExpiryChip(
                  icon: Icons.health_and_safety,
                  label: 'Insurance ${_formatDate(vehicle.insuranceExpiry)}',
                  color: _expiryColor(vehicle.insuranceExpiry),
                ),
                _ExpiryChip(
                  icon: Icons.factory,
                  label: 'Pollution ${_formatDate(vehicle.pollutionExpiry)}',
                  color: _expiryColor(vehicle.pollutionExpiry),
                ),
                _ExpiryChip(
                  icon: Icons.handyman,
                  label: 'Brake Test ${_formatDate(vehicle.brakeTestExpiry)}',
                  color: _expiryColor(vehicle.brakeTestExpiry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: _adminPrimaryColor),
      label: Text(label, style: const TextStyle(color: _adminPrimaryColor)),
      backgroundColor: _adminAccentLight,
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }
}
