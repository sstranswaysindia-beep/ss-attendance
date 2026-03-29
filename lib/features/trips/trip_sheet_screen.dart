import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/trip_plant.dart';
import '../../core/models/trip_sheet_record.dart';
import '../../core/models/trip_vehicle.dart';
import '../../core/services/biometric_unlock_service.dart';
import '../../core/services/local_storage_service.dart';
import '../../core/services/trip_repository.dart';
import '../../core/services/trip_sheet_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

// ─── Design tokens (matches salary_advance_screen.dart) ────────────────────
const Color _primaryColor = Color(0xFF12355B);
const Color _accentColor = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A1628);
const Color _gradientEnd = Color(0xFF1B3A5C);
const Color _surfaceCard = Color(0xFFF8FAFF);
const Color _pageBackground = Color(0xFFF0F4F8);

class TripSheetScreen extends StatefulWidget {
  const TripSheetScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<TripSheetScreen> createState() => _TripSheetScreenState();
}

class _TripSheetScreenState extends State<TripSheetScreen> {
  final TripRepository _tripRepo = TripRepository();
  final TripSheetRepository _sheetRepo = TripSheetRepository();
  final LocalStorageService _localStorage = LocalStorageService();
  final ImagePicker _picker = ImagePicker();
  final DateFormat _dateFormatter = DateFormat('dd MMM yyyy');
  final DateFormat _timeFormatter = DateFormat('hh:mm a');

  bool _isLoadingPlants = true;
  bool _isLoadingVehicles = false;
  bool _isLoadingRecords = true;
  bool _isUploading = false;

  List<TripPlant> _plants = const [];
  List<TripVehicle> _vehicles = const [];
  List<TripSheetRecord> _records = const [];
  final List<File> _capturedImages = [];

  TripPlant? _selectedPlant;
  TripVehicle? _selectedVehicle;
  DateTime _selectedSheetDate = DateTime.now();
  DateTime? _selectedHistoryMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  @override
  void initState() {
    super.initState();
    _loadPlants();
    _loadRecords();
  }

  // ─── Data loading ──────────────────────────────────────────────────────

  Future<void> _loadPlants() async {
    try {
      final plants = await _tripRepo.fetchPlantsForUser(widget.user);
      final savedPlantId = await _localStorage.getTripSheetPlantId(
        widget.user.id,
      );
      final savedPlant = savedPlantId == null
          ? null
          : plants.cast<TripPlant?>().firstWhere(
              (plant) => plant?.id.toString() == savedPlantId,
              orElse: () => null,
            );
      if (!mounted) return;
      final initialPlant =
          savedPlant ?? (plants.length == 1 ? plants.first : null);
      setState(() {
        _plants = plants;
        _isLoadingPlants = false;
        _selectedPlant = initialPlant;
      });
      if (initialPlant != null) {
        final savedVehicleId = await _localStorage.getTripSheetVehicleId(
          widget.user.id,
        );
        await _loadVehicles(initialPlant, preferredVehicleId: savedVehicleId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPlants = false);
    }
  }

  Future<void> _loadVehicles(
    TripPlant plant, {
    String? preferredVehicleId,
  }) async {
    setState(() {
      _isLoadingVehicles = true;
      _vehicles = const [];
      _selectedVehicle = null;
    });
    try {
      final vehicles = await _tripRepo.fetchVehiclesForPlant(
        user: widget.user,
        plantId: plant.id.toString(),
      );
      if (!mounted) return;
      TripVehicle? restoredVehicle;
      if (preferredVehicleId != null && preferredVehicleId.isNotEmpty) {
        restoredVehicle = vehicles.cast<TripVehicle?>().firstWhere(
          (vehicle) => vehicle?.id.toString() == preferredVehicleId,
          orElse: () => null,
        );
      }
      setState(() {
        _vehicles = vehicles;
        _selectedVehicle = restoredVehicle;
        _isLoadingVehicles = false;
      });
      await _loadRecords();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingVehicles = false);
    }
  }

