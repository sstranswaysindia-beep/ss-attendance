import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../../core/models/app_user.dart';
import '../../core/widgets/app_toast.dart';

const Color _adminPrimaryColor = Color(0xFF00296B);
const Color _submitButtonColor = Color(0xFF2E7D32);
const Color _draftButtonColor = Color(0xFFF2994A);
const Color _applicationContainerColor = Color(0xFFE9FCE9);
const Color _formCardColor = Color(0xFFEFF6FF);
const Color _reasonFieldColor = Color(0xFFFFF6D5);

Future<void> showApplyLeaveSheet(BuildContext context, AppUser user) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _ApplyLeaveSheet(user: user);
    },
  );
}

class ApplyLeaveScreen extends StatefulWidget {
  const ApplyLeaveScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _adminPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Apply Leave',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: ApplyLeaveForm(
          user: widget.user,
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class _ApplyLeaveSheet extends StatelessWidget {
  const _ApplyLeaveSheet({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  color: _adminPrimaryColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Apply Leave',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ApplyLeaveForm(
                  user: user,
                  scrollController: scrollController,
                  onCancel: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ApplyLeaveForm extends StatefulWidget {
  const ApplyLeaveForm({
    required this.user,
    this.scrollController,
    this.onCancel,
    super.key,
  });

  final AppUser user;
  final ScrollController? scrollController;
  final VoidCallback? onCancel;

  @override
  State<ApplyLeaveForm> createState() => _ApplyLeaveFormState();
}

class _ApplyLeaveFormState extends State<ApplyLeaveForm> {
  static const String _submitUrl =
      'https://sstranswaysindia.com/api/mobile/leave_request_submit.php';
  static const String _listUrl =
      'https://sstranswaysindia.com/api/mobile/leave_request_list.php';
  static const String _deleteUrl =
      'https://sstranswaysindia.com/api/mobile/leave_request_delete.php';
  static const List<String> _leaveTypes = <String>[
    'Casual Leave',
    'Sick Leave',
    'Half Day Leave',
  ];

  static const List<String> _durations = <String>[
    'Full Day',
    'Half Day',
  ];

  static const List<String> _halfDaySessions = <String>[
    'First Half',
    'Second Half',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();

  String? _selectedLeaveType;
  String _selectedDuration = _durations.first;
  String? _selectedHalfDaySession;
  DateTime? _startDate;
  DateTime? _endDate;
  double? _totalDays;
  bool _isSubmitting = false;

  bool _isLoadingRequests = false;
  String? _requestError;
  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    _selectedLeaveType = _leaveTypes.first;
    _loadRequests();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _recalculateTotalDays() {
    if (_startDate == null) {
      setState(() => _totalDays = null);
      return;
    }

    final DateTime? end = _endDate ?? _startDate;
    if (end == null) {
      setState(() => _totalDays = null);
      return;
    }
    if (end.isBefore(_startDate!)) {
      setState(() => _totalDays = null);
      return;
    }

    if (_selectedDuration == 'Half Day') {
      setState(() => _totalDays = 0.5);
      return;
    }

    final days = end.difference(_startDate!).inDays + 1;
    setState(() => _totalDays = days.toDouble());
  }

  int? _resolveDriverId() {
    return int.tryParse(widget.user.driverId ?? '') ??
        int.tryParse(widget.user.id);
  }

  Future<void> _loadRequests() async {
    final driverId = _resolveDriverId();
    if (driverId == null) {
      setState(() {
        _requestError = 'Driver ID is missing.';
        _requests = const [];
      });
      return;
    }

    setState(() {
      _isLoadingRequests = true;
      _requestError = null;
    });

    try {
      final response = await http.post(
        Uri.parse(_listUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId, 'limit': 10}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['status'] == 'ok') {
        final items = (data['requests'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        if (mounted) {
          setState(() => _requests = items);
        }
      } else {
        final error = data['error']?.toString() ?? 'Unable to load requests.';
        if (mounted) {
          setState(() {
            _requestError = error;
            _requests = const [];
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _requestError = 'Unable to load requests.';
          _requests = const [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingRequests = false);
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            dialogBackgroundColor: Colors.white,
            colorScheme: theme.colorScheme.copyWith(
              background: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_selectedDuration == 'Half Day') {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
    _recalculateTotalDays();
  }

  void _handleDurationChange(String? value) {
    if (value == null) return;
    setState(() {
      _selectedDuration = value;
      if (_selectedDuration == 'Half Day') {
        _selectedHalfDaySession ??= _halfDaySessions.first;
        if (_startDate != null) {
          _endDate = _startDate;
        }
      } else {
        _selectedHalfDaySession = null;
      }
    });
    _recalculateTotalDays();
  }

  Future<void> _submit({required bool asDraft}) async {
    if (_isSubmitting) return;

    if (!asDraft && !_formKey.currentState!.validate()) {
      return;
    }

    if (!asDraft) {
      if (_startDate == null || _endDate == null) {
        showAppToast(context, 'Please select leave dates.', isError: true);
        return;
      }

      if (_endDate!.isBefore(_startDate!)) {
        showAppToast(context, 'End date cannot be before start date.',
            isError: true);
        return;
      }

      if (_selectedDuration == 'Half Day' &&
          !_isSameDay(_startDate!, _endDate!)) {
        showAppToast(context, 'Half day leave must be for a single date.',
            isError: true);
        return;
      }
    }

    final driverId = _resolveDriverId();
    final requestedById = int.tryParse(widget.user.id);

    if (_selectedLeaveType == null || _selectedLeaveType!.isEmpty) {
      showAppToast(context, 'Please select leave type.', isError: true);
      return;
    }

    if (_startDate == null || _endDate == null) {
      showAppToast(context, 'Please select leave dates.', isError: true);
      return;
    }

    if (driverId == null || requestedById == null) {
      showAppToast(context, 'User IDs are missing.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse(_submitUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driverId': driverId,
          'requestedById': requestedById,
          'leaveType': _selectedLeaveType,
          'startDate': _startDate?.toIso8601String(),
          'endDate': _endDate?.toIso8601String(),
          'totalDays': _totalDays ?? 0,
          'duration': _selectedDuration,
          'halfDaySession': _selectedHalfDaySession ?? '',
          'reason': _reasonController.text.trim(),
          'status': asDraft ? 'Draft' : 'Pending',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['status'] == 'ok') {
        showAppToast(
          context,
          asDraft ? 'Leave request saved as draft.' : 'Leave request submitted.',
        );
        await _loadRequests();
        if (!asDraft) {
          _formKey.currentState?.reset();
          _reasonController.clear();
          setState(() {
            _selectedLeaveType = null;
            _selectedDuration = _durations.first;
            _selectedHalfDaySession = null;
            _startDate = null;
            _endDate = null;
            _totalDays = null;
          });
        }
      } else {
        showAppToast(
          context,
          data['error']?.toString() ?? 'Unable to submit leave request.',
          isError: true,
        );
      }
    } catch (e) {
      showAppToast(context, 'Network error. Try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _deleteRequest(int requestId) async {
    final requestedById = int.tryParse(widget.user.id);
    if (requestedById == null) {
      showAppToast(context, 'User ID missing.', isError: true);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(_deleteUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'leaveRequestId': requestId,
          'requestedById': requestedById,
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['status'] == 'ok') {
        showAppToast(context, 'Leave request deleted.');
        await _loadRequests();
      } else {
        showAppToast(
          context,
          data['error']?.toString() ?? 'Unable to delete request.',
          isError: true,
        );
      }
    } catch (_) {
      showAppToast(context, 'Network error. Try again.', isError: true);
    }
  }

  Future<void> _confirmDelete(int requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete request?'),
        content:
            const Text('This will remove the leave request permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteRequest(requestId);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('dd-MM-yyyy').format(date);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green.shade600;
      case 'rejected':
        return Colors.red.shade600;
      case 'draft':
        return Colors.grey.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = (request['status'] ?? 'Pending').toString();
    final type = (request['leave_type'] ?? '').toString();
    final start = (request['leave_start_date'] ?? '').toString();
    final end = (request['leave_end_date'] ?? '').toString();
    final days = (request['total_days'] ?? '').toString();
    final appliedOn = (request['applied_on'] ?? '').toString();
    final managerRemarks = (request['manager_remarks'] ?? '').toString();
    final duration = (request['leave_duration'] ?? '').toString();
    final halfSession = (request['half_day_session'] ?? '').toString();
    final requestId = int.tryParse(request['id']?.toString() ?? '');
    final canDelete = status.toLowerCase() == 'draft' ||
        status.toLowerCase() == 'pending';

    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    type.isEmpty ? 'Leave Request' : type,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (canDelete && requestId != null)
                  IconButton(
                    onPressed: () => _confirmDelete(requestId),
                    icon: const Icon(Icons.delete, size: 20),
                    color: Colors.red.shade600,
                    tooltip: 'Delete',
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Dates: $start to $end'),
            Text(
              'Days: $days • $duration'
              '${halfSession.isNotEmpty ? ' ($halfSession)' : ''}',
            ),
            if (appliedOn.isNotEmpty) Text('Applied: $appliedOn'),
            if (managerRemarks.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Manager Remarks: $managerRemarks',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsSection(TextTheme textTheme) {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requestError != null) {
      return Text(
        _requestError!,
        style: textTheme.bodyMedium?.copyWith(color: Colors.red.shade700),
      );
    }
    if (_requests.isEmpty) {
      return Text(
        'No leave applications yet.',
        style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
      );
    }
    return Column(
      children: _requests.map(_buildRequestCard).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalDaysLabel =
        _totalDays == null ? '' : _totalDays!.toStringAsFixed(1);

    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: Colors.white,
        highlightColor: Colors.white,
        splashColor: Colors.transparent,
        dropdownMenuTheme: const DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Colors.white),
          ),
        ),
      ),
      child: Container(
        color: Colors.white,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Leave Application',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Submit your leave request with accurate dates and reason.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0.5,
                  color: _formCardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedLeaveType,
                          items: _leaveTypes
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            labelText: 'Type of Leave',
                          ),
                          dropdownColor: Colors.white,
                          validator: (value) => value == null || value.isEmpty
                              ? 'Select leave type'
                              : null,
                          onChanged: (value) {
                            setState(() => _selectedLeaveType = value);
                          },
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickDate(isStart: true),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Leave Start Date',
                                ),
                                child: Text(
                                  _formatDate(_startDate),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickDate(isStart: false),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Leave End Date',
                                ),
                                child: Text(
                                  _formatDate(_endDate),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Total Number of Leave Days',
                        ),
                        child: Text(totalDaysLabel),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedDuration,
                        items: _durations
                            .map(
                              (duration) => DropdownMenuItem(
                                value: duration,
                                child: Text(duration),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'Leave Duration',
                        ),
                        dropdownColor: Colors.white,
                        onChanged: _handleDurationChange,
                      ),
                      if (_selectedDuration == 'Half Day') ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedHalfDaySession,
                          items: _halfDaySessions
                              .map(
                                (session) => DropdownMenuItem(
                                  value: session,
                                  child: Text(session),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            labelText: 'Half Day Session',
                          ),
                          dropdownColor: Colors.white,
                          validator: (value) => value == null || value.isEmpty
                              ? 'Select session'
                              : null,
                          onChanged: (value) {
                            setState(() => _selectedHalfDaySession = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _reasonController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Reason / Purpose of Leave',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: _reasonFieldColor,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Reason is required'
                                : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isSubmitting ? null : () => _submit(asDraft: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _draftButtonColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save as Draft'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isSubmitting ? null : () => _submit(asDraft: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _submitButtonColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 24),
              Text(
                'Your Applications',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: _applicationContainerColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: _buildRequestsSection(theme.textTheme),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
