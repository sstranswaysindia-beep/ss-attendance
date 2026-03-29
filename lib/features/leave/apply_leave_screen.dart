import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../../core/models/app_user.dart';
import '../../core/widgets/app_toast.dart';

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
      backgroundColor: _surfaceBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            backgroundColor: _gradientEnd,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            title: const Text(
              'Apply Leave',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
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
                    padding: const EdgeInsets.fromLTRB(20, 34, 20, 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.18)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_accentTeal, _heroGreen],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.event_note_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Leave Application',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Submit your request with dates & reason',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.65),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ApplyLeaveForm(
              user: widget.user,
              onCancel: () => Navigator.of(context).pop(),
            ),
          ),
        ],
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
            color: _surfaceBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ─── Premium Handle Bar ───
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_gradientStart, _gradientEnd],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_accentTeal, _heroGreen],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.event_note_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Apply Leave',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
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

class _ApplyLeaveFormState extends State<ApplyLeaveForm>
    with SingleTickerProviderStateMixin {
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

  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _selectedLeaveType = _leaveTypes.first;
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadRequests();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _staggerController.forward();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _staggerController.dispose();
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
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _gradientEnd,
              onPrimary: Colors.white,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'draft':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle_outline_rounded;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'draft':
        return Icons.edit_note_rounded;
      default:
        return Icons.schedule_rounded;
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
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_statusIcon(status), color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  type.isEmpty ? 'Leave Request' : type,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF12243A),
                  ),
                ),
              ),
              if (canDelete && requestId != null)
                GestureDetector(
                  onTap: () => _confirmDelete(requestId),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.28)),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _gradientStart.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildRequestDetailRow(Icons.date_range_rounded, 'Dates', '$start → $end'),
                const SizedBox(height: 6),
                _buildRequestDetailRow(
                  Icons.timer_outlined,
                  'Duration',
                  '$days days • $duration${halfSession.isNotEmpty ? ' ($halfSession)' : ''}',
                ),
                if (appliedOn.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildRequestDetailRow(Icons.schedule_rounded, 'Applied', appliedOn),
                ],
              ],
            ),
          ),
          if (managerRemarks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accentGold.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accentGold.withOpacity(0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.comment_outlined, size: 14, color: _accentGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      managerRemarks,
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12.5,
                        color: Color(0xFF374151),
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

  Widget _buildRequestDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF6C7A8F)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6C7A8F),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF12243A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsSection() {
    if (_isLoadingRequests) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: _accentTeal),
        ),
      );
    }
    if (_requestError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _requestError!,
          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
        ),
      );
    }
    if (_requests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No leave applications yet.',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: _requests.map(_buildRequestCard).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDaysLabel =
        _totalDays == null ? '' : _totalDays!.toStringAsFixed(1);

    final formWidgets = <Widget>[
      // ─── Form Card ───
      _buildFormCard(totalDaysLabel),
      // ─── Action Buttons ───
      _buildActionButtons(),
      // ─── Applications Section ───
      _buildApplicationsSection(),
    ];

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
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        child: Form(
          key: _formKey,
          child: AnimatedBuilder(
            animation: _staggerController,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(formWidgets.length, (index) {
                  final start = (index * 0.2).clamp(0.0, 1.0);
                  final end = (start + 0.5).clamp(0.0, 1.0);
                  final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _staggerController,
                      curve: Interval(start, end, curve: Curves.easeOutCubic),
                    ),
                  );
                  return Transform.translate(
                    offset: Offset(0, 30 * (1 - anim.value)),
                    child: Opacity(
                      opacity: anim.value,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: index < formWidgets.length - 1 ? 16 : 0,
                        ),
                        child: formWidgets[index],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(String totalDaysLabel) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: _gradientStart.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_gradientStart, _accentTeal],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leave Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF12243A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Fill in your leave information below',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6C7A8F),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
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
            decoration: _premiumInputDecoration('Type of Leave', Icons.category_outlined),
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
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: _premiumInputDecoration('Start Date', Icons.date_range_rounded),
                    child: Text(
                      _formatDate(_startDate),
                      style: TextStyle(
                        color: _startDate != null ? const Color(0xFF12243A) : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(isStart: false),
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: _premiumInputDecoration('End Date', Icons.date_range_rounded),
                    child: Text(
                      _formatDate(_endDate),
                      style: TextStyle(
                        color: _endDate != null ? const Color(0xFF12243A) : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Total days display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accentTeal.withOpacity(0.06), _heroGreen.withOpacity(0.04)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accentTeal.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.event_available_rounded, size: 18, color: _accentTeal),
                const SizedBox(width: 10),
                const Text(
                  'Total Leave Days',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6C7A8F),
                  ),
                ),
                const Spacer(),
                Text(
                  totalDaysLabel.isEmpty ? '—' : totalDaysLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: totalDaysLabel.isEmpty ? Colors.grey : _gradientStart,
                  ),
                ),
              ],
            ),
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
            decoration: _premiumInputDecoration('Leave Duration', Icons.timer_outlined),
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
              decoration: _premiumInputDecoration('Half Day Session', Icons.wb_sunny_outlined),
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
            decoration: _premiumInputDecoration(
              'Reason / Purpose of Leave',
              Icons.subject_rounded,
            ).copyWith(
              alignLabelWithHint: true,
              filled: true,
              fillColor: _accentGold.withOpacity(0.04),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty
                    ? 'Reason is required'
                    : null,
          ),
        ],
      ),
    );
  }

  InputDecoration _premiumInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, size: 18, color: _gradientEnd),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accentTeal, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accentGold, _accentGold.withOpacity(0.85)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _accentGold.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmitting ? null : () => _submit(asDraft: true),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Save Draft',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_gradientStart, _accentTeal],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _accentTeal.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmitting ? null : () => _submit(asDraft: false),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Submit',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApplicationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.list_alt_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              'Your Applications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildRequestsSection(),
      ],
    );
  }
}