  Future<void> _loadRecords() async {
    final plant = _selectedPlant;
    final vehicle = _selectedVehicle;
    if (plant == null || vehicle == null) {
      if (!mounted) return;
      setState(() {
        _records = const [];
        _isLoadingRecords = false;
      });
      return;
    }

    setState(() => _isLoadingRecords = true);
    try {
      final month = _selectedHistoryMonth;
      final records = await _sheetRepo.fetchRecords(
        user: widget.user,
        plantId: plant.id,
        vehicleId: vehicle.id,
        dateFrom: month == null ? null : _formatApiDate(_monthStart(month)),
        dateTo: month == null ? null : _formatApiDate(_monthEnd(month)),
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoadingRecords = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingRecords = false);
    }
  }

  // ─── Image capture / selection ─────────────────────────────────────────

  Future<void> _pickTripSheetImage(ImageSource source) async {
    if (_selectedPlant == null || _selectedVehicle == null) {
      showAppToast(context, 'Select plant and vehicle first.', isError: true);
      return;
    }
    try {
      BiometricUnlockService.suppressPromptsTemporarily();
      if (source == ImageSource.gallery) {
        final List<XFile> photos = await _picker.pickMultiImage(
          imageQuality: 80,
          maxWidth: 1920,
        );
        if (photos.isEmpty || !mounted) return;
        setState(() {
          _capturedImages.addAll(photos.map((photo) => File(photo.path)));
        });
        showAppToast(
          context,
          '${photos.length} trip sheet ${photos.length == 1 ? 'image' : 'images'} added.',
        );
        return;
      }

      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (photo == null || !mounted) return;
      setState(() {
        _capturedImages.add(File(photo.path));
      });
      showAppToast(context, 'Trip sheet image added.');
    } catch (e) {
      if (!mounted) return;
      final sourceLabel = source == ImageSource.camera ? 'Camera' : 'Gallery';
      showAppToast(context, '$sourceLabel error: $e', isError: true);
    }
  }

  Future<void> _showImageSourcePicker() async {
    if (_selectedPlant == null || _selectedVehicle == null) {
      showAppToast(context, 'Select plant and vehicle first.', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Choose Trip Sheet Images',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Capture one photo or select multiple from gallery.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildGradientButton(
                        label: 'Camera',
                        icon: Icons.camera_alt_rounded,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _pickTripSheetImage(ImageSource.camera);
                        },
                        colors: const [Color(0xFF00897B), Color(0xFF00BFA6)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGradientButton(
                        label: 'Gallery',
                        icon: Icons.photo_library_rounded,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _pickTripSheetImage(ImageSource.gallery);
                        },
                        colors: const [Color(0xFF1B64D8), Color(0xFF0097A7)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadTripSheet() async {
    if (_capturedImages.isEmpty ||
        _selectedPlant == null ||
        _selectedVehicle == null) {
      return;
    }
    setState(() => _isUploading = true);
    try {
      final captureDate = _selectedSheetDate;
      final imagesToUpload = List<File>.from(_capturedImages);
      var uploadedCount = 0;
      for (final image in imagesToUpload) {
        await _sheetRepo.upload(
          user: widget.user,
          plantId: _selectedPlant!.id,
          plantName: _selectedPlant!.name,
          vehicleId: _selectedVehicle!.id,
          vehicleNumber: _selectedVehicle!.number,
          imageFile: image,
          captureDate: captureDate,
        );
        uploadedCount++;
      }
      if (!mounted) return;
      showAppToast(
        context,
        '$uploadedCount trip sheet ${uploadedCount == 1 ? 'image' : 'images'} uploaded successfully.',
      );
      final uploadedMonth = DateTime(captureDate.year, captureDate.month);
      setState(() {
        _capturedImages.clear();
        _selectedSheetDate = DateTime.now();
        _selectedHistoryMonth = uploadedMonth;
      });
      await _loadRecords();
    } on TripSheetFailure catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Upload failed. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    EdgeInsetsGeometry? margin,
    Color? color,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color ?? _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _sectionTitle(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 1),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, _accentColor],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    IconData? icon,
    required VoidCallback? onTap,
    required List<Color> colors,
    bool isLoading = false,
  }) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: disabled
                ? [Colors.grey.shade300, Colors.grey.shade400]
                : colors,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: colors.last.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Date helpers ──────────────────────────────────────────────────────

  DateTime _monthStart(DateTime value) => DateTime(value.year, value.month);

  DateTime _monthEnd(DateTime value) =>
      DateTime(value.year, value.month + 1, 0);

  String _formatApiDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _dateGroupLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(recordDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return _dateFormatter.format(date);
  }

  String _monthFilterLabel(DateTime? value) {
    if (value == null) return 'All months';
    return DateFormat('MMMM yyyy').format(value);
  }

  Future<void> _pickSheetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedSheetDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Select trip sheet date',
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedSheetDate = picked);
  }

