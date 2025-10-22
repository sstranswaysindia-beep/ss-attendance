import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/meter_reading_models.dart';
import '../../core/services/meter_reading_repository.dart';
import '../../core/widgets/app_toast.dart';

class MeterReadingSheet extends StatefulWidget {
  const MeterReadingSheet({super.key, required this.user});

  final AppUser user;

  @override
  State<MeterReadingSheet> createState() => _MeterReadingSheetState();
}

class _MeterReadingSheetState extends State<MeterReadingSheet> {
  final MeterReadingRepository _repository = MeterReadingRepository();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _readingController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  MeterStatusData? _status;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  int? _selectedPlantId;
  int? _selectedVehicleId;
  XFile? _photo;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _readingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final userId = int.tryParse(widget.user.id);
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _error = 'Invalid user ID';
      });
      return;
    }

    try {
      final status = await _repository.fetchStatus(userId: userId);
      _applyStatus(status);
    } catch (error) {
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  void _applyStatus(MeterStatusData status) {
    MeterPlantStatus? initialPlant;
    MeterVehicleStatus? initialVehicle;

    if (status.sections.isNotEmpty) {
      initialPlant = status.sections.firstWhere(
        (section) => section.vehicles.isNotEmpty,
        orElse: () => status.sections.first,
      );
      if (initialPlant.vehicles.isNotEmpty) {
        initialVehicle = initialPlant.vehicles.first;
      }
    }

    setState(() {
      _status = status;
      _isLoading = false;
      _error = null;
      _selectedPlantId = initialPlant?.plantId;
      _selectedVehicleId = initialVehicle?.vehicleId;
    });
  }

  List<MeterVehicleStatus> get _vehiclesForSelectedPlant {
    final status = _status;
    if (status == null) {
      return const [];
    }
    if (_selectedPlantId == null) {
      return status.sections.expand((section) => section.vehicles).toList();
    }
    final section = status.sections.firstWhere(
      (element) => element.plantId == _selectedPlantId,
      orElse: () => status.sections.isNotEmpty
          ? status.sections.first
          : const MeterPlantStatus(plantId: 0, plantName: '', vehicles: []),
    );
    return section.vehicles;
  }

  MeterVehicleStatus? get _selectedVehicle {
    final vehicleId = _selectedVehicleId;
    if (vehicleId == null) {
      return null;
    }
    for (final section in _status?.sections ?? const []) {
      for (final vehicle in section.vehicles) {
        if (vehicle.vehicleId == vehicleId) {
          return vehicle;
        }
      }
    }
    return null;
  }

  Future<void> _pickPhoto() async {
    try {
      final picture = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picture != null) {
        setState(() {
          _photo = picture;
        });
      }
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, 'Unable to capture photo: $error', isError: true);
    }
  }

  bool get _canSubmit {
    final status = _status;
    if (status == null || !status.window.isOpen) {
      return false;
    }
    if (_selectedVehicleId == null || _photo == null) {
      return false;
    }
    final value = double.tryParse(_readingController.text.trim());
    return value != null && value >= 0;
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    final status = _status;
    if (status == null) {
      return;
    }

    final userId = int.tryParse(widget.user.id);
    final driverId = int.tryParse(widget.user.driverId ?? widget.user.id);
    final vehicleId = _selectedVehicleId;
    final reading = double.tryParse(_readingController.text.trim());
    final photo = _photo;

    if (userId == null ||
        driverId == null ||
        vehicleId == null ||
        reading == null ||
        photo == null) {
      showAppToast(context, 'Please complete all fields', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final request = MeterReadingRequest(
        userId: userId,
        driverId: driverId,
        vehicleId: vehicleId,
        readingKm: reading,
        photoPath: photo.path,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      final updatedStatus = await _repository.submitReading(request);
      _readingController.clear();
      _notesController.clear();
      setState(() {
        _photo = null;
      });
      _applyStatus(updatedStatus);
      if (!mounted) return;
      showAppToast(context, 'Meter reading submitted');
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showHistory(MeterVehicleStatus vehicle) async {
    final userId = int.tryParse(widget.user.id);
    if (userId == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return FutureBuilder<List<MeterHistoryEntry>>(
          future: _repository.fetchHistory(
            userId: userId,
            vehicleId: vehicle.vehicleId,
            monthKey: _status?.monthKey,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load history: ${snapshot.error}'),
              );
            }
            final history = snapshot.data ?? const [];
            if (history.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No history yet for this vehicle'),
              );
            }
            final formatter = DateFormat('dd MMM, HH:mm');
            return SafeArea(
              top: false,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                itemBuilder: (context, index) {
                  final entry = history[index];
                  final submitted = entry.submittedAt != null
                      ? formatter.format(entry.submittedAt!.toLocal())
                      : '--';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Reading ${entry.readingKm.toStringAsFixed(1)} km',
                    ),
                    subtitle: Text(
                      'Submitted $submitted\nStatus: ${entry.status ?? 'pending'}',
                    ),
                    trailing: entry.photoUrl.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () {
                              Navigator.of(context).pop(entry.photoUrl);
                            },
                          )
                        : null,
                  );
                },
                separatorBuilder: (_, __) => const Divider(),
                itemCount: history.length,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _ErrorView(message: _error!, onRetry: _loadStatus)
              : _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final status = _status!;
    final sections = status.sections;
    final selectedVehicle = _selectedVehicle;
    final isSupervisor = widget.user.role == UserRole.supervisor;

    MeterPlantStatus? currentSection;
    if (selectedVehicle != null) {
      currentSection = sections.firstWhere(
        (section) => section.vehicles.any(
          (vehicle) => vehicle.vehicleId == selectedVehicle.vehicleId,
        ),
        orElse: () => sections.isNotEmpty
            ? sections.first
            : const MeterPlantStatus(plantId: 0, plantName: '', vehicles: []),
      );
    } else if (sections.isNotEmpty) {
      currentSection = sections.first;
    }

    final currentPlantName = currentSection?.plantName ?? '';
    final dropdownPlantId = _selectedPlantId ?? currentSection?.plantId;
    final vehicles = _vehiclesForSelectedPlant;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Monthly Meter Reading',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Month ${status.monthKey}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (!status.window.isOpen)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.window.reason ??
                          'Meter reading submission is only available on the last day of the month and the first day of the next month.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 16),
                if (isSupervisor) ...[
                  DropdownButtonFormField<int>(
                    value: dropdownPlantId,
                    decoration: const InputDecoration(
                      labelText: 'Plant',
                      border: OutlineInputBorder(),
                    ),
                    items: sections
                        .map(
                          (section) => DropdownMenuItem<int>(
                            value: section.plantId,
                            child: Text(
                              section.plantName.isEmpty
                                  ? 'Plant ${section.plantId}'
                                  : section.plantName,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPlantId = value;
                        final vehiclesForPlant = _vehiclesForSelectedPlant;
                        _selectedVehicleId = vehiclesForPlant.isNotEmpty
                            ? vehiclesForPlant.first.vehicleId
                            : null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  _FormField(
                    label: 'Plant',
                    child: Text(
                      currentPlantName.isEmpty
                          ? 'Auto-selected'
                          : currentPlantName,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<int>(
                  value: _selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle',
                    border: OutlineInputBorder(),
                  ),
                  items: vehicles
                      .map(
                        (vehicle) => DropdownMenuItem<int>(
                          value: vehicle.vehicleId,
                          child: Text(vehicle.vehicleNumber),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVehicleId = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _readingController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Odometer (km)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                _PhotoField(
                  photo: _photo,
                  onPick: _pickPhoto,
                  onClear: () => setState(() => _photo = null),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: !_isSubmitting && _canSubmit ? _submit : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit reading',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          sliver: SliverList.separated(
            itemBuilder: (context, index) {
              final section = status.sections[index];
              return _PlantSection(
                section: section,
                onViewHistory: _showHistory,
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemCount: status.sections.length,
          ),
        ),
      ],
    );
  }
}

class _PlantSection extends StatelessWidget {
  const _PlantSection({required this.section, required this.onViewHistory});

  final MeterPlantStatus section;
  final void Function(MeterVehicleStatus vehicle) onViewHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.plantName.isEmpty
              ? 'Plant ${section.plantId}'
              : section.plantName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...section.vehicles.map(
          (vehicle) =>
              _VehicleCard(vehicle: vehicle, onViewHistory: onViewHistory),
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.onViewHistory});

  final MeterVehicleStatus vehicle;
  final void Function(MeterVehicleStatus vehicle) onViewHistory;

  Color _statusColor() {
    switch (vehicle.status) {
      case 'submitted':
        return Colors.green.shade600;
      case 'late':
      case 'missed':
      case 'pending':
      default:
        return Colors.red.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd MMM, HH:mm');
    final submittedAt = vehicle.submittedAt != null
        ? formatter.format(vehicle.submittedAt!.toLocal())
        : 'Not submitted';
    final cardColor = vehicle.status == 'submitted'
        ? Colors.green.shade50
        : Colors.red.shade50;
    final borderColor = vehicle.status == 'submitted'
        ? Colors.green.shade300
        : Colors.red.shade300;
    final textColor = vehicle.status == 'submitted'
        ? Colors.green.shade900
        : Colors.red.shade900;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vehicle.vehicleNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                Chip(
                  label: Text(vehicle.statusLabel),
                  backgroundColor: _statusColor().withOpacity(0.15),
                  labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _statusColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reading: ${vehicle.formattedReading}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: textColor),
            ),
            Text(
              'Submitted: $submittedAt',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textColor.withOpacity(0.8),
              ),
            ),
            if (vehicle.driverName != null && vehicle.driverName!.isNotEmpty)
              Text(
                'Driver: ${vehicle.driverName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textColor.withOpacity(0.8),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onViewHistory(vehicle),
                icon: const Icon(Icons.history),
                label: const Text('View history'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.photo,
    required this.onPick,
    required this.onClear,
  });

  final XFile? photo;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Odometer photo', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_camera),
                label: Text(photo == null ? 'Capture photo' : 'Retake photo'),
              ),
            ),
            if (photo != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(photo!.path),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(24),
                          maximumSize: const Size.square(24),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.black87,
                        ),
                        onPressed: onClear,
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
