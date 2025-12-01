import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/admin_driver_master.dart';
import '../../core/models/app_user.dart';
import '../../core/models/trip_plant.dart';
import '../../core/models/trip_vehicle.dart';
import '../../core/services/admin_master_repository.dart';
import '../../core/services/safety_repository.dart';
import '../../core/services/trip_repository.dart';
import '../../core/widgets/app_toast.dart';

class SpotAuditWizardScreen extends StatefulWidget {
  const SpotAuditWizardScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<SpotAuditWizardScreen> createState() => _SpotAuditWizardScreenState();
}

class _SpotAuditWizardScreenState extends State<SpotAuditWizardScreen> {
  static const Color _noteFillColor = Color(0xFFFFF8C4);

  final TripRepository _tripRepository = TripRepository();
  final AdminMasterRepository _adminRepository = AdminMasterRepository();
  late final SafetyRepository _safetyRepository;
  final PageController _pageController = PageController();

  List<TripPlant> _plants = const [];
  List<TripVehicle> _vehicles = const [];
  List<AdminDriver> _drivers = const [];
  Map<int, List<TripVehicle>> _plantVehicles = <int, List<TripVehicle>>{};
  Map<int, List<AdminDriver>> _plantDrivers = <int, List<AdminDriver>>{};

  int? _selectedPlantId;
  String? _selectedVehicleId;
  int? _selectedDriverId;
  DateTime _assessmentDate = DateTime.now();
  String _truckCategory = 'VITT';
  final TextEditingController _highlightsController = TextEditingController();
  final Map<String, TextEditingController> _commentControllers = {};

  final Map<String, _SpotAuditSection> _sections = _buildSections();
  final Map<String, dynamic> _answers = {};
  final GlobalKey<FormState> _detailsFormKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isLoading = true;
  String? _loadingError;
  bool _isSubmitting = false;
  bool _isPrefetchingVehicles = false;

