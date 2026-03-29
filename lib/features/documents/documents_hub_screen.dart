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

// ─── Premium Design Tokens ───
const Color _gradientStart = Color(0xFF0A1628);
const Color _gradientEnd = Color(0xFF1B3A5C);
const Color _gradientMid = Color(0xFF0D4F6B);
const Color _accentTeal = Color(0xFF00BFA6);
const Color _accentGold = Color(0xFFD4A843);
const Color _surfaceBg = Color(0xFFF0F4F8);
const Color _surfaceCard = Color(0xFFF8FAFF);
const Color _heroGreen = Color(0xFF7CFFB2);
const Color _heroRed = Color(0xFFFF7C7C);

class DocumentsHubScreen extends StatefulWidget {
  const DocumentsHubScreen({required this.user, this.initialData, super.key});

  final AppUser user;
  final DocumentOverviewData? initialData;

  @override
  State<DocumentsHubScreen> createState() => _DocumentsHubScreenState();
}

class _DocumentsHubScreenState extends State<DocumentsHubScreen>
    with TickerProviderStateMixin {
  final DocumentsRepository _repository = DocumentsRepository();

  DocumentOverviewData? _data;
  bool _isLoading = false;
  String? _error;

  late final AnimationController _heroController;
  late final AnimationController _staggerController;
  late final Animation<double> _heroFade;
  late final Animation<double> _heroScale;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFade = CurvedAnimation(parent: _heroController, curve: Curves.easeOut);
    _heroScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _heroController, curve: Curves.easeOutBack),
    );

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (_data == null) {
      _loadData();
    } else {
      _startAnimations();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadData(refreshOnly: true);
      });
    }
  }

  void _startAnimations() {
    _heroController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _heroController.dispose();
    _staggerController.dispose();
    super.dispose();
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
      _startAnimations();
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
        return Scaffold(
          backgroundColor: _surfaceBg,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_gradientStart, _surfaceBg],
                stops: [0.0, 0.4],
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: _accentTeal),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: _surfaceBg,
        appBar: AppBar(
          title: const Text('Documents', style: TextStyle(color: Colors.white)),
          backgroundColor: _gradientEnd,
          foregroundColor: Colors.white,
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.folder_off,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'No document data available.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6C7A8F),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_gradientStart, _accentTeal],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _loadData,
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
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
          backgroundColor: _surfaceBg,
          body: NestedScrollView(
            physics: const BouncingScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  pinned: true,
                  centerTitle: true,
                  expandedHeight: 280,
                  backgroundColor: _gradientEnd,
                  surfaceTintColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  iconTheme: const IconThemeData(color: Colors.white),
                  leading: IconButton(
                    onPressed: () => Navigator.of(context).pop(_data),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  title: const Text(
                    'Documents',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      tooltip: 'Status legend',
                      onPressed: _showLegend,
                    ),
                    const SizedBox(width: 4),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_gradientStart, _gradientEnd, _gradientMid],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 56),
                          child: FadeTransition(
                            opacity: _heroFade,
                            child: ScaleTransition(
                              scale: _heroScale,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [_buildHeroCard(data)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surfaceBg,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: TabBar(
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        labelColor: _gradientStart,
                        unselectedLabelColor: Colors.grey.shade500,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        indicatorColor: _accentTeal,
                        indicatorWeight: 3,
                        tabs: const [
                          Tab(
                            height: 46,
                            iconMargin: EdgeInsets.only(bottom: 1),
                            icon: Icon(Icons.local_shipping_outlined, size: 16),
                            text: 'Vehicle Docs',
                          ),
                          Tab(
                            height: 46,
                            iconMargin: EdgeInsets.only(bottom: 1),
                            icon: Icon(Icons.person_outline_rounded, size: 16),
                            text: 'Driver Docs',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              children: [
                _VehicleDocsView(
                  data: data,
                  repository: _repository,
                  onRefresh: _handleRefresh,
                  staggerController: _staggerController,
                ),
                _DriverDocsView(
                  data: data,
                  repository: _repository,
                  user: widget.user,
                  onRefresh: _handleRefresh,
                  staggerController: _staggerController,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(DocumentOverviewData data) {
    final total = data.totalCounts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accentTeal, _heroGreen],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Document Overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${total.total} total documents tracked',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroStatBadge(
                label: 'Active',
                value: total.active.toString(),
                color: _heroGreen,
              ),
              const SizedBox(width: 8),
              _HeroStatBadge(
                label: 'Due Soon',
                value: total.dueSoon.toString(),
                color: const Color(0xFFFBBF24),
              ),
              const SizedBox(width: 8),
              _HeroStatBadge(
                label: 'Expired',
                value: total.expired.toString(),
                color: _heroRed,
              ),
              const SizedBox(width: 8),
              _HeroStatBadge(
                label: 'N/A',
                value: total.notApplicable.toString(),
                color: const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLegend() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_gradientStart, _accentTeal],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Status Legend',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _PremiumLegendRow(
                color: Color(0xFF10B981),
                label: 'Active',
                description: 'Expiry date more than 30 days away or not set.',
              ),
              SizedBox(height: 12),
              _PremiumLegendRow(
                color: Color(0xFFF59E0B),
                label: 'Due Soon',
                description: 'Expires within the next 30 days.',
              ),
              SizedBox(height: 12),
              _PremiumLegendRow(
                color: Color(0xFFEF4444),
                label: 'Expired',
                description: 'Expiry date already passed.',
              ),
              SizedBox(height: 12),
              _PremiumLegendRow(
                color: Color(0xFF9CA3AF),
                label: 'Not Applicable',
                description: 'Document does not require an expiry date.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: _accentTeal)),
            ),
          ],
        );
      },
    );
  }
}

// ─── Hero Stat Badge ───

class _HeroStatBadge extends StatelessWidget {
  const _HeroStatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vehicle Docs View ───

class _VehicleDocsView extends StatefulWidget {
  const _VehicleDocsView({
    required this.data,
    required this.repository,
    required this.onRefresh,
    required this.staggerController,
  });

  final DocumentOverviewData data;
  final DocumentsRepository repository;
  final Future<void> Function() onRefresh;
  final AnimationController staggerController;

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
      color: _accentTeal,
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          _buildPremiumSelector<int>(
            context,
            label: 'Plant',
            icon: Icons.factory_outlined,
            value: _selectedPlantId,
            items: widget.data.filters.plants
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
          ),
          const SizedBox(height: 10),
          _buildPremiumSelector<int>(
            context,
            label: 'Vehicle',
            icon: Icons.local_shipping_outlined,
            value:
                _filteredVehiclesForPlant(
                  _selectedPlantId,
                ).any((v) => v.vehicleId == _selectedVehicleId)
                ? _selectedVehicleId
                : null,
            items: _filteredVehiclesForPlant(_selectedPlantId)
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
          ),
          const SizedBox(height: 12),
          _buildStatusChips(widget.data.vehicleCounts),
          const SizedBox(height: 12),
          _buildVehicleDocuments(context),
        ],
      ),
    );
  }

  Widget _buildVehicleDocuments(BuildContext context) {
    final vehicle = widget.data.vehicleById(_selectedVehicleId);
    if (vehicle == null) {
      return _PremiumPlaceholder(
        icon: Icons.directions_car,
        message: 'Select a vehicle to view its documents.',
      );
    }
    if (vehicle.documents.isEmpty) {
      return _PremiumPlaceholder(
        icon: Icons.folder_open,
        message: 'No documents for this vehicle.',
      );
    }

    return Column(
      children: vehicle.documents
          .map(
            (document) => _PremiumDocumentCard(
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

// ─── Driver Docs View ───

class _DriverDocsView extends StatefulWidget {
  const _DriverDocsView({
    required this.data,
    required this.repository,
    required this.user,
    required this.onRefresh,
    required this.staggerController,
  });

  final DocumentOverviewData data;
  final DocumentsRepository repository;
  final AppUser user;
  final Future<void> Function() onRefresh;
  final AnimationController staggerController;

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
      color: _accentTeal,
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          _buildSelectors(context),
          const SizedBox(height: 12),
          _buildStatusChips(widget.data.driverCounts),
          const SizedBox(height: 12),
          _buildDriverDocuments(context),
        ],
      ),
    );
  }

  Widget _buildSelectors(BuildContext context) {
    final plants = widget.data.filters.plants;
    final drivers = _filteredDrivers();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPremiumSelector<int>(
          context,
          label: 'Plant',
          icon: Icons.factory_outlined,
          value: plants.any((plant) => plant.plantId == _selectedPlantId)
              ? _selectedPlantId
              : null,
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
        const SizedBox(height: 10),
        _buildPremiumSelector<int>(
          context,
          label: 'Driver',
          icon: Icons.person_outline_rounded,
          value: drivers.any((driver) => driver.driverId == _selectedDriverId)
              ? _selectedDriverId
              : null,
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
        const SizedBox(height: 10),
        _buildPremiumSelector<String?>(
          context,
          label: 'Role',
          icon: Icons.badge_outlined,
          value: _selectedRole,
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
      return _PremiumPlaceholder(
        icon: Icons.person_outline,
        message: 'Select a driver to view documents.',
      );
    }

    final documents = _filteredDocuments(driver);
    if (documents.isEmpty) {
      return _PremiumPlaceholder(
        icon: Icons.folder_open,
        message: 'No documents for this driver.',
      );
    }

    return Column(
      children: documents
          .map(
            (document) => _PremiumDocumentCard(
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

// ─── Premium Selector ───

Widget _buildPremiumSelector<T>(
  BuildContext context, {
  required String label,
  required IconData icon,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  ValueChanged<T?>? onChanged,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(
      color: _surfaceCard,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: _gradientStart.withOpacity(0.08)),
      boxShadow: [
        BoxShadow(
          color: _gradientStart.withOpacity(0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6C7A8F)),
        floatingLabelStyle: const TextStyle(
          fontSize: 12,
          color: Color(0xFF6C7A8F),
        ),
        prefixIcon: Icon(icon, size: 18, color: _gradientEnd),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      ),
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF12243A),
        fontWeight: FontWeight.w500,
      ),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 20,
        color: Color(0xFF6C7A8F),
      ),
      dropdownColor: Colors.white,
      items: items,
      onChanged: onChanged,
    ),
  );
}

// ─── Status Chips ───

Widget _buildStatusChips(DocumentCounts counts) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      _PremiumStatusChip(
        color: const Color(0xFF10B981),
        label: 'Active',
        value: counts.active,
      ),
      _PremiumStatusChip(
        color: const Color(0xFFF59E0B),
        label: 'Due Soon',
        value: counts.dueSoon,
      ),
      _PremiumStatusChip(
        color: const Color(0xFFEF4444),
        label: 'Expired',
        value: counts.expired,
      ),
      _PremiumStatusChip(
        color: const Color(0xFF9CA3AF),
        label: 'N/A',
        value: counts.notApplicable,
      ),
    ],
  );
}

