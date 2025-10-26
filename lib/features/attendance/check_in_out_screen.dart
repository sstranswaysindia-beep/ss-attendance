import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/models/driver_vehicle.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/services/assignment_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

enum CheckFlowAction { checkIn, checkOut }

class CheckInOutScreen extends StatefulWidget {
  const CheckInOutScreen({
    required this.user,
    this.availableVehicles = const <DriverVehicle>[],
    this.selectedVehicleId,
    this.onVehicleAssigned,
    super.key,
  });

  final AppUser user;
  final List<DriverVehicle> availableVehicles;
  final String? selectedVehicleId;
  final ValueChanged<DriverVehicle>? onVehicleAssigned;

  @override
  State<CheckInOutScreen> createState() => _CheckInOutScreenState();
}

class _CheckInOutScreenState extends State<CheckInOutScreen>
    with SingleTickerProviderStateMixin {
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  final AssignmentRepository _assignmentRepository = AssignmentRepository();

  AttendanceRecord? _activeShift;
  bool _isLoadingShift = true;
  bool _isSubmitting = false;
  bool _isAssigning = false;
  bool _isSyncPending = false;
  File? _capturedPhoto;
  String? _submissionSummary;
  bool _hasShownLocationWarning = false;
  bool? _locationServiceEnabled;
  LocationPermission? _locationPermissionStatus;
  bool _locationStatusRefreshing = false;

  String? _selectedVehicleId;
  String? _selectedVehicleNumber;

  late final AnimationController _statusController;
  late final Animation<double> _statusAnimation;

  @override
  void initState() {
    super.initState();
    _statusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _statusAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _statusController, curve: Curves.easeInOut),
    );

    _initialiseVehicleSelection();
    _loadActiveShift();
    if (widget.user.geofencingEnabled) {
      _preflightLocationCheck();
    }
  }

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
  }

  void _initialiseVehicleSelection() {
    final vehicles = widget.availableVehicles;
    if (vehicles.isEmpty) {
      _selectedVehicleId = widget.selectedVehicleId;
      _selectedVehicleNumber = widget.user.vehicleNumber;
      return;
    }

    if (widget.selectedVehicleId != null) {
      final match = vehicles.firstWhere(
        (vehicle) => vehicle.id == widget.selectedVehicleId,
        orElse: () => vehicles.first,
      );
      _selectedVehicleId = match.id;
      _selectedVehicleNumber = match.vehicleNumber;
      return;
    }

    final firstVehicle = vehicles.first;
    _selectedVehicleId = firstVehicle.id;
    _selectedVehicleNumber = firstVehicle.vehicleNumber;
  }

  Future<void> _loadActiveShift() async {
    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _isLoadingShift = false;
        _activeShift = null;
      });
      return;
    }

    setState(() => _isLoadingShift = true);

    try {
      // Use our new get_current_attendance API for better supervisor support
      final currentAttendance = await _fetchCurrentAttendance();
      if (!mounted) return;

      setState(() {
        _activeShift = currentAttendance;
        _isLoadingShift = false;
        if (currentAttendance != null) {
          if (currentAttendance.vehicleId != null &&
              currentAttendance.vehicleId!.isNotEmpty) {
            _selectedVehicleId = currentAttendance.vehicleId;
            _selectedVehicleNumber = currentAttendance.vehicleNumber;
          }
          _submissionSummary = _hasOpenShift
              ? 'Checked in at ${_formatDateTime(currentAttendance.inTime)}'
              : 'Last check-out ${_formatDateTime(currentAttendance.outTime)}';
        }
      });
      _updateStatusAnimation();
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingShift = false;
        _activeShift = null;
      });
      _updateStatusAnimation();
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingShift = false;
        _activeShift = null;
      });
      _updateStatusAnimation();
      showAppToast(context, 'Unable to load attendance status.', isError: true);
    }
  }

  Future<void> _preflightLocationCheck() async {
    if (!widget.user.geofencingEnabled) {
      return;
    }
    setState(() => _locationStatusRefreshing = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = serviceEnabled;
        _locationPermissionStatus = permission;
        _locationStatusRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = null;
        _locationPermissionStatus = null;
        _locationStatusRefreshing = false;
      });
    }
  }

  Future<void> _openLocationSettings() async {
    try {
      final didOpen = await Geolocator.openLocationSettings();
      if (!mounted) return;
      if (didOpen) {
        await _preflightLocationCheck();
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        'Unable to open location settings on this device.',
        isError: true,
      );
    }
  }

  Future<void> _openAppPermissionSettings() async {
    try {
      final didOpen = await Geolocator.openAppSettings();
      if (!mounted) return;
      if (didOpen) {
        await _preflightLocationCheck();
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        'Unable to open app permissions screen.',
        isError: true,
      );
    }
  }

  Future<AttendanceRecord?> _fetchCurrentAttendance() async {
    try {
      final requestBody = {
        'userId': widget.user.id,
        'driverId': widget.user.driverId,
      };

      print(
        'DEBUG: Fetching current attendance for user ${widget.user.id}, driverId: ${widget.user.driverId}',
      );

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_current_attendance.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok' && data['current_attendance'] != null) {
          final attendanceData =
              data['current_attendance'] as Map<String, dynamic>;
          print('DEBUG: Found current attendance: ${attendanceData['id']}');
          return AttendanceRecord(
            attendanceId: attendanceData['id']?.toString() ?? '',
            driverId: attendanceData['driver_id']?.toString() ?? '',
            plantId: attendanceData['plant_id']?.toString(),
            plantName: '', // Will be filled from other sources
            vehicleId: attendanceData['vehicle_id']?.toString(),
            vehicleNumber: '', // Will be filled from other sources
            assignmentId: attendanceData['assignment_id']?.toString(),
            inTime: attendanceData['in_time']?.toString(),
            outTime: attendanceData['out_time']?.toString(),
            notes: attendanceData['notes']?.toString(),
            status: attendanceData['approval_status']?.toString(),
            source: attendanceData['source']?.toString(),
          );
        } else {
          print('DEBUG: No current attendance found');
        }
      }
      return null;
    } catch (e) {
      print('Error fetching current attendance: $e');
      return null;
    }
  }

  bool get _hasOpenShift {
    final record = _activeShift;
    if (record == null) {
      return false;
    }
    final outTime = record.outTime;
    return outTime == null || outTime.isEmpty;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _hasCompletedAttendanceToday {
    final record = _activeShift;
    if (record == null) {
      return false;
    }
    final inTimeRaw = record.inTime;
    if (inTimeRaw == null || inTimeRaw.isEmpty) {
      return false;
    }
    final inTime = DateTime.tryParse(inTimeRaw);
    if (inTime == null || !_isSameDay(inTime, DateTime.now())) {
      return false;
    }
    final outTimeRaw = record.outTime;
    if (outTimeRaw == null || outTimeRaw.isEmpty) {
      return false;
    }
    final outTime = DateTime.tryParse(outTimeRaw);
    return outTime != null;
  }

  CheckFlowAction get _currentAction =>
      _hasOpenShift ? CheckFlowAction.checkOut : CheckFlowAction.checkIn;

  String get _currentActionLabel =>
      _currentAction == CheckFlowAction.checkIn ? 'Check-in' : 'Check-out';

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return DateFormat('dd MMM yyyy • HH:mm').format(parsed);
  }

  String? _resolvePlantId() {
    final activeShift = _activeShift;
    final activePlantId = activeShift?.plantId;
    if (_hasOpenShift && activePlantId != null && activePlantId.isNotEmpty) {
      return activePlantId;
    }

    final assignmentPlantId = widget.user.assignmentPlantId;
    if (assignmentPlantId != null && assignmentPlantId.isNotEmpty) {
      return assignmentPlantId;
    }

    final mappedPlantId = widget.user.plantId;
    if (mappedPlantId != null && mappedPlantId.isNotEmpty) {
      return mappedPlantId;
    }

    final defaultPlantId = widget.user.defaultPlantId;
    if (defaultPlantId != null && defaultPlantId.isNotEmpty) {
      return defaultPlantId;
    }

    return activePlantId;
  }

  String _resolvePlantLabel() {
    final activeShift = _activeShift;
    if (_hasOpenShift) {
      final activeLabel = activeShift?.plantName;
      if (activeLabel != null && activeLabel.isNotEmpty) {
        return activeLabel;
      }
    }

    final candidates = <String?>[
      widget.user.assignmentPlantName,
      widget.user.plantName,
      widget.user.defaultPlantName,
      activeShift?.plantName,
      _resolvePlantId(),
    ];

    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }

    return 'Not mapped';
  }

  Future<void> _pickVehicle() async {
    final vehicles = widget.availableVehicles;
    if (vehicles.isEmpty) {
      showAppToast(
        context,
        'No vehicles mapped yet. Contact supervisor.',
        isError: true,
      );
      return;
    }

    final selected = await showModalBottomSheet<DriverVehicle>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Vehicle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...vehicles.map(
                (vehicle) => ListTile(
                  leading: const Icon(Icons.fire_truck),
                  title: Text(vehicle.vehicleNumber),
                  trailing: vehicle.id == _selectedVehicleId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(vehicle),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    await _persistVehicleSelection(selected);
  }

  Future<void> _persistVehicleSelection(DriverVehicle vehicle) async {
    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    final plantId = _resolvePlantId();

    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'User mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }
    if (plantId == null || plantId.isEmpty) {
      showAppToast(
        context,
        'Plant mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    setState(() => _isAssigning = true);
    try {
      await _assignmentRepository.assignVehicle(
        driverId: driverId,
        vehicleId: vehicle.id,
        plantId: plantId,
        userId: widget.user.id,
      );
      if (!mounted) return;

      setState(() {
        _selectedVehicleId = vehicle.id;
        _selectedVehicleNumber = vehicle.vehicleNumber;
        _isAssigning = false;
      });
      widget.onVehicleAssigned?.call(vehicle);
      showAppToast(context, 'Vehicle updated successfully.');
    } on AssignmentFailure catch (error) {
      if (!mounted) return;
      setState(() => _isAssigning = false);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAssigning = false);
      showAppToast(context, 'Unable to update vehicle.', isError: true);
    }
  }

  Future<void> _handleCheckInOut() async {
    if (_currentAction == CheckFlowAction.checkIn &&
        _hasCompletedAttendanceToday) {
      showAppToast(
        context,
        'Attendance already marked for today.',
        isError: false,
      );
      return;
    }
    // First capture photo, then submit attendance
    await _capturePhoto();

    // If photo was captured successfully, proceed with submission
    if (_capturedPhoto != null) {
      await _submitAttendance();
    }
  }

  Future<void> _capturePhoto() async {
    try {
      XFile? xFile;
      try {
        final platform = ImagePickerPlatform.instance;
        xFile = await platform.getImageFromSource(
          source: ImageSource.camera,
          options: const ImagePickerOptions(
            imageQuality: 85,
            preferredCameraDevice: CameraDevice.front,
          ),
        );
      } on UnimplementedError {
        // Fallback to default picker implementation if the platform
        // interface method is not supported.
        xFile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 85,
        );
      }

      // Final safeguard fallback to the classic picker call.
      xFile ??= await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );

      if (xFile == null) {
        return;
      }

      final directory = await getApplicationDocumentsDirectory();

      // Create date-based folder structure
      final now = DateTime.now();
      final dateFolder = DateFormat('yyyy-MM-dd').format(now);
      final dateDir = Directory(
        '${directory.path}/attendance_photos/$dateFolder',
      );

      // Create directory if it doesn't exist
      if (!await dateDir.exists()) {
        await dateDir.create(recursive: true);
      }

      // Create filename with action type and timestamp
      final actionType = _currentAction == CheckFlowAction.checkIn
          ? 'checkin'
          : 'checkout';
      final timeStamp = DateFormat('HH-mm-ss').format(now);
      final fileName = '${actionType}_${timeStamp}.jpg';
      final savedPath = '${dateDir.path}/$fileName';
      final savedFile = await File(xFile.path).copy(savedPath);

      if (!mounted) return;
      setState(() => _capturedPhoto = savedFile);

      // Optionally keep file size info for debugging without user toast
      // final fileSize = await savedFile.length();
      // final sizeKB = (fileSize / 1024).toStringAsFixed(1);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to capture photo.', isError: true);
    }
  }

  Future<void> _submitAttendance() async {
    final performedAction = _currentAction;
    final actionLabel = performedAction == CheckFlowAction.checkIn
        ? 'Check-in'
        : 'Check-out';

    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    final plantId = _resolvePlantId();
    final vehicleId = _selectedVehicleId;
    final assignmentId = _activeShift?.assignmentId ?? widget.user.assignmentId;

    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'User mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }
    if (plantId == null || plantId.isEmpty) {
      showAppToast(
        context,
        'Plant mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }
    if (vehicleId == null || vehicleId.isEmpty) {
      showAppToast(
        context,
        'Select a vehicle before submitting.',
        isError: true,
      );
      return;
    }
    if (_currentAction == CheckFlowAction.checkIn &&
        _hasCompletedAttendanceToday) {
      showAppToast(
        context,
        'Attendance already marked for today.',
        isError: false,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _isSyncPending = true;
    });
    _updateStatusAnimation();

    try {
      final locationPayload = await _captureCurrentLocation(
        requireHighAccuracy: widget.user.geofencingEnabled,
      );

      if (widget.user.geofencingEnabled && locationPayload == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSubmitting = false;
          _isSyncPending = false;
        });
        _updateStatusAnimation();
        showAppToast(
          context,
          'Precise location is required for attendance. Enable GPS and try again.',
          isError: true,
        );
        return;
      }
      final result = await _attendanceRepository.submit(
        driverId: driverId,
        plantId: plantId,
        vehicleId: vehicleId,
        assignmentId: assignmentId,
        action: performedAction == CheckFlowAction.checkIn
            ? AttendanceAction.checkIn
            : AttendanceAction.checkOut,
        photoFile: _capturedPhoto,
        locationJson: locationPayload,
      );

      if (!mounted) return;

      final displayTimestamp = _formatDateTime(result.timestamp);

      setState(() {
        _capturedPhoto = null;
        _submissionSummary = '$actionLabel recorded at $displayTimestamp';
        _isSyncPending = false;
      });
      _updateStatusAnimation();

      // Force refresh the active shift after submission
      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // Small delay for server processing
      await _loadActiveShift();
      if (!mounted) return;
      showAppToast(context, '$actionLabel submitted successfully.');
      if (performedAction == CheckFlowAction.checkOut) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          }
        });
      }
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _isSyncPending = false);
      _updateStatusAnimation();
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSyncPending = false);
      _updateStatusAnimation();
      showAppToast(context, 'Unable to submit attendance.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _updateStatusAnimation();
      }
    }
  }

  Future<Map<String, dynamic>?> _captureCurrentLocation({
    bool requireHighAccuracy = false,
  }) async {
    bool? serviceEnabledValue;
    LocationPermission? permissionValue;
    try {
      if (mounted) {
        setState(() => _locationStatusRefreshing = true);
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      serviceEnabledValue = serviceEnabled;
      if (!serviceEnabled) {
        if (mounted && !_hasShownLocationWarning) {
          _hasShownLocationWarning = true;
          showAppToast(
            context,
            'Enable location services to attach coordinates to attendance.',
          );
        }
        return null;
      }

      var permission = await Geolocator.checkPermission();
      permissionValue = permission;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        permissionValue = permission;
      }

      final bool hasPermission =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (!hasPermission) {
        if (mounted && !_hasShownLocationWarning) {
          _hasShownLocationWarning = true;
          final bool permanentlyDenied =
              permission == LocationPermission.deniedForever;
          showAppToast(
            context,
            permanentlyDenied
                ? 'Location permission permanently denied. Open app settings to enable it.'
                : 'Location permission denied. Attendance submitted without GPS.',
            isError: true,
          );
        }
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: requireHighAccuracy
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      _hasShownLocationWarning = false;
      return <String, dynamic>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': position.timestamp.toIso8601String(),
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'speedAccuracy': position.speedAccuracy,
        'heading': position.heading,
        'source': 'geolocator',
        'geofenceEnforced': requireHighAccuracy,
      };
    } catch (error) {
      if (mounted && !_hasShownLocationWarning) {
        _hasShownLocationWarning = true;
        showAppToast(
          context,
          'Unable to capture GPS location. Attendance saved without it.',
          isError: true,
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          if (serviceEnabledValue != null) {
            _locationServiceEnabled = serviceEnabledValue;
          }
          if (permissionValue != null) {
            _locationPermissionStatus = permissionValue;
          }
          _locationStatusRefreshing = false;
        });
      }
    }
  }

  Widget _buildGeofenceBanner(BuildContext context) {
    if (!widget.user.geofencingEnabled) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final bool? serviceStatus = _locationServiceEnabled;
    final LocationPermission? permissionStatus = _locationPermissionStatus;
    final bool serviceKnown = serviceStatus != null;
    final bool serviceEnabled = serviceStatus == true;
    final bool permissionKnown = permissionStatus != null;
    final bool permissionGranted =
        permissionStatus == LocationPermission.always ||
        permissionStatus == LocationPermission.whileInUse;
    final bool permissionForeverDenied =
        permissionStatus == LocationPermission.deniedForever;

    final String serviceLabel = serviceKnown
        ? (serviceEnabled ? 'GPS enabled' : 'GPS disabled')
        : (_locationStatusRefreshing
              ? 'Checking GPS status…'
              : 'GPS status unknown');
    final IconData serviceIcon = serviceKnown
        ? (serviceEnabled ? Icons.gps_fixed : Icons.gps_off)
        : Icons.location_searching;
    final Color serviceColor = serviceKnown
        ? (serviceEnabled ? Colors.green.shade700 : Colors.red.shade600)
        : Colors.blueGrey.shade600;

    final String permissionLabel = permissionKnown
        ? _permissionDescription(permissionStatus!)
        : (_locationStatusRefreshing
              ? 'Checking permission…'
              : 'Permission unchecked');
    final IconData permissionIcon;
    final Color permissionColor;

    if (!permissionKnown) {
      permissionIcon = Icons.lock_clock;
      permissionColor = Colors.blueGrey.shade600;
    } else if (permissionGranted) {
      permissionIcon = Icons.lock_open;
      permissionColor = Colors.green.shade700;
    } else if (permissionForeverDenied) {
      permissionIcon = Icons.lock;
      permissionColor = Colors.red.shade600;
    } else {
      permissionIcon = Icons.lock_outline;
      permissionColor = Colors.orange.shade700;
    }

    final bool isSupervisor = widget.user.role == UserRole.supervisor;
    final String subjectLine = isSupervisor
        ? 'Supervisors must mark attendance from within their assigned plant boundary.'
        : 'Drivers must remain inside the plant geofence before submitting attendance.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: Colors.indigo.shade600,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Geofence active',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.indigo.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Precise GPS is mandatory for check-in and check-out. $subjectLine',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.indigo.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusPill(
                icon: serviceIcon,
                label: serviceLabel,
                color: serviceColor,
              ),
              _buildStatusPill(
                icon: permissionIcon,
                label: permissionLabel,
                color: permissionColor,
              ),
              _buildStatusPill(
                icon: isSupervisor ? Icons.manage_accounts : Icons.badge,
                label: isSupervisor ? 'Supervisor account' : 'Driver account',
                color: Colors.indigo.shade700,
                backgroundColor: Colors.indigo.shade100,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _locationStatusRefreshing
                      ? null
                      : _preflightLocationCheck,
                  icon: _locationStatusRefreshing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _locationStatusRefreshing ? 'Checking…' : 'Refresh status',
                  ),
                ),
                TextButton.icon(
                  onPressed: _openLocationSettings,
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('Location settings'),
                ),
                if (permissionForeverDenied)
                  TextButton.icon(
                    onPressed: _openAppPermissionSettings,
                    icon: const Icon(Icons.app_settings_alt),
                    label: const Text('App permissions'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required Color color,
    Color? backgroundColor,
  }) {
    final Color resolvedBackground = backgroundColor ?? color.withOpacity(0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _permissionDescription(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
        return 'Permission: always';
      case LocationPermission.whileInUse:
        return 'Permission: while in use';
      case LocationPermission.denied:
        return 'Permission denied';
      case LocationPermission.deniedForever:
        return 'Permission permanently denied';
      default:
        return 'Permission: ${permission.name}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool attendanceCompleted = _hasCompletedAttendanceToday;
    final String buttonLabel = attendanceCompleted
        ? 'Attendance Completed'
        : _currentActionLabel;
    final bool isButtonEnabled = !attendanceCompleted && !_isSubmitting;
    final Color resolvedButtonColor = attendanceCompleted
        ? Colors.blueGrey.shade400
        : _currentAction == CheckFlowAction.checkIn
        ? const Color(0xFF07DD05)
        : const Color(0xFFDFCE34);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in / Check-out'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActiveShift,
            tooltip: 'Refresh attendance status',
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _isLoadingShift
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadActiveShift,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (widget.user.geofencingEnabled) ...[
                      _buildGeofenceBanner(context),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryInfoCard(
                            icon: Icons.factory_outlined,
                            label: 'Plant',
                            value: _resolvePlantLabel(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryInfoCard(
                            icon: Icons.fire_truck,
                            label: 'Vehicle',
                            value: _selectedVehicleNumber ?? 'Not assigned',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _isAssigning ? null : _pickVehicle,
                        icon: _isAssigning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.swap_horiz),
                        label: Text(
                          _isAssigning ? 'Updating...' : 'Change Vehicle',
                        ),
                      ),
                    ),
                    if (widget.availableVehicles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'No vehicles are mapped yet. Contact supervisor to assign one.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.camera_alt,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Photo Capture',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Camera will open automatically when you click ${_currentActionLabel.toLowerCase()}. Photo will be saved to organized date folders.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.blue.shade600),
                          ),
                          if (_capturedPhoto != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _capturedPhoto!,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Photo captured successfully!',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.green.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: isButtonEnabled ? _handleCheckInOut : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: resolvedButtonColor,
                        disabledBackgroundColor: Colors.blueGrey.shade200,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  attendanceCompleted
                                      ? Icons.verified
                                      : Icons.camera_alt,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  buttonLabel,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                    ),
                    if (attendanceCompleted) ...[
                      const SizedBox(height: 12),
                      Text(
                        'You have already completed today\'s attendance.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blueGrey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _ShiftStatusCard(
                      actionLabel: _currentActionLabel,
                      hasOpenShift: _hasOpenShift,
                      hasCompletedToday: attendanceCompleted,
                      summary: _submissionSummary,
                      activeShift: _activeShift,
                      isSyncPending: _isSyncPending,
                      statusAnimation: (_hasOpenShift || _isSyncPending)
                          ? _statusAnimation
                          : null,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _updateStatusAnimation() {
    final shouldAnimate = _isSyncPending || _hasOpenShift;
    if (shouldAnimate) {
      if (!_statusController.isAnimating) {
        _statusController.repeat(reverse: true);
      }
    } else {
      if (_statusController.isAnimating) {
        _statusController.stop();
      }
    }
  }
}

class _SummaryInfoCard extends StatelessWidget {
  const _SummaryInfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftStatusCard extends StatelessWidget {
  const _ShiftStatusCard({
    required this.actionLabel,
    required this.hasOpenShift,
    required this.hasCompletedToday,
    required this.summary,
    required this.activeShift,
    required this.isSyncPending,
    this.statusAnimation,
  });

  final String actionLabel;
  final bool hasOpenShift;
  final bool hasCompletedToday;
  final String? summary;
  final AttendanceRecord? activeShift;
  final bool isSyncPending;
  final Animation<double>? statusAnimation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle =
        summary ??
        (isSyncPending
            ? 'Sync in progress.'
            : hasOpenShift
            ? 'Pending check-out.'
            : hasCompletedToday
            ? 'Attendance completed for today.'
            : 'No recent attendance yet.');
    final cardTitle = hasOpenShift
        ? 'Currently Checked-in'
        : hasCompletedToday
        ? 'Attendance Completed'
        : 'Ready to $actionLabel';
    final statusLabel = isSyncPending
        ? 'Pending sync'
        : hasOpenShift
        ? 'Open shift'
        : hasCompletedToday
        ? 'Done'
        : 'Ready';
    final baseChip = Chip(
      label: Text(statusLabel),
      backgroundColor: isSyncPending
          ? Colors.orange.shade200
          : hasOpenShift
          ? Colors.amber.shade200
          : hasCompletedToday
          ? Colors.lightGreen.shade200
          : Colors.lightBlue.shade200,
    );
    final statusChip = statusAnimation != null
        ? ScaleTransition(scale: statusAnimation!, child: baseChip)
        : baseChip;

    final cardColor = hasOpenShift
        ? Colors.amber.shade50
        : hasCompletedToday
        ? Colors.green.shade50
        : Colors.lightBlue.shade50;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cardTitle, style: theme.textTheme.titleMedium),
                statusChip,
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            if (activeShift != null) ...[
              const SizedBox(height: 12),
              _ShiftDetailRow(
                label: 'Checked in',
                value: _format(activeShift!.inTime),
              ),
              _ShiftDetailRow(
                label: 'Checked out',
                value: _format(activeShift!.outTime),
              ),
              _ShiftDetailRow(
                label: 'Vehicle',
                value:
                    activeShift!.vehicleNumber ?? activeShift!.vehicleId ?? '-',
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return DateFormat('dd MMM • HH:mm').format(parsed);
  }
}

class _ShiftDetailRow extends StatelessWidget {
  const _ShiftDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
