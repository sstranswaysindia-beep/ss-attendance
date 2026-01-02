import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/admin_driver_master.dart';
import '../../core/models/app_user.dart';
import '../../core/models/incab_models.dart';
import '../../core/models/safety_models.dart';
import '../../core/models/plant_directory.dart';
import '../../core/services/admin_master_repository.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';

class InCabAssessmentScreen extends StatefulWidget {
  const InCabAssessmentScreen({
    required this.user,
    required this.repository,
    super.key,
  });

  final AppUser user;
  final SafetyRepository repository;

  @override
  State<InCabAssessmentScreen> createState() => _InCabAssessmentScreenState();
}

class _InCabAssessmentScreenState extends State<InCabAssessmentScreen> {
  final PageController _pageController = PageController();
  final AdminMasterRepository _adminRepo = AdminMasterRepository();
  final Color _primaryColor = const Color(0xFF1C7ED6);
  final Color _backgroundTint = const Color(0xFFF6F9FF);

  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  late DateTime _startTime;

  final List<String> _sectionOrder = const [
    'pre_drive',
    'distance',
    'scanning',
    'braking',
  ];
  List<InCabSection> _sections = const [];
  List<PlantDirectoryEntry> _directory = const [];
  List<AdminDriver> _drivers = const [];
  final Map<String, String> _answers = {};

  bool _loading = true;
  bool _submitting = false;

