import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/proxy_employee.dart';
import '../../core/services/proxy_attendance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class ProxyAttendanceScreen extends StatefulWidget {
  const ProxyAttendanceScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<ProxyAttendanceScreen> createState() => _ProxyAttendanceScreenState();
}

class _ProxyAttendanceScreenState extends State<ProxyAttendanceScreen> {
  final ProxyAttendanceRepository _repository = ProxyAttendanceRepository();
  final DateFormat _dateFormatter = DateFormat('dd MMM yyyy • HH:mm');

  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<ProxyEmployee> _employees = const [];
  List<ProxyPlantOption> _plants = const [];
  ProxyEmployee? _selectedEmployee;
  String? _selectedPlantId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _repository.fetchEmployees(
        supervisorUserId: widget.user.id,
        plantId: _selectedPlantId,
      );
      if (!mounted) return;

      ProxyEmployee? updatedSelection;
      if (_selectedEmployee != null) {
        updatedSelection = response.employees.firstWhere(
          (employee) => employee.driverId == _selectedEmployee!.driverId,
          orElse: () => _selectedEmployee!,
        );
        if (!response.employees.contains(updatedSelection)) {
          updatedSelection = null;
        }
      }

      setState(() {
        _employees = response.employees;
        _plants = response.plants;
        _selectedEmployee =
            updatedSelection ??
            (response.employees.isNotEmpty ? response.employees.first : null);
        _isLoading = false;
      });
    } on ProxyAttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
        _employees = const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load proxy records.';
        _employees = const [];
      });
    }
  }

  Future<void> _submit(String action) async {
    final employee = _selectedEmployee;
    if (employee == null) {
      showAppToast(context, 'Select an employee first.', isError: true);
      return;
    }
    if (_isSelf(employee)) {
      showAppToast(
        context,
        'You cannot proxy mark attendance for your own account.',
        isError: true,
      );
      return;
    }
    if (action == 'check_in' && employee.attendanceCompleted) {
      showAppToast(
        context,
        'Attendance already completed for this employee today.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _repository.submit(
        supervisorUserId: widget.user.id,
        driverId: employee.driverId,
        userId: employee.userId,
        action: action,
      );

      if (!mounted) return;
      showAppToast(
        context,
        action == 'check_in'
            ? 'Check-in recorded successfully.'
            : 'Check-out recorded successfully.',
      );
      await _loadData();
    } on ProxyAttendanceFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to submit attendance.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _buildContent(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Proxy Attendance')),
      body: AppGradientBackground(child: body),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSupervisorBanner(context),
          const SizedBox(height: 16),
          if (_plants.length > 1) _buildPlantFilter(context),
          if (_plants.length > 1) const SizedBox(height: 16),
          _buildEmployeeSelector(context),
          const SizedBox(height: 16),
          if (_selectedEmployee != null)
            _buildEmployeeSummary(context, _selectedEmployee!),
          const SizedBox(height: 16),
          if (_selectedEmployee != null)
            _buildActionButtons(context, _selectedEmployee!),
          const SizedBox(height: 24),
          _buildInfoFooter(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSupervisorBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.indigo.shade200,
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Supervisor ID: ${widget.user.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.user.supervisedPlants.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Plants: ${widget.user.supervisedPlants.map((p) => p['plant_name']).join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlantFilter(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _selectedPlantId,
      icon: const Icon(Icons.arrow_drop_down),
      decoration: const InputDecoration(
        labelText: 'Filter by plant',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All plants')),
        ..._plants.map(
          (plant) => DropdownMenuItem<String>(
            value: plant.plantId,
            child: Text(plant.plantName),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() {
          _selectedPlantId = value;
        });
        _loadData();
      },
    );
  }

  Widget _buildEmployeeSelector(BuildContext context) {
    if (_employees.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          color: Colors.white,
        ),
        child: Column(
          children: [
            const Icon(Icons.people_outline, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No proxy-enabled employees found.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<ProxyEmployee>(
      value: _selectedEmployee,
      decoration: const InputDecoration(
        labelText: 'Select employee',
        border: OutlineInputBorder(),
      ),
      items: _employees
          .map(
            (employee) => DropdownMenuItem<ProxyEmployee>(
              value: employee,
              child: Text('${employee.fullName} (${employee.roleBadge})'),
            ),
          )
          .toList(),
      onChanged: (employee) {
        setState(() => _selectedEmployee = employee);
      },
    );
  }

  Widget _buildEmployeeSummary(BuildContext context, ProxyEmployee employee) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.blueGrey.shade100,
                child: Text(
                  employee.fullName.isNotEmpty
                      ? employee.fullName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee.roleBadge,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee.plantName ?? 'Plant not mapped',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(employee.statusLabel),
                backgroundColor: employee.hasOpenShift
                    ? Colors.orange.shade100
                    : Colors.green.shade100,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetric(
                  context,
                  label: 'Last check-in',
                  value: employee.lastCheckInDisplay(_dateFormatter),
                  icon: Icons.login,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetric(
                  context,
                  label: 'Last check-out',
                  value: employee.lastCheckOutDisplay(_dateFormatter),
                  icon: Icons.logout,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        color: Colors.blueGrey.withOpacity(0.05),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.blueGrey),
                ),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ProxyEmployee employee) {
    final bool isSelf = _isSelf(employee);
    if (isSelf) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blueGrey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You are viewing your own profile. Proxy actions are disabled for self.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    if (employee.attendanceCompleted) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
          color: Colors.green.shade50,
        ),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, color: Colors.green.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Attendance already completed for today.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (!_isSubmitting && !employee.hasOpenShift)
                ? () => _submit('check_in')
                : null,
            icon: _isSubmitting && !employee.hasOpenShift
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('Check-in'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (!_isSubmitting && employee.hasOpenShift)
                ? () => _submit('check_out')
                : null,
            icon: _isSubmitting && employee.hasOpenShift
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: const Text('Check-out'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        color: Colors.white.withOpacity(0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueGrey.shade600),
              const SizedBox(width: 8),
              Text(
                'Proxy check-in guidelines',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Use this module to record attendance on behalf of employees who do not carry a mobile device. '
            'These entries will be tagged as proxy submissions for audit purposes.',
          ),
        ],
      ),
    );
  }

  bool _isSelf(ProxyEmployee employee) {
    final driverId = widget.user.driverId;
    if (driverId != null && driverId.isNotEmpty) {
      return driverId == employee.driverId;
    }
    return widget.user.id == employee.userId;
  }
}