// ─── Premium Document Card ───

class _PremiumDocumentCard extends StatelessWidget {
  const _PremiumDocumentCard({
    required this.document,
    required this.subjectLabel,
    required this.repository,
  });

  final DocumentRecord document;
  final String subjectLabel;
  final DocumentsRepository repository;

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _expiryLabel(document);
    final statusLine = document.status == DocumentStatus.notApplicable
        ? document.statusLabel
        : '${document.statusLabel} • $expiryLabel';
    final hasDocumentLink =
        document.googleDriveLink != null &&
        document.googleDriveLink!.isNotEmpty;
    final statusColor = _premiumStatusColor(document.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: _gradientStart.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _documentIcon(document.type),
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF12243A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subjectLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C7A8F),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.28)),
                ),
                child: Text(
                  document.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _gradientStart.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 14,
                  color: const Color(0xFF6C7A8F),
                ),
                const SizedBox(width: 6),
                Text(
                  'Type: ${document.type}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6C7A8F),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.schedule_outlined,
                  size: 14,
                  color: const Color(0xFF6C7A8F),
                ),
                const SizedBox(width: 4),
                Text(
                  expiryLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (hasDocumentLink)
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_gradientStart, _accentTeal],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openPreview(context),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.visibility_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _accentTeal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accentTeal.withOpacity(0.2)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _share(context),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(
                          Icons.share_outlined,
                          color: _accentTeal,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link_off, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    'Document link not available',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (document.notes != null && document.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _accentGold.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accentGold.withOpacity(0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_rounded, size: 14, color: _accentGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      document.notes!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF374151),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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

// ─── Premium Status Chip ───

class _PremiumStatusChip extends StatelessWidget {
  const _PremiumStatusChip({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ${value.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Premium Placeholder ───

class _PremiumPlaceholder extends StatelessWidget {
  const _PremiumPlaceholder({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gradientStart.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _gradientStart.withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: const Color(0xFF6C7A8F)),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6C7A8F),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Premium Legend Row ───

class _PremiumLegendRow extends StatelessWidget {
  const _PremiumLegendRow({
    required this.color,
    required this.label,
    required this.description,
  });

  final Color color;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF12243A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6C7A8F)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Helpers ───

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

Color _premiumStatusColor(DocumentStatus status) {
  switch (status) {
    case DocumentStatus.active:
      return const Color(0xFF10B981);
    case DocumentStatus.dueSoon:
      return const Color(0xFFF59E0B);
    case DocumentStatus.expired:
      return const Color(0xFFEF4444);
    case DocumentStatus.notApplicable:
      return const Color(0xFF9CA3AF);
  }
}

IconData _documentIcon(String type) {
  final lower = type.toLowerCase();
  if (lower.contains('insurance')) return Icons.security_rounded;
  if (lower.contains('license') || lower.contains('licence'))
    return Icons.credit_card_rounded;
  if (lower.contains('permit')) return Icons.assignment_rounded;
  if (lower.contains('fitness') || lower.contains('certificate'))
    return Icons.verified_rounded;
  if (lower.contains('tax')) return Icons.receipt_long_rounded;
  if (lower.contains('pollution') || lower.contains('puc'))
    return Icons.eco_rounded;
  if (lower.contains('rc') || lower.contains('registration'))
    return Icons.directions_car_rounded;
  return Icons.description_rounded;
}