  @override
  void initState() {
    super.initState();
    _safetyRepository = SafetyRepository(currentUser: widget.user);
    _hydrate();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _highlightsController.dispose();
    for (final controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _hydrate() async {
    try {
      List<TripPlant> plants;
      List<AdminDriver> drivers = const [];
      Map<int, List<TripVehicle>> vehicleMap = <int, List<TripVehicle>>{};
      Map<int, List<AdminDriver>> driverMap = <int, List<AdminDriver>>{};

      try {
        final directory = await _safetyRepository.fetchPlantDirectory(user: widget.user);
        if (directory.isNotEmpty) {
          plants = directory
              .map((entry) => TripPlant(id: entry.id, name: entry.name))
              .toList(growable: false);
          final driverAccumulator = <int, AdminDriver>{};
          for (final entry in directory) {
            vehicleMap[entry.id] = entry.vehicles
                .map((vehicle) => TripVehicle(id: vehicle.id, number: vehicle.number))
                .where((vehicle) => vehicle.id > 0 && vehicle.number.isNotEmpty)
                .toList(growable: false);
            driverMap[entry.id] = entry.drivers
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
                .where((driver) => driver.id > 0 && driver.name.isNotEmpty)
                .toList(growable: false);
            for (final driver in driverMap[entry.id]!) {
              driverAccumulator[driver.id] = driver;
            }
          }
          drivers = driverAccumulator.values.toList(growable: false);
        } else {
          throw Exception('empty directory');
        }
      } catch (_) {
        plants = await _tripRepository.fetchPlantsForUser(widget.user);
        drivers = await _adminRepository.fetchDrivers(status: 'Active');
        vehicleMap = <int, List<TripVehicle>>{};
        driverMap = <int, List<AdminDriver>>{};
      }
      setState(() {
        _plants = plants;
        _drivers = drivers;
        if (vehicleMap.isNotEmpty) {
          _plantVehicles = vehicleMap;
        }
        if (driverMap.isNotEmpty) {
          _plantDrivers = driverMap;
        }
        _isPrefetchingVehicles = false;
        _isLoading = false;
      });
      if (plants.isNotEmpty) {
        final firstPlantId = plants.first.id;
        if (_selectedPlantId == null) {
          _selectedPlantId = firstPlantId;
        }
        if (isAdmin && _plantVehicles[firstPlantId] != null) {
          setState(() {
            _vehicles = _plantVehicles[firstPlantId]!;
          });
        } else {
          await _loadVehiclesForPlant(firstPlantId);
        }
      }
    } catch (error) {
      setState(() {
        _loadingError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVehiclesForPlant(int plantId) async {
    final cached = _plantVehicles[plantId];
    if (cached != null) {
      setState(() {
        _vehicles = cached;
        _selectedVehicleId = null;
      });
      return;
    }
    try {
      final vehicles = await _tripRepository.fetchVehiclesForPlant(
        user: widget.user,
        plantId: plantId.toString(),
      );
      setState(() {
        _vehicles = vehicles;
        _selectedVehicleId = null;
        final updated = Map<int, List<TripVehicle>>.from(_plantVehicles);
        updated[plantId] = vehicles;
        _plantVehicles = updated;
      });
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, 'Unable to load vehicles: $error', isError: true);
    }
  }

  List<AdminDriver> get _filteredDrivers {
    final plantId = _selectedPlantId;
    if (plantId != null) {
      final plantSpecific = _plantDrivers[plantId];
      if (plantSpecific != null && plantSpecific.isNotEmpty) {
        return plantSpecific;
      }
    }
    if (plantId == null) return _drivers;
    return _drivers
        .where((driver) => driver.plantId == plantId)
        .toList(growable: false);
  }

  bool get isAdmin => widget.user.role == UserRole.admin;

  int get _totalSteps => 2 + _sections.length;

  void _nextStep() {
    if (_currentStep == 0) {
      final isValid = _detailsFormKey.currentState?.validate() ?? false;
      if (!isValid) return;
    }
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep += 1);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep == 0) return;
    setState(() => _currentStep -= 1);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _setAnswer(String key, dynamic value) {
    setState(() {
      _answers[key] = value;
    });
  }

  Color _ratingColor(String option) {
    switch (option.toLowerCase()) {
      case 'average':
        return const Color(0xFFE53935);
      case 'good':
        return const Color(0xFFFBC02D);
      case 'very good':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF546E7A);
    }
  }

  int _sectionScore(String sectionKey) {
    final manual = _answers['${sectionKey}_manual_score'];
    if (manual is int) {
      return manual.clamp(0, 2);
    }
    final section = _sections[sectionKey];
    if (section == null) return 0;
    var total = 0;
    var count = 0;
    for (final question in section.questions) {
      final value = _answers[question.id];
      if (value is int) {
        total += value;
        count += 1;
      } else if (value is bool) {
        total += value ? 2 : 0;
        count += 1;
      }
    }
    if (count == 0) return 0;
    return (total / count).round();
  }

  int get _totalScore {
    var sum = 0;
    for (final key in _sections.keys) {
      sum += _sectionScore(key);
    }
    return sum;
  }

  TripVehicle? _selectedVehicleDetails() {
    final selectedId = int.tryParse(_selectedVehicleId ?? '');
    if (selectedId == null) return null;
    for (final vehicle in _vehicles) {
      if (vehicle.id == selectedId) {
        return vehicle;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _buildSectionSubmissions() {
    final submissions = <Map<String, dynamic>>[];
    _sections.forEach((key, section) {
      final answers = <Map<String, dynamic>>[];
      for (final question in section.questions) {
        final raw = _answers[question.id];
        if (raw == null) {
          continue;
        }
        if (question.type == SpotAuditQuestionType.rating) {
          final score = raw is int ? raw : -1;
          if (score < 0 || score >= question.ratingOptions.length) {
            continue;
          }
          answers.add({
            'question_key': question.id,
            'choice': question.ratingOptions[score],
            'score': score,
          });
        } else if (raw is bool) {
          answers.add({
            'question_key': question.id,
            'choice': raw ? 'Yes' : 'No',
            'score': raw ? 2 : 0,
          });
        }
      }
      final comment = _commentControllers[section.key]?.text.trim() ?? '';
      final manual = _answers['${section.key}_manual_score'];
      final sectionScore = manual is int ? manual : _sectionScore(section.key);
      submissions.add({
        'key': section.key,
        'label': section.titleEn,
        'score': sectionScore,
        'comment': comment,
        'answers': answers,
      });
    });
    return submissions;
  }

  Future<void> _submitAudit() async {
    if (_isSubmitting) return;

    final plantId = _selectedPlantId ?? 0;
    final driverId = _selectedDriverId ?? 0;
    final vehicle = _selectedVehicleDetails();
    if (plantId <= 0 || driverId <= 0 || vehicle == null) {
      showAppToast(context, 'Select plant, vehicle, and driver before submitting', isError: true);
      setState(() => _currentStep = 0);
      return;
    }

    final sectionsPayload = _buildSectionSubmissions();
    final localeCode = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final finalAction = _commentControllers['final_action']?.text.trim() ?? '';

    setState(() => _isSubmitting = true);
    try {
      final auditId = await _safetyRepository.submitSpotAudit(
        plantId: plantId,
        driverId: driverId,
        vehicleId: vehicle.id,
        vehicleNumber: vehicle.number,
        assessmentDate: _assessmentDate,
        truckCategory: _truckCategory,
        languageCode: localeCode,
        highlights: _highlightsController.text.trim(),
        assessedBy: widget.user.displayName,
        actionPlan: finalAction,
        sections: sectionsPayload,
      );
      if (!mounted) return;
      final successMessage = auditId > 0
          ? 'Spot audit submitted (ID #$auditId)'
          : 'Spot audit submitted successfully';
      showAppToast(context, successMessage);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      showAppToast(context, message.isEmpty ? 'Failed to submit audit' : message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadingError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Spot Audit')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Unable to load data',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                _loadingError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Spot Audit'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                'Step ${_currentStep + 1}/$_totalSteps',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildDetailsStep(theme),
                ..._sections.values.map(_buildSectionCard),
                _buildSummary(theme),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8BC34A),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _previousStep,
                      child: const Text('Previous'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _currentStep == _totalSteps - 1
                        ? (_isSubmitting ? null : _submitAudit)
                        : _nextStep,
                    child: _currentStep == _totalSteps - 1
                        ? (_isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Submit Audit'))
                        : const Text('Next Page'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep(ThemeData theme) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _detailsFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit Details',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
            _whiteDropdownTheme(
              context,
              DropdownButtonFormField<int>(
                value: _selectedPlantId,
                items: _plants
                    .map(
                      (plant) => DropdownMenuItem(
                        value: plant.id,
                        child: Text(plant.name),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Plant Name',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) =>
                    value == null ? 'Please select a plant' : null,
                onChanged: (value) {
                  setState(() {
                    _selectedPlantId = value;
                    _selectedDriverId = null;
                  });
                  if (value != null) {
                    _loadVehiclesForPlant(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _whiteDropdownTheme(
              context,
              DropdownButtonFormField<String>(
                value: _selectedVehicleId,
                items: _vehicles
                    .map(
                      (vehicle) => DropdownMenuItem(
                        value: vehicle.id.toString(),
                        child: Text(vehicle.number),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Vehicle Number',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) =>
                    value == null ? 'Please select a vehicle' : null,
                onChanged: (value) {
                  setState(() {
                    _selectedVehicleId = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            _whiteDropdownTheme(
              context,
              DropdownButtonFormField<int>(
                value: _selectedDriverId,
                items: _filteredDrivers
                    .map(
                      (driver) => DropdownMenuItem(
                        value: driver.id,
                        child: Text(driver.name),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Driver Name',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) =>
                    value == null ? 'Please select a driver' : null,
                onChanged: (value) {
                  setState(() {
                    _selectedDriverId = value;
                  });
                },
              ),
            ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of Assessment',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat('dd MMM yyyy').format(_assessmentDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _assessmentDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 7)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _assessmentDate = picked);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'SS Transways India',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Transporter Name',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                child: ToggleButtons(
                  isSelected:
                      ['VITT', 'PG'].map((value) => value == _truckCategory).toList(),
                  onPressed: (index) {
                    setState(() => _truckCategory = index == 0 ? 'VITT' : 'PG');
                  },
                  borderRadius: BorderRadius.circular(12),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('VITT Truck'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('PG Truck'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Highlights',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _highlightsController,
                decoration: InputDecoration(
                  hintText: 'Notable observations before audit begins',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: _noteFillColor,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildPlantOverview(ThemeData theme) {
    if (_plants.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plant / Vehicles / Drivers overview',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_isPrefetchingVehicles && _plantVehicles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Column(
            children: _plants.map((plant) {
              final vehicles = _plantVehicles[plant.id] ?? const <TripVehicle>[];
              final drivers = _plantDrivers[plant.id] ??
                  _drivers
                      .where((driver) => driver.plantId == plant.id)
                      .toList(growable: false);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plant.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Vehicles', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      vehicles.isEmpty
                          ? Text(
                              'No vehicles linked',
                              style: theme.textTheme.labelSmall,
                            )
                          : Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: vehicles
                                  .map(
                                    (vehicle) => Chip(
                                      label: Text(vehicle.number),
                                      backgroundColor: Colors.grey[200],
                                    ),
                                  )
                                  .toList(),
                            ),
                      const SizedBox(height: 8),
                      Text('Drivers', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      drivers.isEmpty
                          ? Text(
                              'No drivers linked',
                              style: theme.textTheme.labelSmall,
                            )
                          : Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: drivers
                                  .map(
                                    (driver) => Chip(
                                      label: Text(driver.name),
                                      backgroundColor: Colors.grey[100],
                                    ),
                                  )
                                  .toList(),
                            ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSectionCard(_SpotAuditSection section) {
    final theme = Theme.of(context);
    final commentController = _commentControllers.putIfAbsent(
      section.key,
      () => TextEditingController(),
    );
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.titleEn,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F2949),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.titleHi,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
                for (final question in section.questions) ...[
                  Text(
                    question.labelEn,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    question.labelHi,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (question.type == SpotAuditQuestionType.rating)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: question.ratingOptions.map((option) {
                        final selectedValue =
                            (_answers[question.id] as int?) ?? -1;
                        final score = question.ratingOptions.indexOf(option);
                        final selected = selectedValue == score;
                        final color = _ratingColor(option);
                        return _RatingBlock(
                          label: option,
                          baseColor: color,
                          selected: selected,
                          onTap: () => _setAnswer(question.id, score),
                        );
                      }).toList(),
                    )
                  else
                    Wrap(
                      spacing: 18,
                      children: ['Yes', 'No'].map((option) {
                        final value = option == 'Yes';
                        final selected = _answers[question.id] == value;
                        return _YesNoButton(
                          value: value,
                          selected: selected,
                          onTap: () => _setAnswer(question.id, value),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                ],
                if (section.guide.isNotEmpty) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guide', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(section.guide, style: theme.textTheme.bodySmall),
                        if (section.guideHi.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            section.guideHi,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Text(
                      'Marks',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('0')),
                        ButtonSegment(value: 1, label: Text('1')),
                        ButtonSegment(value: 2, label: Text('2')),
                      ],
                      selected: <int>{_sectionScore(section.key)},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        _setAnswer('${section.key}_manual_score', selection.first);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  decoration: InputDecoration(
                    labelText: 'Highlights / Comments',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: _noteFillColor,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('Total Score'),
                subtitle: const Text('Sum of individual sections'),
                trailing: Text(
                  '$_totalScore',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final section in _sections.values)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                title: Text(section.titleEn),
                subtitle: Text(
                  section.titleHi,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[600],
                  ),
                ),
                trailing: Text('${_sectionScore(section.key)} / 2'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentControllers.putIfAbsent(
                'final_action',
                () => TextEditingController(),
              ),
              decoration: InputDecoration(
                labelText: 'Assessed By / Highlights / Action Plan',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: _noteFillColor,
              ),
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }
}

enum SpotAuditQuestionType { rating, yesNo }

class _SpotAuditQuestion {
  const _SpotAuditQuestion({
    required this.id,
    required this.labelEn,
    required this.labelHi,
    required this.type,
    this.ratingOptions = const ['Average', 'Good', 'Very Good'],
  });

  final String id;
  final String labelEn;
  final String labelHi;
  final SpotAuditQuestionType type;
  final List<String> ratingOptions;
}

class _SpotAuditSection {
  const _SpotAuditSection({
    required this.key,
    required this.titleEn,
    required this.titleHi,
    required this.questions,
    this.guide = '',
    this.guideHi = '',
  });

  final String key;
  final String titleEn;
  final String titleHi;
  final List<_SpotAuditQuestion> questions;
  final String guide;
  final String guideHi;
}


class _RatingBlock extends StatelessWidget {
  const _RatingBlock({
    required this.label,
    required this.baseColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color baseColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 110,
        height: 36,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.black.withOpacity(0.7) : const Color(0xFF5E5E5E),
            width: selected ? 3 : 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: baseColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _YesNoButton extends StatelessWidget {
  const _YesNoButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final bool value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = value ? const Color(0xFF2E7D32) : const Color(0xFFE53935);
    final icon = value ? Icons.check : Icons.close;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black.withOpacity(0.6) : Colors.transparent,
            width: selected ? 3 : 0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

Widget _whiteDropdownTheme(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(
      canvasColor: Colors.white,
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: MaterialStatePropertyAll(Colors.white),
        ),
      ),
    ),
    child: child,
  );
}

Map<String, _SpotAuditSection> _buildSections() {
  final sections = <_SpotAuditSection>[
    _SpotAuditSection(
      key: 'personal_hygiene',
      titleEn: 'Section - Personal Hygiene',
      titleHi: 'व्यक्तिगत स्वच्छता',
      guide:
          'Ask driver to wear FRC.',
      guideHi: 'ड्राइवर को FRC पहनने के लिए कहें।',
      questions: const [
        _SpotAuditQuestion(
          id: 'tidy_uniform',
          labelEn: 'Tidy Uniform',
          labelHi: 'साफ यूनिफॉर्म',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'tidy_frc',
          labelEn: 'Tidy FRC (if applicable)',
          labelHi: 'साफ FRC (यदि लागू हो)',
          type: SpotAuditQuestionType.rating,
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'ppes',
      titleEn: 'PPEs',
      titleHi: 'पीपीई',
      guide:
          'Ask driver to show PPEs and check condition of fire extinguisher.',
      guideHi:
          'ड्राइवर से पीपीई दिखाने को कहें और फायर एक्सटिंग्विशर की स्थिति जांचें।',
      questions: const [
        _SpotAuditQuestion(
          id: 'ppe_condition',
          labelEn: 'Condition',
          labelHi: 'स्थिति',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'ppe_available',
          labelEn: 'Availability',
          labelHi: 'उपलब्धता',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
        _SpotAuditQuestion(
          id: 'fire_extinguisher',
          labelEn: 'Fire Extinguisher',
          labelHi: 'फायर एक्सटिंग्विशर',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'emergency_action',
      titleEn: 'Understanding of Emergency Action Plan',
      titleHi: 'आपातकालीन कार्रवाई योजना की समझ',
      guide: 'Interview him on any applicable scenario.',
      guideHi: 'किसी भी लागू स्थिति पर उससे प्रश्न करें।',
      questions: const [
        _SpotAuditQuestion(
          id: 'emergency_plan',
          labelEn: 'Understands emergency action plan',
          labelHi: 'आपातकालीन योजना की समझ',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'product_awareness',
      titleEn: 'Product Awareness',
      titleHi: 'उत्पाद की जानकारी',
      guide:
          'Interview driver on hazards and what to do in case of leakage or spillage.',
      guideHi:
          'ड्राइवर से उत्पाद के खतरों और रिसाव या फैलाव की स्थिति में क्या करना है, इस पर बात करें।',
      questions: const [
        _SpotAuditQuestion(
          id: 'product_awareness',
          labelEn: 'Understands product hazards',
          labelHi: 'उत्पाद खतरों की जानकारी',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'cabin_housekeeping',
      titleEn: 'Cabin Housekeeping',
      titleHi: 'केबिन की साफ-सफाई',
      guide:
          'Check functioning of seat belt and overall cleanliness.',
      guideHi:
          'सीट बेल्ट के संचालन और समग्र सफाई की जांच करें।',
      questions: const [
        _SpotAuditQuestion(
          id: 'housekeeping',
          labelEn: 'Overall Cleanliness',
          labelHi: 'सामान्य साफ-सफाई',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'seat_condition',
          labelEn: 'Condition of Seats',
          labelHi: 'सीटों की स्थिति',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'seat_belt',
          labelEn: 'Seat belts condition',
          labelHi: 'सीट बेल्ट की स्थिति',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'banned_substances',
          labelEn: 'Presence of banned substances',
          labelHi: 'प्रतिबंधित पदार्थ',
          type: SpotAuditQuestionType.rating,
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'valve_box',
      titleEn: 'Condition of Valve Box / PG Truck',
      titleHi: 'वाल्व बॉक्स / पीजी ट्रक की स्थिति',
      questions: const [
        _SpotAuditQuestion(
          id: 'valve_cleanliness',
          labelEn: 'Cleanliness of valve box',
          labelHi: 'वाल्व बॉक्स की साफ-सफाई',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'waste_presence',
          labelEn: 'Presence of waste material',
          labelHi: 'अपशिष्ट पदार्थों की उपस्थिति',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
        _SpotAuditQuestion(
          id: 'filling_accessories',
          labelEn: 'Availability of filling accessories',
          labelHi: 'भरने वाले उपकरण उपलब्ध',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'accessories',
      titleEn: 'Availability of Accessories',
      titleHi: 'सहायक उपकरणों की उपलब्धता',
      guide: 'Check listed items for availability and condition.',
      guideHi: 'सूचीबद्ध वस्तुओं की उपलब्धता और स्थिति जांचें।',
      questions: const [
        _SpotAuditQuestion(
          id: 'vitt_accessories',
          labelEn: 'VITT accessories (hose, nozzle, cones, etc.)',
          labelHi: 'VITT सहायक उपकरण',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
        _SpotAuditQuestion(
          id: 'pg_accessories',
          labelEn: 'PG Truck accessories',
          labelHi: 'पीजी ट्रक सहायक उपकरण',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'vehicle_condition',
      titleEn: 'Condition of Vehicle',
      titleHi: 'वाहन की स्थिति',
      questions: const [
        _SpotAuditQuestion(
          id: 'vehicle_cleanliness',
          labelEn: 'Vehicle Cleanliness',
          labelHi: 'वाहन की साफ-सफाई',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'damage_check',
          labelEn: 'No damage to SUPD/RUPD/mudguards',
          labelHi: 'कोई क्षति नहीं',
          type: SpotAuditQuestionType.rating,
        ),
        _SpotAuditQuestion(
          id: 'mirror_condition',
          labelEn: 'Condition of mirrors',
          labelHi: 'दर्पणों की स्थिति',
          type: SpotAuditQuestionType.rating,
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'trem',
      titleEn: 'Availability of TREM card and EIP',
      titleHi: 'TREM कार्ड और EIP की उपलब्धता',
      guide: 'Driver should quickly produce TREM card.',
      guideHi: 'ड्राइवर को तुरंत TREM कार्ड दिखाना चाहिए।',
      questions: const [
        _SpotAuditQuestion(
          id: 'trem_card',
          labelEn: 'TREM card present',
          labelHi: 'TREM कार्ड उपलब्ध',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
    _SpotAuditSection(
      key: 'documents',
      titleEn: 'Availability of Documents',
      titleHi: 'दस्तावेजों की उपलब्धता',
      guide: 'All statutory and commercial documents should be available.',
      guideHi: 'सभी वैधानिक और व्यावसायिक दस्तावेज उपलब्ध होना चाहिए।',
      questions: const [
        _SpotAuditQuestion(
          id: 'statutory_docs',
          labelEn:
              'RC, Pollution, Insurance, PESO, Rule 18 & 19, DL, Hazardous Training Certificate',
          labelHi:
              'आरसी, प्रदूषण, बीमा, PESO, नियम 18/19, ड्राइविंग लाइसेंस, प्रशिक्षण प्रमाणपत्र',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
        _SpotAuditQuestion(
          id: 'pod_docs',
          labelEn: 'POD, Invoices',
          labelHi: 'POD, चालान',
          type: SpotAuditQuestionType.yesNo,
          ratingOptions: ['Yes', 'No'],
        ),
      ],
    ),
  ];

  return {
    for (final section in sections) section.key: section,
  };
}
