import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/attendance_record.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/app_toast.dart';

// ── Design tokens ──
const Color _primaryDark = Color(0xFF0A2540);
const Color _accentTeal = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A2540);
const Color _gradientEnd = Color(0xFF1B5E7B);

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late DateTime _selectedMonth;
  String _statusFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  final AttendanceRepository _attendanceRepository = AttendanceRepository();

  bool _isLoading = false;
  // ignore: unused_field
  bool _isDeleting = false;
  String? _errorMessage;
  List<AttendanceRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Business logic (unchanged) ──

  Future<void> _loadHistory() async {
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId.isEmpty) {
      setState(() {
        _errorMessage = 'User mapping missing. Contact admin.';
        _records = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await _attendanceRepository.fetchHistory(
        driverId: driverId,
        month: _selectedMonth,
      );
      if (!mounted) return;
      setState(() => _records = records);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load attendance history.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DateTime> get _availableMonths {
    final now = DateTime.now();
    return List<DateTime>.generate(
      6,
      (index) => DateTime(now.year, now.month - index),
    );
  }

  List<AttendanceRecord> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _records
        .where((record) {
          if (_statusFilter != 'All' &&
              record.status != null &&
              record.status != _statusFilter) {
            return false;
          }
          if (query.isEmpty) return true;
          final haystack = [
            record.plantName,
            record.vehicleNumber,
            record.inTime,
            record.outTime,
            record.notes,
          ].whereType<String>().join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  String _formatMonth(DateTime month) => DateFormat('MMMM yyyy').format(month);

  String _shortMonth(DateTime month) => DateFormat('MMM yy').format(month);

  String _formatTime(String? value) {
    if (value == null || value.isEmpty) return '-';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat('dd-MM-yyyy HH:mm').format(parsed);
  }

  String _formatTimeShort(String? value) {
    if (value == null || value.isEmpty) return '-';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat('HH:mm').format(parsed);
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Rejected':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'Approved':
        return Icons.check_circle_rounded;
      case 'Pending':
        return Icons.hourglass_top_rounded;
      case 'Rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _extractAdjustReason(String raw) {
    final delimiterIndex = raw.indexOf(':');
    if (delimiterIndex == -1) return raw.trim();
    return raw.substring(delimiterIndex + 1).trim();
  }

  Future<void> _deleteRecord(AttendanceRecord record) async {
    final driverId = widget.user.driverId ?? widget.user.id;
    if (driverId.isEmpty) {
      showAppToast(context, 'User mapping missing. Contact admin.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Attendance'),
        content: const Text(
          'Are you sure you want to delete this attendance record?',
        ),
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

    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await _attendanceRepository.deleteAttendance(
        driverId: driverId,
        attendanceId: record.attendanceId,
      );
      if (!mounted) return;
      setState(() {
        _records = List.of(_records)
          ..removeWhere((item) => item.attendanceId == record.attendanceId);
        _isDeleting = false;
      });
      showAppToast(context, 'Attendance deleted.');
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      showAppToast(context, 'Unable to delete attendance.', isError: true);
    }
  }

  // ── Month selector sheet ──

  void _showMonthSelector() {
    final months = _availableMonths;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Month',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _primaryDark,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.5,
                ),
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final month = months[index];
                  final selected = _selectedMonth.year == month.year &&
                      _selectedMonth.month == month.month;
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() => _selectedMonth = month);
                      _loadHistory();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(colors: [_primaryDark, _accentTeal])
                            : null,
                        color: selected ? null : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? Colors.transparent : Colors.grey.shade200,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _shortMonth(month),
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── UI helpers ──

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(14),
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
      child: child,
    );
  }

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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredRecords = _filteredRecords;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 162,
              floating: false,
              pinned: true,
              centerTitle: true,
              backgroundColor: _gradientStart,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  onPressed: _isLoading ? null : _loadHistory,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Reload',
                ),
              ],
              title: const Text(
                'Attendance History',
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
                      colors: [_gradientStart, _gradientEnd, Color(0xFF0D4F6B)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Hero info card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Records',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isLoading ? '...' : '${_records.length}',
                                        style: const TextStyle(
                                          color: Color(0xFF7CFFB2),
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _showMonthSelector,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white.withOpacity(0.25)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          _shortMonth(_selectedMonth),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
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
          ];
        },
        body: Column(
          children: [
            // Filters
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  // Status filter chips
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['All', 'Approved', 'Pending', 'Rejected'].map((status) {
                        final selected = _statusFilter == status;
                        final chipColor = switch (status) {
                          'Approved' => Colors.green,
                          'Rejected' => Colors.red,
                          'Pending' => Colors.orange,
                          _ => _primaryDark,
                        };
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _statusFilter = status),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                              decoration: BoxDecoration(
                                color: selected ? chipColor.withOpacity(0.12) : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected ? chipColor : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: selected ? chipColor : Colors.grey.shade600,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Search bar
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
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by plant, vehicle, notes...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: Icon(Icons.close_rounded, color: Colors.grey.shade400, size: 18),
                              ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            // Records
            if (_isLoading)
              const Expanded(child: Center(child: AppLoader()))
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else if (filteredRecords.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'No records found for ${_shortMonth(_selectedMonth)}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: filteredRecords.length,
                  itemBuilder: (context, index) {
                    final record = filteredRecords[index];
                    return _buildRecordCard(record);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(AttendanceRecord record) {
    final statusLabel =
        record.status?.isNotEmpty == true ? record.status! : 'Pending';
    final sColor = _statusColor(statusLabel);
    final sIcon = _statusIcon(statusLabel);
    final inTime = _formatTimeShort(record.inTime);
    final outTime = _formatTimeShort(record.outTime);
    final parsedDate =
        record.inTime != null && record.inTime!.isNotEmpty
            ? DateTime.tryParse(record.inTime!)
            : null;
    final dayLabel = parsedDate != null
        ? DateFormat('dd MMM').format(parsedDate)
        : '--';
    final weekday = parsedDate != null
        ? DateFormat('EEE').format(parsedDate)
        : '';

    String? notes;
    if (record.notes != null && record.notes!.isNotEmpty) {
      notes = record.isAdjustRequest
          ? _extractAdjustReason(record.notes!)
          : record.notes!;
      if (notes.isEmpty) notes = null;
    }

    final card = _glassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: sColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(sIcon, color: sColor, size: 20),
              ),
              const SizedBox(width: 12),
              // Date & plant
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dayLabel, $weekday',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.plantName ?? record.plantId ?? 'Unknown plant',
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
              const SizedBox(width: 8),
              // Status pill + adjust badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _statusPill(statusLabel, sColor),
                  if (record.isAdjustRequest) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _primaryDark.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_calendar_rounded, size: 10, color: _primaryDark.withOpacity(0.7)),
                          const SizedBox(width: 3),
                          Text(
                            'Past Request',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _primaryDark.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Time bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.login_rounded, size: 14, color: Colors.green.shade500),
                const SizedBox(width: 4),
                Text(
                  inTime,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.logout_rounded, size: 14, color: Colors.blue.shade500),
                const SizedBox(width: 4),
                Text(
                  outTime,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (record.vehicleNumber != null && record.vehicleNumber!.isNotEmpty) ...[
                  const Spacer(),
                  Icon(Icons.directions_car_rounded, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    record.vehicleNumber!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Notes
          if (notes != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_rounded, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notes,
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

    return Dismissible(
      key: ValueKey('attendance-${record.attendanceId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteRecord(record);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      child: card,
    );
  }
}
