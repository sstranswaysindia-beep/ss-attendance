import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_approval.dart';
import '../../core/services/approvals_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';

// ── Design tokens ──
const Color _primaryDark = Color(0xFF0A2540);
const Color _accentTeal = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A2540);
const Color _gradientEnd = Color(0xFF1B5E7B);

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({
    required this.user,
    this.endpointOverride,
    this.title,
    this.userIdParamKey = 'supervisorUserId',
    super.key,
  });

  final AppUser user;
  final Uri? endpointOverride;
  final String? title;
  final String userIdParamKey;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  late final ApprovalsRepository _repository;

  bool _isLoading = true;
  String? _errorMessage;
  List<AttendanceApproval> _approvals = const [];
  List<SupervisorPlantOption> _plants = const [];
  final Set<String> _processingApprovals = <String>{};

  String _statusFilter = 'Pending';
  String? _plantFilter;
  String _searchQuery = '';
  late String _personFilter;
  DateTime _selectedDate = DateTime.now();
  String _rangeSelection = '30';
  int? _rangeDays = 30;

  @override
  void initState() {
    super.initState();
    _repository = ApprovalsRepository(endpoint: widget.endpointOverride);
    _personFilter = widget.user.role == UserRole.supervisor
        ? 'driver'
        : 'supervisor';
    _loadApprovals();
  }

  // ── Business logic (completely unchanged) ──

  Future<void> _loadApprovals() async {
    final supervisorId = widget.user.id;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _repository.fetchApprovals(
        supervisorUserId: supervisorId,
        userIdParamKey: widget.userIdParamKey,
        status: _statusFilter,
        date: _rangeDays != null
            ? null
            : DateFormat('yyyy-MM-dd').format(_selectedDate),
        plantId: _plantFilter,
        rangeDays: _rangeDays,
        roleFilter: _personFilter == 'all' ? null : _personFilter,
      );
      if (!mounted) return;
      setState(() {
        _approvals = response.approvals;
        _plants = response.plants;
        _isLoading = false;
      });
    } on ApprovalsFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
        _approvals = const [];
      });
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load approvals.';
      setState(() {
        _errorMessage = fallback;
        _isLoading = false;
        _approvals = const [];
      });
      showAppToast(context, fallback, isError: true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _rangeSelection = 'custom';
        _rangeDays = null;
      });
      await _loadApprovals();
    }
  }

  Future<bool?> _handleApprovalDismiss(
    AttendanceApproval approval,
    int index,
    DismissDirection direction,
  ) async {
    if (_processingApprovals.contains(approval.attendanceId)) return false;

    final statusLabel = approval.status?.isNotEmpty == true
        ? approval.status!
        : 'Pending';
    final normalizedStatus = statusLabel.toLowerCase();
    final isRejected = normalizedStatus == 'rejected';
    final isApprove = direction == DismissDirection.endToStart;
    String action;
    if (isRejected) {
      final confirmed = await _confirmDeleteRejected(approval);
      if (confirmed != true) return false;
      action = 'delete';
    } else {
      action = isApprove ? 'approve' : 'reject';
      if (!isApprove) {
        final confirmed = await _confirmReject(approval);
        if (confirmed != true) return false;
      }
    }
    final hasOutTime = (approval.outTime ?? '').trim().isNotEmpty;
    if (isApprove && !hasOutTime) {
      showAppToast(
        context,
        'Cannot approve until out punch is submitted.',
        isError: true,
      );
      return false;
    }

    setState(() => _processingApprovals.add(approval.attendanceId));

    try {
      await _repository.submitApprovalAction(
        supervisorUserId: widget.user.id,
        attendanceId: approval.attendanceId,
        action: action,
      );

      if (!mounted) return true;

      setState(() {
        _processingApprovals.remove(approval.attendanceId);
        final updated = List<AttendanceApproval>.of(_approvals);
        final removeIndex = updated.indexWhere(
          (item) => item.attendanceId == approval.attendanceId,
        );
        if (removeIndex >= 0) {
          updated.removeAt(removeIndex);
          _approvals = updated;
        }
      });

      if (mounted) {
        if (action == 'delete') {
          showAppToast(context, 'Rejected attendance deleted.');
        } else if (!isApprove) {
          showAppToast(context, 'Attendance rejected.');
        }
        if (isApprove) _showApproveSuccessAnimation();
        if (_statusFilter.toLowerCase() != 'pending') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadApprovals();
          });
        }
      }
      return true;
    } on ApprovalsFailure catch (error) {
      if (mounted) {
        showAppToast(context, error.message, isError: true);
        setState(() => _processingApprovals.remove(approval.attendanceId));
      }
      return false;
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Unable to update approval.', isError: true);
        setState(() => _processingApprovals.remove(approval.attendanceId));
      }
      return false;
    }
  }

  Future<void> _showApproveSuccessAnimation() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.15),
      builder: (_) => Center(
        child: SizedBox(
          width: 180,
          child: Lottie.asset(
            'assets/animations/check_mark_success.json',
            repeat: false,
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<bool?> _confirmReject(AttendanceApproval approval) {
    final inLabel = (approval.inTime ?? '').trim();
    final dateLabel = inLabel.isNotEmpty
        ? inLabel
        : DateFormat('dd MMM yyyy').format(_selectedDate);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject attendance?'),
        content: Text(
          'Reject attendance for ${approval.driverName} on $dateLabel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDeleteRejected(AttendanceApproval approval) {
    final inLabel = (approval.inTime ?? '').trim();
    final dateLabel = inLabel.isNotEmpty
        ? inLabel
        : DateFormat('dd MMM yyyy').format(_selectedDate);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete rejected attendance?'),
        content: Text(
          'Delete rejected attendance for ${approval.driverName} on $dateLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return Icons.check_circle_rounded;
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  // ── UI Helpers ──

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAvatar(AttendanceApproval approval) {
    final photoUrl = approval.profilePhotoUrl;
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      final uri = Uri.tryParse(photoUrl.trim());
      if (uri != null && uri.hasScheme && uri.hasAuthority) {
        return CircleAvatar(
          backgroundColor: Colors.white,
          backgroundImage: NetworkImage(photoUrl.trim()),
        );
      }
    }
    final initials = _extractInitials(approval.driverName);
    return CircleAvatar(
      backgroundColor: _accentTeal.withOpacity(0.15),
      foregroundColor: _primaryDark,
      child: Text(
        initials,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  String _extractInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // ── Filters sheet ──

  void _showFiltersSheet() {
    final rangeOptions = const {
      '3': 'Last 3 days',
      '7': 'Last 7 days',
      '30': 'Last 30 days',
      'custom': 'Custom date',
    };
    final roleOptions = const [
      {'value': 'supervisor', 'label': 'Supervisors'},
      {'value': 'driver', 'label': 'Drivers'},
      {'value': 'all', 'label': 'All'},
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _primaryDark,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Plant filter
                  DropdownButtonFormField<String>(
                    value: _plantFilter,
                    dropdownColor: Colors.white,
                    decoration: InputDecoration(
                      labelText: 'Plant',
                      prefixIcon: const Icon(
                        Icons.factory_rounded,
                        size: 18,
                        color: _accentTeal,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Plants'),
                      ),
                      ..._plants.map(
                        (plant) => DropdownMenuItem<String>(
                          value: plant.plantId,
                          child: Text(plant.plantName),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setSheetState(() => _plantFilter = value);
                      setState(() => _plantFilter = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  // Range filter
                  DropdownButtonFormField<String>(
                    value: _rangeSelection,
                    dropdownColor: Colors.white,
                    decoration: InputDecoration(
                      labelText: 'Date Range',
                      prefixIcon: const Icon(
                        Icons.date_range_rounded,
                        size: 18,
                        color: _accentTeal,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: rangeOptions.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      if (value == 'custom') {
                        Navigator.pop(context);
                        _pickDate();
                        return;
                      }
                      final parsed = int.tryParse(value);
                      setSheetState(() {
                        _rangeSelection = value;
                        _rangeDays = parsed;
                      });
                      setState(() {
                        _rangeSelection = value;
                        _rangeDays = parsed;
                        _selectedDate = DateTime.now();
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  // Person type
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Person Type',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: roleOptions
                        .map((option) {
                          final selected = option['value'] == _personFilter;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  setSheetState(
                                    () => _personFilter = option['value']!,
                                  );
                                  setState(
                                    () => _personFilter = option['value']!,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: selected
                                        ? const LinearGradient(
                                            colors: [_primaryDark, _accentTeal],
                                          )
                                        : null,
                                    color: selected
                                        ? null
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? Colors.transparent
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    option['label']!,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 20),
                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_primaryDark, _accentTeal],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _loadApprovals();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredByRole = _personFilter == 'all'
        ? _approvals
        : _approvals
              .where((a) => a.role.toLowerCase() == _personFilter.toLowerCase())
              .toList(growable: false);
    final visibleApprovals = _searchQuery.isEmpty
        ? filteredByRole
        : filteredByRole
              .where(
                (a) => a.driverName.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      resizeToAvoidBottomInset: false,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 204,
              floating: false,
              pinned: true,
              centerTitle: true,
              backgroundColor: _gradientStart,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  onPressed: _showFiltersSheet,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Filters',
                ),
                IconButton(
                  onPressed: _isLoading ? null : _loadApprovals,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Reload',
                ),
              ],
              title: Text(
                widget.title ?? 'Approvals',
                style: const TextStyle(
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
                      colors: [_gradientStart, _gradientEnd, Color(0xFF0D4F6B)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 34, 20, 82),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [_buildHeroCard(visibleApprovals.length)],
                      ),
                    ),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(66),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
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
                  child: _buildStatusFilterStrip(),
                ),
              ),
            ),
          ];
        },
        body: RefreshIndicator(
          onRefresh: _loadApprovals,
          color: _accentTeal,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  scrollPadding: EdgeInsets.zero,
                  decoration: InputDecoration(
                    hintText: 'Search by name...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim()),
                ),
              ),
              if (!_isLoading &&
                  _errorMessage == null &&
                  visibleApprovals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.swipe_rounded,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Swipe left to approve · right to reject',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: AppLoader()),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                )
              else if (visibleApprovals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No approvals found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...visibleApprovals.asMap().entries.map(
                  (entry) => _buildApprovalCard(entry.value, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero Card ──

  Widget _buildStatusFilterStrip() {
    return SizedBox(
      height: 56,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        scrollDirection: Axis.horizontal,
        children: ['Pending', 'Approved', 'Rejected', 'All']
            .map((status) {
              final selected = _statusFilter == status;
              final chipColor = switch (status) {
                'Approved' => Colors.green,
                'Rejected' => Colors.red,
                'Pending' => Colors.orange,
                _ => _primaryDark,
              };
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _statusFilter = status);
                    _loadApprovals();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.fromLTRB(15, 7, 15, 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? chipColor.withOpacity(0.12)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected ? chipColor : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: selected ? chipColor : Colors.grey.shade600,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _buildHeroCard(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isLoading ? 'Loading...' : '$count entries',
                style: const TextStyle(
                  color: Color(0xFF7CFFB2),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_statusFilter == 'All' ? 'All' : _statusFilter} approvals',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          _heroMiniStat(
            Icons.date_range_rounded,
            _rangeSelection == 'custom'
                ? DateFormat('dd MMM').format(_selectedDate)
                : 'Last ${_rangeDays}d',
          ),
        ],
      ),
    );
  }

  Widget _heroMiniStat(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── Approval Card ──

  Widget _buildApprovalCard(AttendanceApproval approval, int index) {
    final statusLabel = approval.status?.isNotEmpty == true
        ? approval.status!
        : 'Pending';
    final normalizedStatus = statusLabel.toLowerCase();
    final isPending = normalizedStatus == 'pending';
    final isRejected = normalizedStatus == 'rejected';
    final isApproved = normalizedStatus == 'approved';
    final isProcessing = _processingApprovals.contains(approval.attendanceId);
    final sColor = _statusColor(statusLabel);
    final rawOut = approval.outTime?.trim() ?? '';
    final outDisplay = rawOut.isEmpty ? 'Pending' : rawOut;
    final hasTripToday = approval.tripMatched;

    Widget content = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              _buildAvatar(approval),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            approval.driverName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Trip badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hasTripToday
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: hasTripToday
                                  ? Colors.green.shade400
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasTripToday
                                    ? Icons.local_shipping
                                    : Icons.local_shipping_outlined,
                                size: 10,
                                color: hasTripToday
                                    ? Colors.green.shade700
                                    : Colors.red.shade600,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                hasTripToday ? 'Trip' : 'No Trip',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: hasTripToday
                                      ? Colors.green.shade700
                                      : Colors.red.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      approval.plantName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _statusPill(statusLabel, sColor),
            ],
          ),
          const SizedBox(height: 6),
          // Time bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.login_rounded,
                  size: 14,
                  color: Colors.green.shade500,
                ),
                Text(
                  approval.inTime ?? '-',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.logout_rounded,
                  size: 14,
                  color: outDisplay == 'Pending'
                      ? Colors.orange
                      : Colors.blue.shade500,
                ),
                Text(
                  outDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: outDisplay == 'Pending'
                        ? Colors.orange
                        : Colors.grey.shade700,
                  ),
                ),
                if ((approval.vehicleNumber ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.directions_car_rounded,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  Text(
                    approval.vehicleNumber!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
          // Notes
          if ((approval.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notes_rounded,
                  size: 14,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    approval.notes!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (isProcessing) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0x66FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!isPending && !isRejected && !isApproved) return content;

    DismissDirection dismissDirection;
    Widget leadingBackground = const SizedBox.shrink();
    Widget trailingBackground = const SizedBox.shrink();

    if (isPending) {
      dismissDirection = DismissDirection.horizontal;
      leadingBackground = _buildSwipeBackground(
        alignment: Alignment.centerLeft,
        color: Colors.red.shade50,
        icon: Icons.close_rounded,
        label: 'Reject',
        labelColor: Colors.red.shade600,
      );
      trailingBackground = _buildSwipeBackground(
        alignment: Alignment.centerRight,
        color: Colors.green.shade50,
        icon: Icons.check_rounded,
        label: 'Approve',
        labelColor: Colors.green.shade600,
      );
    } else if (isRejected) {
      dismissDirection = DismissDirection.startToEnd;
      leadingBackground = _buildSwipeBackground(
        alignment: Alignment.centerLeft,
        color: Colors.red.shade50,
        icon: Icons.delete_rounded,
        label: 'Delete',
        labelColor: Colors.red.shade600,
      );
    } else {
      dismissDirection = DismissDirection.startToEnd;
      leadingBackground = _buildSwipeBackground(
        alignment: Alignment.centerLeft,
        color: Colors.red.shade50,
        icon: Icons.close_rounded,
        label: 'Reject',
        labelColor: Colors.red.shade600,
      );
    }

    return Dismissible(
      key: ValueKey('approval_${approval.attendanceId}'),
      direction: dismissDirection,
      background: leadingBackground,
      secondaryBackground: trailingBackground,
      confirmDismiss: (direction) =>
          _handleApprovalDismiss(approval, index, direction),
      child: content,
    );
  }

  Widget _buildSwipeBackground({
    required AlignmentGeometry alignment,
    required Color color,
    required IconData icon,
    required String label,
    required Color labelColor,
  }) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: labelColor, size: 20),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