  String? _driverId;
  int? _vehicleId;
  int? _plantId;
  int? _transporterPlantId;
  String? _transporter;
  String? _weather;
  String? _location;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _startTime = DateTime.now();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.fetchInCabQuestions(),
        widget.repository.fetchPlantDirectory(user: widget.user),
        _adminRepo.fetchDrivers(status: 'Active'),
      ]);
      setState(() {
        _sections = results[0] as List<InCabSection>;
        _directory = results[1] as List<PlantDirectoryEntry>;
        _drivers = results[2] as List<AdminDriver>;
        _transporter = 'SS TRANSWAYS INDIA';
        if (_plantId == null && _directory.isNotEmpty) {
          _plantId = _directory.first.id;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showAppToast(context, 'Failed to load data: $e', isError: true);
    }
  }

  void _next() {
    if (_step == 0 && !_validateInfo()) return;

    if (_step > 0 && _step <= _sectionOrder.length) {
      final key = _sectionOrder[_step - 1];
      if (!_validateSection(key)) return;
    }

    if (_step == 5 && !_validateNotes()) return;

    if (_step < 5) {
      setState(() => _step++);
      _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    }
  }

  bool _validateInfo() {
    if (_plantId == null) {
      showAppToast(context, 'Plant चुनें', isError: true);
      return false;
    }
    if (_vehicleId == null) {
      showAppToast(context, 'वाहन चुनें', isError: true);
      return false;
    }
    if (_driverId == null) {
      showAppToast(context, 'ड्राइवर चुनें', isError: true);
      return false;
    }
    if ((_transporter ?? '').trim().isEmpty) {
      showAppToast(context, 'Transporter आवश्यक है', isError: true);
      return false;
    }
    if (_weather == null || _weather!.trim().isEmpty) {
      showAppToast(context, 'Weather चुनें', isError: true);
      return false;
    }
    if ((_location ?? '').trim().isEmpty) {
      showAppToast(context, 'Location दर्ज करें', isError: true);
      return false;
    }
    return true;
  }

  bool _validateSection(String sectionKey) {
    final section = _sections.firstWhere(
      (s) => s.key == sectionKey,
      orElse: () => InCabSection(key: sectionKey, title: sectionKey, items: const []),
    );
    for (final q in section.items) {
      final key = '${section.key}:${q.code}';
      final ans = _answers[key];
      if (ans == null || ans.isEmpty) {
        showAppToast(context, 'सभी सवालों का जवाब देना आवश्यक है', isError: true);
        return false;
      }
    }
    return true;
  }

  bool _validateNotes() {
    if ((_overallNotes ?? '').trim().isEmpty) {
      showAppToast(context, 'टिप्पणियाँ आवश्यक हैं', isError: true);
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_validateInfo()) return;
    for (final key in _sectionOrder) {
      if (!_validateSection(key)) return;
    }
    if (!_validateNotes()) return;
    final endTime = DateTime.now();
    final items = <InCabAnswer>[];
    for (final section in _sections) {
      for (final q in section.items) {
        final key = '${section.key}:${q.code}';
        final ans = _answers[key];
        if (ans != null && ans.isNotEmpty) {
          items.add(InCabAnswer(
            sectionKey: section.key,
            itemCode: q.code,
            questionText: q.text,
            result: ans,
          ));
        }
      }
    }
    if (items.isEmpty) {
      showAppToast(context, 'कृपया सवालों के जवाब दें', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final driverIdVal = int.tryParse(_driverId ?? '');
      if (driverIdVal == null) {
        showAppToast(context, 'Invalid driver selection', isError: true);
        return;
      }
      final req = InCabAssessmentRequest(
        driverId: driverIdVal,
        vehicleId: _vehicleId!,
        plantId: _plantId,
        assessorUserId: int.tryParse(widget.user.id),
        transporterName: _transporter,
        weather: _weather,
        locationText: _location,
        startTime: _startTime.toIso8601String(),
        endTime: endTime.toIso8601String(),
        assessmentDate: _date.toIso8601String().split('T').first,
        items: items,
        overallNotes: _overallNotes,
      );
      await widget.repository.submitInCabAssessment(req);
      if (mounted) {
        showAppToast(context, 'Assessment saved');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _overallNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'In-Cab Assessment',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          backgroundColor: const Color(0xFF12355B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _loading
            ? const Center(child: AppLoader())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: Text('Step ${_step + 1} / 6', style: theme.textTheme.titleMedium),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _backgroundTint,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE8F1FF), Color(0xFFFDFDFE)],
                        ),
                      ),
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildInfoPage(),
                          _buildSectionPage('ड्राइव शुरू करने से पहले', 'pre_drive'),
                          _buildSectionPage('दरूरी बनाए रखना', 'distance'),
                          _buildSectionPage('360° स्कैनिंग', 'scanning'),
                          _buildSectionPage('ब्रेकिंग स्किल', 'braking'),
                          _buildNotesPage(),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        if (_step > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _submitting ? null : _back,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF3BF),
                                side: BorderSide(color: const Color(0xFFE5C200).withOpacity(0.6)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Back'),
                            ),
                          ),
                        if (_step > 0) const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _next,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(_step == 5 ? 'Submit' : 'Next'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInfoPage() {
    final theme = Theme.of(context);
    final plants = _directory;
    final selectedPlantVehicles = plants
        .firstWhere(
          (p) => p.id == _plantId,
          orElse: () => plants.isNotEmpty
              ? plants.first
              : PlantDirectoryEntry(id: 0, name: '', vehicles: const [], drivers: const []),
        )
        .vehicles;
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDropdown<int>(
              label: 'Plant',
              value: _plantId,
              items: plants
                  .map((p) => DropdownMenuItem<int>(
                        value: p.id,
                        child: Text(p.name, style: GoogleFonts.josefinSans()),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _plantId = v;
                _vehicleId = null;
              }),
            ),
            const SizedBox(height: 12),
            _buildDropdown<int>(
              label: 'Vehicle',
              value: _vehicleId,
              items: selectedPlantVehicles
                  .map((v) => DropdownMenuItem<int>(
                        value: v.id,
                        child: Text(v.number, style: GoogleFonts.josefinSans()),
                      ))
                  .toList(),
            onChanged: (v) {
              setState(() {
                _vehicleId = v;
                if (_plantId == null && plants.isNotEmpty) {
                  _plantId = plants.first.id;
                }
              });
            },
          ),
          const SizedBox(height: 12),
            _buildDropdown<String>(
              label: 'Driver',
              value: _driverId,
              items: _drivers
                  .map((d) => DropdownMenuItem<String>(
                        value: d.id.toString(),
                        child: Text(d.name, style: GoogleFonts.josefinSans()),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _driverId = v),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: 'Transporter',
              initialValue: _transporter ?? 'SS TRANSWAYS INDIA',
              readOnly: true,
              onChanged: (v) => _transporter = v,
            ),
            const SizedBox(height: 12),
            _buildDropdown<String>(
              label: 'Weather',
              value: _weather,
              items: const [
                DropdownMenuItem(value: 'Clear', child: Text('Clear')),
                DropdownMenuItem(value: 'Rain', child: Text('Rain')),
                DropdownMenuItem(value: 'Fog', child: Text('Fog')),
                DropdownMenuItem(value: 'Night', child: Text('Night')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _weather = v),
            ),
            const SizedBox(height: 12),
            _buildTextField(label: 'Location', onChanged: (v) => _location = v),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Select date'),
              subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionPage(String title, String sectionKey) {
    final section = _sections.firstWhere(
      (s) => s.key == sectionKey,
      orElse: () => InCabSection(key: sectionKey, title: title, items: const []),
    );
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...section.items.map((q) {
            final key = '${section.key}:${q.code}';
            final selected = _answers[key];
            return Card(
              elevation: 2,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.text, style: GoogleFonts.josefinSans(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: q.options.map((opt) {
                        final value = opt.value.toLowerCase();
                        Color? selectedColor;
                        if (value == 'yes' || value == 'positive') {
                          selectedColor = const Color(0xFF2F9E44);
                        } else if (value == 'needs_improvement' || value == 'improvement') {
                          selectedColor = const Color(0xFFF5B301);
                        } else if (value == 'no' || value == 'not_observed') {
                          selectedColor = const Color(0xFFE03131);
                        } else {
                          selectedColor = _primaryColor;
                        }
                        return ChoiceChip(
                          label: Text(opt.label),
                          labelStyle: GoogleFonts.josefinSans(
                            color: selected == opt.value ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                          selected: selected == opt.value,
                          selectedColor: selectedColor,
                          backgroundColor: _backgroundTint,
                          onSelected: (_) => setState(() => _answers[key] = opt.value),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNotesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTextField(
            label: 'टिप्पणियाँ',
            maxLines: 4,
            onChanged: (v) => _overallNotes = v,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      dropdownColor: Colors.white,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildTextField({
    required String label,
    int maxLines = 1,
    String? initialValue,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      maxLines: maxLines,
      initialValue: initialValue,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      onChanged: onChanged,
    );
  }
}
