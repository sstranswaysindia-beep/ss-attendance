import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_approval.dart';
import '../../core/services/approvals_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

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
  DateTime _selectedDate = DateTime.now();
  String _rangeSelection = '30';
  int? _rangeDays = 30;

  @override
  void initState() {
    super.initState();
    _repository = ApprovalsRepository(endpoint: widget.endpointOverride);
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

    final isApprove = direction == DismissDirection.endToStart;
    final action = isApprove ? 'approve' : 'reject';

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
        if (index >= 0 && index < updated.length) {
          updated.removeAt(index);
          _approvals = updated;
        }
      });

      if (mounted) {
        showAppToast(
          context,
          isApprove ? 'Attendance approved.' : 'Attendance rejected.',
        );
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

  Color _statusChipColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green.shade100;
      case 'rejected':
        return Colors.red.shade100;
      default:
        return Colors.orange.shade100;
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

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Approvals')),
      body: AppGradientBackground(
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
              DropdownButtonFormField<String>(
                value: _statusFilter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: statusOptions
                    .map(
                      (status) =>
                          DropdownMenuItem(value: status, child: Text(status)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _statusFilter = value);
                  _loadApprovals();
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loadApprovals,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
              if (!_isLoading && _errorMessage == null && _approvals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: const [
                      Icon(Icons.swipe, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Swipe left to approve and right to reject pending entries.',
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? Center(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _approvals.isEmpty
                    ? Center(
                        child: Text(
                          'No approvals for ${DateFormat('dd MMM yyyy').format(_selectedDate)}.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : Card(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _approvals.length,
                          separatorBuilder: (_, __) => const Divider(height: 0),
                          itemBuilder: (context, index) {
                            final approval = _approvals[index];
                            final statusLabel =
                                approval.status?.isNotEmpty == true
                                ? approval.status!
                                : 'Pending';
                            final isPending =
                                statusLabel.toLowerCase() == 'pending';
                            final isProcessing = _processingApprovals.contains(
                              approval.attendanceId,
                            );

                            final subtitleLines = <String>[
                              'Plant: ${approval.plantName}',
                              if ((approval.vehicleNumber ?? '').isNotEmpty)
                                'Vehicle: ${approval.vehicleNumber}',
                              'In: ${approval.inTime ?? '-'}',
                              'Out: ${approval.outTime ?? '-'}',
                            ];
                            if ((approval.notes ?? '').isNotEmpty) {
                              subtitleLines.add('Notes: ${approval.notes}');
                            }

                            Widget content = Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    approval.driverName.isNotEmpty
                                        ? approval.driverName[0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(approval.driverName),
                                subtitle: Text(subtitleLines.join('\n')),
                                trailing: Chip(
                                  label: Text(statusLabel),
                                  backgroundColor: _statusChipColor(
                                    statusLabel,
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

                            if (!isPending) {
                              return content;
                            }

                            return Dismissible(
                              key: ValueKey(
                                'approval_${approval.attendanceId}',
                              ),
                              direction: DismissDirection.horizontal,
                              background: const _ApprovalSwipeBackground(
                                alignment: Alignment.centerLeft,
                                color: Color(0xFFFFE5E5),
                                icon: Icons.close,
                                label: 'Reject',
                              ),
                              secondaryBackground:
                                  const _ApprovalSwipeBackground(
                                    alignment: Alignment.centerRight,
                                    color: Color(0xFFE5F6E5),
                                    icon: Icons.check,
                                    label: 'Approve',
                                  ),
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