  Future<void> _applyHistoryMonth(DateTime? value) async {
    setState(() {
      _selectedHistoryMonth = value == null
          ? null
          : DateTime(value.year, value.month);
    });
    await _loadRecords();
  }

  DateTime _tripSheetDeleteCutoff() {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1);
  }

  bool _canDeleteRecord(TripSheetRecord record) {
    final cutoff = _tripSheetDeleteCutoff();
    final recordDate = record.createdAt.toLocal();
    final recordMonth = DateTime(recordDate.year, recordDate.month);
    return !recordMonth.isBefore(cutoff);
  }

  void _showDeleteBlockedMessage(TripSheetRecord record) {
    showAppToast(
      context,
      'Only current month and previous month trip sheet images can be deleted.',
      isError: true,
    );
  }

  Future<bool> _confirmAndDeleteRecord(
    TripSheetRecord record, {
    bool removeFromList = true,
  }) async {
    if (!_canDeleteRecord(record)) {
      _showDeleteBlockedMessage(record);
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete trip sheet image?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will remove the trip sheet image for ${record.vehicleNumber}. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFD32F2F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return false;
    }

    try {
      await _sheetRepo.deleteRecord(user: widget.user, recordId: record.id);
      if (!mounted) return false;
      if (removeFromList) {
        setState(() {
          _records = _records
              .where((item) => item.id != record.id)
              .toList(growable: false);
        });
        showAppToast(context, 'Trip sheet image deleted.');
      }
      return true;
    } on TripSheetFailure catch (error) {
      if (!mounted) return false;
      showAppToast(context, error.message, isError: true);
      return false;
    } catch (_) {
      if (!mounted) return false;
      showAppToast(
        context,
        'Unable to delete trip sheet image.',
        isError: true,
      );
      return false;
    }
  }

  void _showMonthFilterSheet() {
    final now = DateTime.now();
    final recentMonths = List<DateTime>.generate(
      12,
      (index) => DateTime(now.year, now.month - index),
      growable: false,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Filter trip sheets by month',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.layers_clear_rounded,
                          color: _primaryColor,
                        ),
                        title: const Text('All months'),
                        trailing: _selectedHistoryMonth == null
                            ? const Icon(
                                Icons.check_rounded,
                                color: _accentColor,
                              )
                            : null,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _applyHistoryMonth(null);
                        },
                      ),
                      for (final month in recentMonths)
                        ListTile(
                          leading: const Icon(
                            Icons.calendar_month_rounded,
                            color: _primaryColor,
                          ),
                          title: Text(_monthFilterLabel(month)),
                          trailing:
                              _selectedHistoryMonth?.year == month.year &&
                                  _selectedHistoryMonth?.month == month.month
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: _accentColor,
                                )
                              : null,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _applyHistoryMonth(month);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, List<TripSheetRecord>> _groupByDate(
    List<TripSheetRecord> records,
  ) {
    final grouped = <String, List<TripSheetRecord>>{};
    for (final record in records) {
      final label = _dateGroupLabel(record.createdAt);
      grouped.putIfAbsent(label, () => []).add(record);
    }
    return grouped;
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: _gradientStart,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Trip Sheets',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadRecords,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        color: _accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_gradientStart, _gradientEnd, Color(0xFF0D4F6B)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_accentColor, Color(0xFF007C6E)],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.user.displayName.isNotEmpty
                            ? widget.user.displayName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.user.role.name[0].toUpperCase()}${widget.user.role.name.substring(1)} · Trip Sheets',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
                      color: const Color(0xFF7CFFB2).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF7CFFB2).withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      '${_records.length} sheets',
                      style: const TextStyle(
                        color: Color(0xFF7CFFB2),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionTitle('Capture Trip Sheet', icon: Icons.camera_alt_rounded),
            _buildCaptureSection(),
            const SizedBox(height: 8),
            _buildHistoryHeader(),
            _buildHistorySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureSection() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Plant dropdown
          _buildDropdownCard<TripPlant>(
            label: 'Select Plant',
            icon: Icons.factory_rounded,
            isLoading: _isLoadingPlants,
            value: _selectedPlant,
            items: _plants,
            itemLabel: (p) => p.name,
            onChanged: (plant) {
              if (plant == null) return;
              setState(() {
                _selectedPlant = plant;
                _selectedVehicle = null;
                _capturedImages.clear();
                _records = const [];
                _isLoadingRecords = false;
              });
              _localStorage.saveTripSheetPlantId(
                widget.user.id,
                plant.id.toString(),
              );
              _loadVehicles(plant);
            },
          ),

          const SizedBox(height: 8),

          // Vehicle dropdown
          _buildDropdownCard<TripVehicle>(
            label: 'Select Vehicle',
            icon: Icons.local_shipping_rounded,
            isLoading: _isLoadingVehicles,
            value: _selectedVehicle,
            items: _vehicles,
            itemLabel: (v) => v.number,
            onChanged: _selectedPlant == null
                ? null
                : (vehicle) {
                    setState(() {
                      _selectedVehicle = vehicle;
                      _capturedImages.clear();
                    });
                    if (vehicle != null) {
                      _localStorage.saveTripSheetPlantId(
                        widget.user.id,
                        _selectedPlant!.id.toString(),
                      );
                      _localStorage.saveTripSheetVehicleId(
                        widget.user.id,
                        vehicle.id.toString(),
                      );
                    }
                    _loadRecords();
                  },
          ),

          const SizedBox(height: 8),

          _buildDateSelectorCard(),

          const SizedBox(height: 10),

          if (_capturedImages.isNotEmpty) ...[
            _buildSelectedImagesSection(),
            const SizedBox(height: 10),
          ],

          // Camera button
          _buildGradientButton(
            label: _isUploading ? 'Uploading...' : 'Add Trip Sheet Photos',
            icon: Icons.add_a_photo_rounded,
            isLoading: _isUploading,
            onTap:
                (_isUploading ||
                    _selectedPlant == null ||
                    _selectedVehicle == null)
                ? null
                : _showImageSourcePicker,
            colors: const [Color(0xFF00897B), Color(0xFF00BFA6)],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImagesSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.collections_rounded,
                  size: 18,
                  color: _accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selected Photos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      '${_capturedImages.length} photo${_capturedImages.length == 1 ? '' : 's'} ready. Each photo will create a separate trip sheet entry.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_capturedImages.length, (index) {
                final image = _capturedImages[index];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        image,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _capturedImages.removeAt(index);
                          });
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploading
                      ? null
                      : () {
                          setState(() {
                            _capturedImages.clear();
                          });
                        },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('Clear All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildGradientButton(
                  label: _isUploading
                      ? 'Uploading...'
                      : 'Upload ${_capturedImages.length}',
                  icon: Icons.cloud_upload_rounded,
                  isLoading: _isUploading,
                  onTap: _isUploading ? null : _uploadTripSheet,
                  colors: const [Color(0xFF1B64D8), Color(0xFF0097A7)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelectorCard() {
    return InkWell(
      onTap: _pickSheetDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.event_rounded,
                size: 16,
                color: _accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trip Sheet Date',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _dateFormatter.format(_selectedSheetDate),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Defaults to today',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded, color: _accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownCard<T>({
    required String label,
    required IconData icon,
    required bool isLoading,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    ValueChanged<T?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<T>(
                      value: value,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        color: _accentColor,
                      ),
                      dropdownColor: Colors.white,
                      hint: Text(
                        label,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      items: items
                          .map(
                            (item) => DropdownMenuItem<T>(
                              value: item,
                              child: Text(
                                itemLabel(item),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: onChanged,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_isLoadingRecords) {
      return _glassCard(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
            ),
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      return _glassCard(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                size: 32,
                color: Colors.blueGrey.shade300,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No trip sheets uploaded yet.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Select a plant & vehicle, then capture.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    final grouped = _groupByDate(_records);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6, left: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: entry.key == 'Today'
                        ? _accentColor
                        : _primaryColor.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: entry.key == 'Today'
                        ? _accentColor
                        : const Color(0xFF1A1A2E).withOpacity(0.7),
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${entry.value.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _primaryColor.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...entry.value.map((record) => _buildRecordCard(record)),
        ],
      ],
    );
  }

  Widget _buildHistoryHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 1),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryColor, _accentColor],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Trip Sheet History',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
                letterSpacing: 0.3,
              ),
            ),
          ),
          InkWell(
            onTap: _showMonthFilterSheet,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 16,
                    color: _accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _monthFilterLabel(_selectedHistoryMonth),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: _accentColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(TripSheetRecord record) {
    final canDelete = _canDeleteRecord(record);

    final card = GestureDetector(
      onTap: () => _openTripSheetPreview(record),
      child: _glassCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: record.imageUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.image, color: Colors.grey, size: 24),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.red.shade300,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.vehicleNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.factory_rounded,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          record.plantName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _dateFormatter.format(record.createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _timeFormatter.format(record.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: record.userRole == 'supervisor'
                              ? Colors.indigo.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: record.userRole == 'supervisor'
                                ? Colors.indigo.shade200
                                : Colors.green.shade200,
                          ),
                        ),
                        child: Text(
                          record.userRole[0].toUpperCase() +
                              record.userRole.substring(1),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: record.userRole == 'supervisor'
                                ? Colors.indigo.shade600
                                : Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () async {
                    if (canDelete) {
                      await _confirmAndDeleteRecord(record);
                    } else {
                      _showDeleteBlockedMessage(record);
                    }
                  },
                  tooltip: canDelete
                      ? 'Delete image'
                      : 'Delete allowed only for current and previous month',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: canDelete
                        ? const Color(0xFFD32F2F)
                        : Colors.grey.shade400,
                    size: 22,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade300,
                  size: 24,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!canDelete) {
      return card;
    }

    return Dismissible(
      key: ValueKey('trip_sheet_${record.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) =>
          _confirmAndDeleteRecord(record, removeFromList: false),
      onDismissed: (_) {
        if (!mounted) return;
        setState(() {
          _records = _records
              .where((item) => item.id != record.id)
              .toList(growable: false);
        });
        showAppToast(context, 'Trip sheet image deleted.');
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFCDD2)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerLeft,
        child: Row(
          children: const [
            Icon(Icons.delete_rounded, color: Color(0xFFD32F2F), size: 22),
            SizedBox(width: 8),
            Text(
              'Swipe to delete',
              style: TextStyle(
                color: Color(0xFFD32F2F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: card,
    );
  }

  void _openTripSheetPreview(TripSheetRecord record) {
    final fmt = DateFormat('dd MMM yyyy · hh:mm a');
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        int reloadKey = 0;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Trip Sheet',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _gradientStart,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${record.vehicleNumber} • ${fmt.format(record.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.plantName,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              content: SizedBox(
                width: 340,
                height: 420,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      record.imageUrl,
                      key: ValueKey('trip_sheet_${record.id}_$reloadKey'),
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: AppLoader(size: 36));
                      },
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Unable to load trip sheet image.',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  reloadKey++;
                                });
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
