import 'package:flutter/material.dart';

import '../../core/models/admin_proxy_user.dart';
import '../../core/models/app_user.dart';
import '../../core/services/admin_proxy_repository.dart';
import '../../core/widgets/app_toast.dart';

const Color _proxyPrimaryColor = Color(0xFF0B3D91);
const Color _proxyCardTint = Color(0xFFD6E4FF);

class AdminProxyScreen extends StatefulWidget {
  const AdminProxyScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AdminProxyScreen> createState() => _AdminProxyScreenState();
}

class _AdminProxyScreenState extends State<AdminProxyScreen> {
  final AdminProxyRepository _repository = AdminProxyRepository();
  final Set<int> _pendingUpdates = <int>{};

  bool _isLoading = true;
  String? _error;
  int? _selectedPlantId;
  List<AdminProxyUser> _users = const <AdminProxyUser>[];
  List<AdminProxyPlant> _plants = const <AdminProxyPlant>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({int? plantId}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedPlantId = plantId;
    });
    try {
      final payload = await _repository.fetchUsers(plantId: plantId);
      if (!mounted) return;
      setState(() {
        _users = payload.users;
        _plants = payload.plants;
        _error = null;
      });
    } on AdminProxyFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load proxy attendance data. Please try again.';
      setState(() => _error = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _onPlantChanged(int? plantId) {
    if (_selectedPlantId == plantId) {
      return;
    }
    _loadData(plantId: plantId);
  }

  Future<void> _onToggle(AdminProxyUser user, bool enabled) async {
    if (_pendingUpdates.contains(user.userId)) {
      return;
    }
    final index = _users.indexWhere((element) => element.userId == user.userId);
    if (index == -1) {
      return;
    }

    setState(() {
      _pendingUpdates.add(user.userId);
      _users = List<AdminProxyUser>.from(_users)
        ..[index] = _users[index].copyWith(proxyEnabled: enabled);
    });

    try {
      await _repository.updateProxy(userId: user.userId, enabled: enabled);
      if (!mounted) return;
      final message = enabled
          ? 'Enabled proxy attendance for ${user.fullName}.'
          : 'Disabled proxy attendance for ${user.fullName}.';
      showAppToast(context, message);
    } on AdminProxyFailure catch (error) {
      if (!mounted) return;
      _revertToggle(index, user, !enabled);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _revertToggle(index, user, !enabled);
      showAppToast(
        context,
        'Unable to update proxy attendance for ${user.fullName}.',
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() => _pendingUpdates.remove(user.userId));
    }
  }

  void _revertToggle(int index, AdminProxyUser user, bool value) {
    setState(() {
      _users = List<AdminProxyUser>.from(_users)
        ..[index] = user.copyWith(proxyEnabled: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _proxyPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Proxy Attendance',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadData(plantId: _selectedPlantId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Color(0x2200296B),
                color: _proxyPrimaryColor,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProxyCard(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProxyCard(BuildContext context) {
    final theme = Theme.of(context);
    final plantItems = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('All plants'),
      ),
      ..._plants.map(
        (plant) => DropdownMenuItem<int?>(
          value: plant.id,
          child: Text(plant.name),
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, _proxyCardTint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _proxyPrimaryColor.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B3D91),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Proxy Attendance Controls',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _proxyPrimaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage who can submit attendance on behalf of others.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _proxyPrimaryColor.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Filter by plant',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _selectedPlantId,
                items: plantItems,
                isExpanded: true,
                dropdownColor: Colors.white,
                onChanged: _isLoading ? null : _onPlantChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null && !_isLoading)
            _ProxyEmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              message: _error!,
              onRetry: () => _loadData(plantId: _selectedPlantId),
            )
          else if (!_isLoading && _users.isEmpty)
            const _ProxyEmptyState(
              icon: Icons.person_off_outlined,
              title: 'No users found',
              message: 'No users are eligible for proxy attendance for this plant.',
            )
          else
            ..._users.map(
              (user) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProxyUserTile(
                  user: user,
                  isBusy: _pendingUpdates.contains(user.userId),
                  onChanged: (value) => _onToggle(user, value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProxyUserTile extends StatelessWidget {
  const _ProxyUserTile({
    required this.user,
    required this.onChanged,
    required this.isBusy,
  });

  final AdminProxyUser user;
  final ValueChanged<bool> onChanged;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plantNames =
        user.plants.isEmpty ? 'Unassigned' : user.plants.map((p) => p.name).join(', ');
    final roleLabel = user.role.isEmpty
        ? 'Unknown'
        : '${user.role[0].toUpperCase()}${user.role.substring(1).toLowerCase()}';
    final subtitleParts = <String>[
      roleLabel,
      if (user.employeeId != null && user.employeeId!.isNotEmpty)
        'Emp: ${user.employeeId}',
      if (user.contact != null && user.contact!.isNotEmpty)
        '☎ ${user.contact}',
    ];
    final subtitle = subtitleParts.join(' • ');

    return Card(
      color: Colors.transparent,
      elevation: 0.5,
      shadowColor: const Color(0x200B3D91),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.white, Color(0xFFE3EDFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _proxyPrimaryColor.withOpacity(0.05)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _proxyPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _proxyPrimaryColor.withOpacity(0.75),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: _proxyPrimaryColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          plantNames,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _proxyPrimaryColor.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: user.proxyEnabled,
              onChanged: isBusy ? null : onChanged,
              activeColor: const Color(0xFF1ABC9C),
              activeTrackColor: const Color(0xFF8DE3C5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyEmptyState extends StatelessWidget {
  const _ProxyEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _proxyPrimaryColor.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: _proxyPrimaryColor.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: _proxyPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _proxyPrimaryColor.withOpacity(0.7),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: _proxyPrimaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
