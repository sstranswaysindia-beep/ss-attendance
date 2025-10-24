import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/admin_driver_master.dart';
import '../../core/models/app_user.dart';
import '../../core/services/admin_master_repository.dart';
import '../../core/widgets/app_toast.dart';

const Color _adminPrimaryColor = Color(0xFF00296B);
const Color _adminAccentLight = Color(0xFFE3F2FD);

class AdminDriverMasterScreen extends StatefulWidget {
  const AdminDriverMasterScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AdminDriverMasterScreen> createState() => _AdminDriverMasterScreenState();
}

class _AdminDriverMasterScreenState extends State<AdminDriverMasterScreen> {
  final AdminMasterRepository _repository = AdminMasterRepository();
  final TextEditingController _searchController = TextEditingController();

  List<AdminDriver> _drivers = const [];
  String? _errorMessage;
  String _activeSearch = '';
  bool _isLoading = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers({
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
      final results = await _repository.fetchDrivers(
        search: query.isEmpty ? null : query,
      );
      if (!mounted) return;
      setState(() {
        _drivers = results;
        _errorMessage = null;
      });
    } on AdminMasterFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load drivers. Please try again.';
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
    _loadDrivers(search: term.isEmpty ? null : term);
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    if (_activeSearch.isEmpty) return;
    _loadDrivers(search: '');
  }

  Future<void> _handleRefresh() {
    return _loadDrivers(search: _activeSearch, showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _adminPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Driver Master',
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
                        labelText: 'Search by name, code or plant',
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
            Expanded(
              child: _buildContent(),
            ),
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
                onPressed: _isLoading ? null : () => _loadDrivers(search: _activeSearch),
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

    if (_drivers.isEmpty) {
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
                    ? 'No drivers available.'
                    : 'No drivers found for "${_activeSearch}".',
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
        itemCount: _drivers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final driver = _drivers[index];
          return _DriverMasterCard(driver: driver);
        },
      ),
    );
  }
}

class _DriverMasterCard extends StatelessWidget {
  const _DriverMasterCard({required this.driver});

  final AdminDriver driver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('dd MMM yyyy');
    final joiningText = driver.joiningDate != null
        ? 'Joined ${dateFormatter.format(driver.joiningDate!)}'
        : 'Joining date NA';
    final licenceText = driver.dlValidity != null
        ? 'DL valid till ${dateFormatter.format(driver.dlValidity!)}'
        : 'DL validity NA';

    final avatar = driver.hasProfilePhoto
        ? CircleAvatar(
            radius: 26,
            backgroundImage: NetworkImage(driver.profilePhoto!),
            backgroundColor: _adminPrimaryColor.withOpacity(0.1),
          )
        : CircleAvatar(
            radius: 26,
            backgroundColor: _adminPrimaryColor.withOpacity(0.1),
            child: Text(
              driver.initials,
              style: const TextStyle(
                color: _adminPrimaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          );

    final statusColor = driver.isActive ? Colors.green : Colors.red;

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _adminPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.badge, size: 16, color: _adminPrimaryColor),
                        label: Text(
                          'Emp ID: ${driver.empId}',
                          style: const TextStyle(color: _adminPrimaryColor),
                        ),
                        backgroundColor: _adminAccentLight,
                      ),
                      Chip(
                        avatar: const Icon(Icons.apartment, size: 16, color: _adminPrimaryColor),
                        label: Text(
                          driver.plantName.isEmpty ? 'Plant: Unassigned' : driver.plantName,
                          style: const TextStyle(color: _adminPrimaryColor),
                        ),
                        backgroundColor: _adminAccentLight,
                      ),
                      Chip(
                        avatar: const Icon(Icons.person, size: 16, color: _adminPrimaryColor),
                        label: Text(
                          driver.displayRole,
                          style: const TextStyle(color: _adminPrimaryColor),
                        ),
                        backgroundColor: _adminAccentLight,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((driver.contact ?? '').isNotEmpty)
                    Text(
                      'Contact: ${driver.contact}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  Text(
                    licenceText,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    joiningText,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Chip(
                  label: Text(
                    driver.status,
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: statusColor,
                ),
                if (driver.dlNumber != null && driver.dlNumber!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'DL: ${driver.dlNumber}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _adminPrimaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
