import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/app_user.dart';
import '../../core/models/document_models.dart';
import '../../core/services/documents_repository.dart';
import 'document_file_helper_stub.dart'
    if (dart.library.io) 'document_file_helper_io.dart'
    as doc_helper;
import 'document_preview_screen.dart';

class DocumentsHubScreen extends StatefulWidget {
  const DocumentsHubScreen({required this.user, this.initialData, super.key});

  final AppUser user;
  final DocumentOverviewData? initialData;

  @override
  State<DocumentsHubScreen> createState() => _DocumentsHubScreenState();
}

class _DocumentsHubScreenState extends State<DocumentsHubScreen> {
  final DocumentsRepository _repository = DocumentsRepository();

  DocumentOverviewData? _data;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    if (_data == null) {
      _loadData();
    } else {
      // Refresh silently to ensure we show the latest snapshot.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadData(refreshOnly: true);
      });
    }
  }

  Future<void> _loadData({bool refreshOnly = false}) async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
      if (!refreshOnly) {
        _error = null;
      }
    });
    try {
      final fresh = await _repository.fetchOverview(userId: widget.user.id);
      if (!mounted) return;
      setState(() {
        _data = fresh;
      });
    } on DocumentFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
      });
      if (!refreshOnly) {
        _showSnackBar(failure.message);
      }
    } catch (_) {
      if (!mounted) return;
      const fallbackMessage = 'Unable to load documents. Please try again.';
      setState(() {
        _error = fallbackMessage;
      });
      if (!refreshOnly) {
        _showSnackBar(fallbackMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleRefresh() => _loadData(refreshOnly: true);

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      if (_isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Documents'),
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'No document data available.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_data);
        return false;
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () {
                Navigator.of(context).pop(_data);
              },
            ),
            title: const Text('Documents'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Vehicle Docs'),
                Tab(text: 'Driver Docs'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Status legend',
                onPressed: _showLegend,
              ),
            ],
          ),
          body: TabBarView(
            children: [
              _VehicleDocsView(
                data: data,
                repository: _repository,
                onRefresh: _handleRefresh,
              ),
              _DriverDocsView(
                data: data,
                repository: _repository,
                user: widget.user,
                onRefresh: _handleRefresh,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLegend() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Status Legend'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _LegendRow(
                color: Color(0xFF90EE90),
                label: 'Active',
                description: 'Expiry date more than 30 days away or not set.',
              ),
              SizedBox(height: 12),
              _LegendRow(
                color: Color(0xFFFFE29A),
                label: 'Due Soon',
                description: 'Expires within the next 30 days.',
              ),
              SizedBox(height: 12),
              _LegendRow(
                color: Color(0xFFEF5350),
                label: 'Expired',
                description: 'Expiry date already passed.',
              ),
              SizedBox(height: 12),
              _LegendRow(
                color: Color(0xFFFFF176),
                label: 'Not Applicable',
                description: 'Document does not require an expiry date.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _VehicleDocsView extends StatefulWidget {
  const _VehicleDocsView({
    required this.data,
    required this.repository,
    required this.onRefresh,
  });

  final DocumentOverviewData data;
  final DocumentsRepository repository;
  final Future<void> Function() onRefresh;

  @override
  State<_VehicleDocsView> createState() => _VehicleDocsViewState();
}

class _VehicleDocsViewState extends State<_VehicleDocsView> {
  int? _selectedPlantId;
  int? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
  }

  @override
  void didUpdateWidget(covariant _VehicleDocsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _initializeSelection(notifyListeners: true);
    }
  }

  void _initializeSelection({bool notifyListeners = false}) {
    final plants = widget.data.filters.plants;
    if (plants.isNotEmpty) {
      _selectedPlantId ??= plants.first.plantId;
    }
    final vehicles = _filteredVehiclesForPlant(_selectedPlantId);
    if (vehicles.isNotEmpty) {
      final vehicleIds = vehicles.map((vehicle) => vehicle.vehicleId).toSet();
      if (_selectedVehicleId == null ||
          !vehicleIds.contains(_selectedVehicleId)) {
        _selectedVehicleId = vehicles.first.vehicleId;
      }
    } else {
      _selectedVehicleId = null;
    }
    if (notifyListeners && mounted) {
      setState(() {});
    }
  }

  List<DocumentVehicle> _filteredVehiclesForPlant(int? plantId) {
    final vehicles = widget.data.vehicles;
    if (plantId == null) {
      return vehicles;
    }
    return vehicles
        .where((vehicle) => vehicle.plantId == plantId)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPlantSelector(context),
          const SizedBox(height: 12),
          _buildVehicleSelector(context),
          const SizedBox(height: 16),
          _buildVehicleSummaryChip(context),
          const SizedBox(height: 16),
          _buildVehicleDocuments(context),
        ],
      ),
    );
  }

  Widget _buildPlantSelector(BuildContext context) {
    final plants = widget.data.filters.plants;
    return DropdownButtonFormField<int>(
      value: plants.any((plant) => plant.plantId == _selectedPlantId)
          ? _selectedPlantId
          : null,
      decoration: const InputDecoration(
        labelText: 'Plant',
        border: OutlineInputBorder(),
      ),
      items: plants
          .map(
            (plant) => DropdownMenuItem<int>(
              value: plant.plantId,
              child: Text(plant.plantName),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          _selectedPlantId = value;
          final vehicles = _filteredVehiclesForPlant(_selectedPlantId);
          if (vehicles.isNotEmpty) {
            _selectedVehicleId = vehicles.first.vehicleId;
          } else {
            _selectedVehicleId = null;
          }
        });
      },
    );
  }

  Widget _buildVehicleSelector(BuildContext context) {
    final vehicles = _filteredVehiclesForPlant(_selectedPlantId);
    if (vehicles.isEmpty) {
      return DropdownButtonFormField<int>(
        value: null,
        items: const [],
        decoration: const InputDecoration(
          labelText: 'Vehicle',
          border: OutlineInputBorder(),
        ),
        onChanged: null,
        hint: const Text('No vehicles for this plant'),
      );
    }
    return DropdownButtonFormField<int>(
      value: vehicles.any((vehicle) => vehicle.vehicleId == _selectedVehicleId)
          ? _selectedVehicleId
          : vehicles.first.vehicleId,
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
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          _selectedVehicleId = value;
        });
      },
    );
  }

  Widget _buildVehicleSummaryChip(BuildContext context) {
    final vehicleCounts = widget.data.vehicleCounts;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusChip(
          color: const Color(0xFF90EE90),
          label: 'Active',
          value: vehicleCounts.active,
        ),
        _StatusChip(
          color: Colors.amber.shade300,
          label: 'Due Soon',
          value: vehicleCounts.dueSoon,
        ),
        _StatusChip(
          color: const Color(0xFFEF5350),
          label: 'Expired',
          value: vehicleCounts.expired,
        ),
        _StatusChip(
          color: const Color(0xFFFFF176),
          label: 'Not Applicable',
          value: vehicleCounts.notApplicable,
        ),
      ],
    );
  }

  Widget _buildVehicleDocuments(BuildContext context) {
    final vehicle = widget.data.vehicleById(_selectedVehicleId);
    if (vehicle == null) {
      return const _PlaceholderCard(
        icon: Icons.directions_car,
        message: 'Select a vehicle to view its documents.',
      );
    }
    if (vehicle.documents.isEmpty) {
      return const _PlaceholderCard(
        icon: Icons.folder_open,
        message: 'No documents for this vehicle.',
      );
    }

    return Column(
      children: vehicle.documents
          .map(
            (document) => _DocumentCard(
              document: document,
              subjectLabel:
                  'Vehicle: ${vehicle.vehicleNumber} • Plant: ${vehicle.plantName}',
              repository: widget.repository,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DriverDocsView extends StatefulWidget {
  const _DriverDocsView({
    required this.data,
    required this.repository,
    required this.user,
    required this.onRefresh,
  });

  final DocumentOverviewData data;
  final DocumentsRepository repository;
  final AppUser user;
  final Future<void> Function() onRefresh;

  @override
  State<_DriverDocsView> createState() => _DriverDocsViewState();
}

class _DriverDocsViewState extends State<_DriverDocsView> {
  int? _selectedPlantId;
  int? _selectedDriverId;
  String? _selectedRole;
  late final bool _restrictToSelf;
  int? _selfDriverId;

  @override
  void initState() {
    super.initState();
    _restrictToSelf = false;
    _selfDriverId = null;
    _initializeSelection();
  }

  @override
  void didUpdateWidget(covariant _DriverDocsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _initializeSelection(notifyListeners: true);
    }
  }

  void _initializeSelection({bool notifyListeners = false}) {
    if (_restrictToSelf && _selfDriverId != null) {
      _selectedDriverId = _selfDriverId;
      final driver = widget.data.driverById(_selectedDriverId);
      _selectedPlantId = driver?.plantId;
    } else {
      final plants = widget.data.filters.plants;
      if (plants.isNotEmpty) {
        _selectedPlantId ??= plants.first.plantId;
      }
    }

    _syncDriverSelection();
    if (notifyListeners && mounted) {
      setState(() {});
    }
  }

  void _syncDriverSelection() {
    final drivers = _filteredDrivers();
    if (_restrictToSelf && _selfDriverId != null) {
      _selectedDriverId = _selfDriverId;
      return;
    }
    if (drivers.isNotEmpty) {
      final ids = drivers.map((driver) => driver.driverId).toSet();
      if (_selectedDriverId == null || !ids.contains(_selectedDriverId)) {
        _selectedDriverId = drivers.first.driverId;
      }
    } else {
      _selectedDriverId = null;
    }
  }

  List<DocumentDriver> _filteredDrivers() {
    final lowerRole = _selectedRole?.toLowerCase();
    final drivers = widget.data.drivers
        .where((driver) {
          final matchesPlant =
              _selectedPlantId == null || driver.plantId == _selectedPlantId;
          final matchesRole =
              lowerRole == null || lowerRole.isEmpty || lowerRole == 'all'
              ? true
              : driver.role.toLowerCase() == lowerRole;
          return matchesPlant && matchesRole;
        })
        .toList(growable: false);

    drivers.sort(
      (a, b) =>
          a.driverName.toLowerCase().compareTo(b.driverName.toLowerCase()),
    );

    return drivers;
  }

  List<DocumentRecord> _filteredDocuments(DocumentDriver driver) {
    final docs = List<DocumentRecord>.from(driver.documents);
    docs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return docs;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSelectors(context),
          const SizedBox(height: 16),
          _buildDriverSummaryChip(context),
          const SizedBox(height: 16),
          _buildDriverDocuments(context),
        ],
      ),
    );
  }

  Widget _buildDriverSummaryChip(BuildContext context) {
    final counts = widget.data.driverCounts;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusChip(
          color: const Color(0xFF90EE90),
          label: 'Active',
          value: counts.active,
        ),
        _StatusChip(
          color: Colors.amber.shade300,
          label: 'Due Soon',
          value: counts.dueSoon,
        ),
        _StatusChip(
          color: const Color(0xFFEF5350),
          label: 'Expired',
          value: counts.expired,
        ),
        _StatusChip(
          color: const Color(0xFFFFF176),
          label: 'Not Applicable',
          value: counts.notApplicable,
        ),
      ],
    );
  }

  Widget _buildSelectors(BuildContext context) {
    final plants = widget.data.filters.plants;
    final drivers = _filteredDrivers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          value: plants.any((plant) => plant.plantId == _selectedPlantId)
              ? _selectedPlantId
              : null,
          decoration: const InputDecoration(
            labelText: 'Plant',
            border: OutlineInputBorder(),
          ),
          items: plants
              .map(
                (plant) => DropdownMenuItem<int>(
                  value: plant.plantId,
                  child: Text(plant.plantName),
                ),
              )
              .toList(growable: false),
          onChanged: _restrictToSelf
              ? null
              : (value) {
                  setState(() {
                    _selectedPlantId = value;
                    _syncDriverSelection();
                  });
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: drivers.any((driver) => driver.driverId == _selectedDriverId)
              ? _selectedDriverId
              : null,
          decoration: const InputDecoration(
            labelText: 'Driver',
            border: OutlineInputBorder(),
          ),
          items: drivers
              .map(
                (driver) => DropdownMenuItem<int>(
                  value: driver.driverId,
                  child: Text(driver.driverName),
                ),
              )
              .toList(growable: false),
          onChanged: _restrictToSelf
              ? null
              : (value) {
                  setState(() {
                    _selectedDriverId = value;
                  });
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _selectedRole,
          decoration: const InputDecoration(
            labelText: 'Role',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All roles'),
            ),
            ...widget.data.filters.roles.map(
              (role) => DropdownMenuItem<String?>(
                value: role,
                child: Text(role[0].toUpperCase() + role.substring(1)),
              ),
            ),
          ],
          onChanged: _restrictToSelf
              ? null
              : (value) {
                  setState(() {
                    _selectedRole = value;
                    _syncDriverSelection();
                  });
                },
        ),
      ],
    );
  }

  Widget _buildDriverDocuments(BuildContext context) {
    final driver = widget.data.driverById(_selectedDriverId);
    if (driver == null) {
      return const _PlaceholderCard(
        icon: Icons.person_outline,
        message: 'Select a driver to view documents.',
      );
    }

    final documents = _filteredDocuments(driver);
    if (documents.isEmpty) {
      return const _PlaceholderCard(
        icon: Icons.folder_open,
        message: 'No documents for this driver.',
      );
    }

    return Column(
      children: documents
          .map(
            (document) => _DocumentCard(
              document: document,
              subjectLabel:
                  'Driver: ${driver.driverName} • Plant: ${driver.plantName}',
              repository: widget.repository,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.subjectLabel,
    required this.repository,
  });

  final DocumentRecord document;
  final String subjectLabel;
  final DocumentsRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiryLabel = _expiryLabel(document);
    final statusLine = document.status == DocumentStatus.notApplicable
        ? document.statusLabel
        : '${document.statusLabel} • $expiryLabel';
    final hasDocumentLink =
        document.googleDriveLink != null &&
        document.googleDriveLink!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _cardColor(document.status, theme),
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(subjectLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Type: ${document.type}',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                _StatusIndicator(status: document.status, label: statusLine),
              ],
            ),
            const SizedBox(height: 12),
            if (hasDocumentLink)
              Wrap(
                spacing: 12,
                children: [
                  _PrimaryActionButton(
                    icon: Icons.visibility,
                    label: 'Preview',
                    onPressed: () => _openPreview(context),
                  ),
                  _ShareIconButton(onPressed: () => _share(context)),
                ],
              )
            else
              Text(
                'Document link not available.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            if (document.notes != null && document.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(document.notes!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openPreview(BuildContext context) async {
    final uri = repository.bestDocumentUri(document);
    if (uri == null) {
      _showMissingLinkSnackBar(context);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          DocumentPreviewSheet(title: document.name, initialUri: uri),
    );
  }

  Future<void> _share(BuildContext context) async {
    final result = await doc_helper.DocumentFileHelper.download(
      document,
      repository,
    );

    if (!context.mounted) {
      return;
    }

    if (result == null) {
      _showMissingLinkSnackBar(
        context,
        customMessage: 'Unable to prepare file for sharing on this platform.',
      );
      return;
    }

    await Share.shareXFiles([
      XFile(result.path, mimeType: result.mimeType, name: result.fileName),
    ], subject: document.name);
  }

  void _showMissingLinkSnackBar(
    BuildContext context, {
    String customMessage = 'No link available for this document.',
  }) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(customMessage)));
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF03A9F4),
        foregroundColor: Colors.white,
        textStyle: Theme.of(context).textTheme.labelLarge,
      ),
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _ShareIconButton extends StatelessWidget {
  const _ShareIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF03A9F4),
        foregroundColor: Colors.white,
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.share),
      tooltip: 'Share',
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(
        '$label: ${value.toString().padLeft(2, '0')}',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status, this.label});

  final DocumentStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(status, theme);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 4),
        if (label != null) Text(label!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.description,
  });

  final Color color;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(description, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _expiryLabel(DocumentRecord document) {
  if (document.status == DocumentStatus.notApplicable) {
    return 'Not Applicable';
  }
  final date = document.expiryDate;
  if (date == null) {
    return '—';
  }
  return DateFormat('d MMM yyyy').format(date);
}

Color _cardColor(DocumentStatus status, ThemeData theme) {
  switch (status) {
    case DocumentStatus.active:
      return const Color(0xFF90EE90);
    case DocumentStatus.dueSoon:
      return Colors.amber.shade100;
    case DocumentStatus.expired:
      return const Color(0xFFEF5350);
    case DocumentStatus.notApplicable:
      return const Color(0xFFFFF176);
  }
}

Color _statusColor(DocumentStatus status, ThemeData theme) {
  switch (status) {
    case DocumentStatus.active:
      return const Color(0xFF689F38);
    case DocumentStatus.dueSoon:
      return Colors.amber.shade700;
    case DocumentStatus.expired:
      return const Color(0xFFD32F2F);
    case DocumentStatus.notApplicable:
      return const Color(0xFFFBC02D);
  }
}
