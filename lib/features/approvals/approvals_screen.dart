import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_approval.dart';
import '../../core/services/approvals_repository.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/app_loader.dart';

const Color _adminPrimaryColor = Color(0xFF00296B);
const Color _adminAccentLight = Color(0xFFE3F2FD);
const Color _adminPendingColor = Color(0xFFFFBB39);

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

class _ApprovalSwipeBackground extends StatelessWidget {
  const _ApprovalSwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final AlignmentGeometry alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium;
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(width: 8),
          Text(label, style: textStyle),
        ],
      ),
    );
  }
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
    _personFilter =
        widget.user.role == UserRole.supervisor ? 'driver' : 'supervisor';
    _loadApprovals();
  }

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
    if (_processingApprovals.contains(approval.attendanceId)) {
      return false;
    }

    final statusLabel =
        approval.status?.isNotEmpty == true ? approval.status! : 'Pending';
    final normalizedStatus = statusLabel.toLowerCase();
    final isRejected = normalizedStatus == 'rejected';
    final isApprove = direction == DismissDirection.endToStart;
    String action;
    if (isRejected) {
      final confirmed = await _confirmDeleteRejected(approval);
      if (confirmed != true) {
        return false;
      }
      action = 'delete';
    } else {
      action = isApprove ? 'approve' : 'reject';
      if (!isApprove) {
        final confirmed = await _confirmReject(approval);
        if (confirmed != true) {
          return false;
        }
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

      if (!mounted) {
        return true;
      }

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
        } else {
          showAppToast(
            context,
            isApprove ? 'Attendance approved.' : 'Attendance rejected.',
          );
        }
        if (isApprove) {
          _showApproveSuccessAnimation();
        }
        if (_statusFilter.toLowerCase() != 'pending') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadApprovals();
            }
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
    if (!mounted) {
      return;
    }

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

  Color _statusChipColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green.shade100;
      case 'rejected':
        return Colors.red.shade100;
      default:
        return _adminPendingColor;
    }
  }

  Color _chipLabelColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green.shade900;
      case 'rejected':
        return Colors.red.shade900;
      default:
        return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusOptions = const ['Pending', 'Approved', 'Rejected', 'All'];
    final formattedDate = DateFormat('dd-MM-yyyy').format(_selectedDate);
    final rangeOptions = const {
      '3': 'Last 3 days',
      '7': 'Last 7 days',
      '30': 'Last 30 days',
      'custom': 'Custom date',
    };
    final filteredByRole = _personFilter == 'all'
        ? _approvals
        : _approvals
            .where(
              (approval) =>
                  approval.role.toLowerCase() == _personFilter.toLowerCase(),
            )
            .toList(growable: false);
    final visibleApprovals = _searchQuery.isEmpty
        ? filteredByRole
        : filteredByRole
            .where(
              (approval) =>
                  approval.driverName.toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ),
            )
            .toList(growable: false);
    final roleOptions = const [
      {'value': 'supervisor', 'label': 'Supervisors'},
      {'value': 'driver', 'label': 'Drivers'},
      {'value': 'all', 'label': 'All'},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _adminPrimaryColor,
        foregroundColor: Colors.white,
        title: Text(
          widget.title ?? 'Approvals',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: Container(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _plantFilter,
                      decoration: const InputDecoration(labelText: 'Plant'),
                      dropdownColor: Colors.white,
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
                        setState(() => _plantFilter = value);
                        _loadApprovals();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _rangeSelection,
                      decoration: const InputDecoration(labelText: 'Range'),
                      dropdownColor: Colors.white,
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
                          _pickDate();
                          return;
                        }
                        final parsed = int.tryParse(value);
                        setState(() {
                          _rangeSelection = value;
                          _rangeDays = parsed;
                          _selectedDate = DateTime.now();
                        });
                        _loadApprovals();
                      },
                    ),
                  ),
                ],
              ),
              if (_rangeSelection == 'custom') ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Custom date'),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formattedDate),
                        const Icon(Icons.calendar_month),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _statusFilter,
                      decoration: const InputDecoration(labelText: 'Status'),
                      dropdownColor: Colors.white,
                      items: statusOptions
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _statusFilter = value);
                        _loadApprovals();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Person type',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 6),
                        ToggleButtons(
                          isSelected: roleOptions
                              .map((option) =>
                                  option['value'] == _personFilter)
                              .toList(),
                          borderRadius: BorderRadius.circular(12),
                          constraints: const BoxConstraints(minHeight: 40),
                          onPressed: (index) {
                            final selected = roleOptions[index]['value']!;
                            if (selected == _personFilter) return;
                            setState(() => _personFilter = selected);
                            _loadApprovals();
                          },
                          children: roleOptions
                              .map(
                                (option) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(option['label']!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Search driver name',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _loadApprovals,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Refresh'),
                    style: TextButton.styleFrom(
                      backgroundColor: _adminPrimaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              if (!_isLoading &&
                  _errorMessage == null &&
                  visibleApprovals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: const [
                      Icon(Icons.swipe, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Swipe left to approve and right to reject pending entries. Rejected entries can be swiped right to delete.',
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(child: AppLoader())
                    : _errorMessage != null
                        ? Center(
                            child: Text(
                              _errorMessage!,
                              style: theme.textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : visibleApprovals.isEmpty
                            ? Center(
                                child: Text(
                                  'No approvals for ${DateFormat('dd MMM yyyy').format(_selectedDate)}.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1400296B),
                                      blurRadius: 18,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: visibleApprovals.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final approval = visibleApprovals[index];
                            final statusLabel =
                                approval.status?.isNotEmpty == true
                                ? approval.status!
                                : 'Pending';
                            final normalizedStatus = statusLabel.toLowerCase();
                            final isPending = normalizedStatus == 'pending';
                            final isRejected = normalizedStatus == 'rejected';
                            final isApproved = normalizedStatus == 'approved';
                            final isProcessing = _processingApprovals.contains(
                              approval.attendanceId,
                            );

                            final rawOut = approval.outTime?.trim() ?? '';
                            final outDisplay = rawOut.isEmpty
                                ? 'Pending'
                                : rawOut;

                            final subtitleLines = <String>[
                              'Plant: ${approval.plantName}',
                              if ((approval.vehicleNumber ?? '').isNotEmpty)
                                'Vehicle: ${approval.vehicleNumber}',
                              'In: ${approval.inTime ?? '-'}',
                              'Out: $outDisplay',
                            ];
                            if ((approval.notes ?? '').isNotEmpty) {
                              subtitleLines.add('Notes: ${approval.notes}');
                            }

                            Widget content = Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.white, _adminAccentLight],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _adminPrimaryColor.withOpacity(0.06),
                                ),
                              ),
                              child: ListTile(
                                leading: _buildAvatar(approval),
                                title: Text(
                                  approval.driverName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(subtitleLines.join('\n')),
                                trailing: Chip(
                                  label: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: _chipLabelColor(statusLabel),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  backgroundColor: _statusChipColor(
                                    statusLabel,
                                  ),
                                  side: BorderSide(
                                    color: _chipLabelColor(
                                      statusLabel,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                              ),
                            );

                            if (isProcessing) {
                              content = Stack(
                                children: [
                                  content,
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Color(0x66FFFFFF),
                                      child: Center(
                                        child: SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (!isPending && !isRejected && !isApproved) {
                              return content;
                            }

                            DismissDirection dismissDirection;
                            Widget leadingBackground = const SizedBox.shrink();
                            Widget trailingBackground = const SizedBox.shrink();

                            if (isPending) {
                              dismissDirection = DismissDirection.horizontal;
                              leadingBackground =
                                  const _ApprovalSwipeBackground(
                                    alignment: Alignment.centerLeft,
                                    color: Color(0xFFFFE5E5),
                                    icon: Icons.close,
                                    label: 'Reject',
                                  );
                              trailingBackground = _ApprovalSwipeBackground(
                                alignment: Alignment.centerRight,
                                color: const Color(0xFFE5F6E5),
                                icon: Icons.check,
                                label: 'Approve',
                              );
                            } else if (isRejected) {
                              dismissDirection = DismissDirection.startToEnd;
                              leadingBackground = const _ApprovalSwipeBackground(
                                alignment: Alignment.centerLeft,
                                color: Color(0xFFFFE5E5),
                                icon: Icons.delete,
                                label: 'Delete',
                              );
                            } else {
                              dismissDirection = DismissDirection.startToEnd;
                              leadingBackground =
                                  const _ApprovalSwipeBackground(
                                    alignment: Alignment.centerLeft,
                                    color: Color(0xFFFFE5E5),
                                    icon: Icons.close,
                                    label: 'Reject',
                                  );
                            }

                            return Dismissible(
                              key: ValueKey(
                                'approval_${approval.attendanceId}',
                              ),
                              direction: dismissDirection,
                              background: leadingBackground,
                              secondaryBackground: trailingBackground,
                              confirmDismiss: (direction) =>
                                  _handleApprovalDismiss(
                                    approval,
                                    index,
                                    direction,
                                  ),
                              child: content,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    backgroundColor: _adminPrimaryColor.withOpacity(0.12),
    foregroundColor: _adminPrimaryColor,
    child: Text(initials, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}

String _extractInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'A';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
