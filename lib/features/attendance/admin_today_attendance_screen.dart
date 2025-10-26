import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/supervisor_today_attendance.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../dashboard/widgets/admin_today_attendance_list.dart';

class AdminTodayAttendanceScreen extends StatefulWidget {
  const AdminTodayAttendanceScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AdminTodayAttendanceScreen> createState() =>
      _AdminTodayAttendanceScreenState();
}

class _AdminTodayAttendanceScreenState
    extends State<AdminTodayAttendanceScreen> {
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  bool _isLoading = false;
  String? _errorMessage;
  List<SupervisorTodayAttendancePlant> _plants =
      const <SupervisorTodayAttendancePlant>[];
  List<_PlantOption> _plantOptions = const <_PlantOption>[];
  String? _selectedPlantId;
  String _selectedPlantLabel = 'All Plants';

  @override
  void initState() {
    super.initState();
    _loadTodayAttendance();
  }

  Future<void> _loadTodayAttendance({
    bool silent = false,
    String? plantIdOverride,
  }) async {
    final plantId = plantIdOverride ?? _selectedPlantId;
    setState(() {
      _isLoading = true;
      if (!silent) {
        _errorMessage = null;
      }
    });
    try {
      final response = await _attendanceRepository.fetchAdminTodayAttendance(
        plantId: plantId,
      );
      if (!mounted) return;
      setState(() {
        _plants = response;
        _errorMessage = null;
        if (plantId == null) {
          _plantOptions = _buildPlantOptions(response);
        } else {
          _plantOptions = _addOptionIfMissing(_plantOptions, response, plantId);
        }
        _selectedPlantLabel = _resolvePlantLabel(_selectedPlantId);
      });
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
      if (!silent) {
        showAppToast(context, error.message, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      const fallback = "Unable to load today's attendance.";
      setState(() {
        _errorMessage = fallback;
      });
      if (!silent) {
        showAppToast(context, fallback, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() => _loadTodayAttendance(silent: true);

  List<_PlantOption> _buildPlantOptions(
    List<SupervisorTodayAttendancePlant> plants,
  ) {
    final seen = <String>{};
    final options = <_PlantOption>[];
    for (final plant in plants) {
      final id = plant.plantId.toString();
      if (seen.add(id)) {
        options.add(_PlantOption(id: id, name: _plantDisplayName(plant)));
      }
    }
    options.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return options;
  }

  List<_PlantOption> _addOptionIfMissing(
    List<_PlantOption> existing,
    List<SupervisorTodayAttendancePlant> plants,
    String plantId,
  ) {
    if (existing.any((option) => option.id == plantId)) {
      return existing;
    }
    String name = 'Plant #$plantId';
    for (final plant in plants) {
      if (plant.plantId.toString() == plantId) {
        name = _plantDisplayName(plant);
        break;
      }
    }
    final updated = List<_PlantOption>.from(existing)
      ..add(_PlantOption(id: plantId, name: name))
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return updated;
  }

  String _plantDisplayName(SupervisorTodayAttendancePlant plant) {
    final name = plant.plantName.trim();
    if (name.isEmpty) {
      return 'Plant #${plant.plantId}';
    }
    return name;
  }

  String _resolvePlantLabel(String? plantId) {
    if (plantId == null) {
      return 'All Plants';
    }
    for (final option in _plantOptions) {
      if (option.id == plantId) {
        return option.name;
      }
    }
    return 'Plant #$plantId';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat('dd MMM yyyy').format(DateTime.now());
    final showFilter = _plantOptions.isNotEmpty || _selectedPlantId != null;
    final Widget? plantFilterWidget = showFilter
        ? Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Filter by plant',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedPlantId,
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Plants'),
                          ),
                          ..._plantOptions.map(
                            (option) => DropdownMenuItem<String?>(
                              value: option.id,
                              child: Text(option.name),
                            ),
                          ),
                        ],
                        onChanged: _isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedPlantId = value;
                                  _selectedPlantLabel = _resolvePlantLabel(
                                    value,
                                  );
                                });
                                _loadTodayAttendance(plantIdOverride: value);
                              },
                      ),
                    ),
                  ),
                ),
                if (_selectedPlantId != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear filter',
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _selectedPlantId = null;
                              _selectedPlantLabel = 'All Plants';
                            });
                            _loadTodayAttendance();
                          },
                  ),
              ],
            ),
          )
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF00296B),
        foregroundColor: Colors.white,
        title: const Text(
          'Today Attendance',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => _loadTodayAttendance(),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (plantFilterWidget != null) plantFilterWidget,
              Text(
                'Admin overview for $dateLabel',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Showing $_selectedPlantLabel • pull down to refresh.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              AdminTodayAttendanceList(
                isLoading: _isLoading,
                errorMessage: _errorMessage,
                plants: _plants,
                onRetry: () => _loadTodayAttendance(),
                emptyMessage:
                    'No attendance records for $_selectedPlantLabel today.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantOption {
  const _PlantOption({required this.id, required this.name});

  final String id;
  final String name;
}
