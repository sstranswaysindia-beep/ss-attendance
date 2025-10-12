import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class AttendanceAdjustRequestScreen extends StatefulWidget {
  const AttendanceAdjustRequestScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AttendanceAdjustRequestScreen> createState() =>
      _AttendanceAdjustRequestScreenState();
}

class _AttendanceAdjustRequestScreenState
    extends State<AttendanceAdjustRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _inTimeController = TextEditingController();
  final _outTimeController = TextEditingController();
  final _reasonController = TextEditingController();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  bool _isSubmitting = false;
  TimeOfDay? _selectedInTime;
  TimeOfDay? _selectedOutTime;

  @override
  void dispose() {
    _inTimeController.dispose();
    _outTimeController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime({required bool isIn}) async {
    final fallback = TimeOfDay.now();
    final initial = isIn
        ? (_selectedInTime ?? fallback)
        : (_selectedOutTime ?? fallback);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isIn) {
          _selectedInTime = picked;
          _inTimeController.text = picked.format(context);
        } else {
          _selectedOutTime = picked;
          _outTimeController.text = picked.format(context);
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // For supervisors without driver_id, use user ID instead
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'User mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    final inTimeOfDay = _selectedInTime;
    final outTimeOfDay = _selectedOutTime;
    if (inTimeOfDay == null || outTimeOfDay == null) {
      showAppToast(context, 'Provide valid in and out time.', isError: true);
      return;
    }

    final proposedIn = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      inTimeOfDay.hour,
      inTimeOfDay.minute,
    );
    var proposedOut = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      outTimeOfDay.hour,
      outTimeOfDay.minute,
    );

    if (!proposedOut.isAfter(proposedIn)) {
      showAppToast(context, 'Out time must be after in time.', isError: true);
      return;
    }

    final reason = _reasonController.text.trim();

    final requestedById = widget.user.id;
    final plantId = widget.user.assignmentPlantId?.isNotEmpty == true
        ? widget.user.assignmentPlantId
        : widget.user.plantId;
    final vehicleId = widget.user.assignmentVehicleId?.isNotEmpty == true
        ? widget.user.assignmentVehicleId
        : (widget.user.availableVehicles.isNotEmpty
              ? widget.user.availableVehicles.first.id
              : null);

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
        'Vehicle mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _attendanceRepository.submitAdjustRequest(
        driverId: driverId,
        requestedById: requestedById,
        proposedIn: proposedIn,
        proposedOut: proposedOut,
        reason: reason,
        plantId: plantId,
        vehicleId: vehicleId,
      );
      if (!mounted) return;
      showAppToast(context, 'Request submitted for approval');
      Navigator.of(context).pop(true);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to submit request.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd-MM-yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text('Past Attendance Request')),
      body: AppGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(dateLabel),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: _pickDate,
                  ),
                ),
                TextFormField(
                  controller: _inTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'In Time'),
                  onTap: () => _pickTime(isIn: true),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Provide in time' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _outTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Out Time'),
                  onTap: () => _pickTime(isIn: false),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Provide out time'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please describe the reason'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
