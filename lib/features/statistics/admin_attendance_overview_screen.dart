import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/admin_attendance_overview.dart';
import '../../core/models/app_user.dart';
import '../../core/services/attendance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class AdminAttendanceOverviewScreen extends StatefulWidget {
  const AdminAttendanceOverviewScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AdminAttendanceOverviewScreen> createState() =>
      _AdminAttendanceOverviewScreenState();
}

class _AdminAttendanceOverviewScreenState
    extends State<AdminAttendanceOverviewScreen> {
  final AttendanceRepository _attendanceRepository = AttendanceRepository();
  final TextEditingController _searchController = TextEditingController();

  late final List<DateTime> _monthOptions;
  late DateTime _selectedMonth;

  bool _isLoading = false;
  String? _errorMessage;
  AdminAttendanceOverview? _overview;
  String _activeSearch = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _monthOptions = List<DateTime>.generate(
      12,
      (index) => DateTime(now.year, now.month - index, 1),
    );
    _loadOverview(syncController: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOverview({
    DateTime? month,
    String? searchTerm,
    bool syncController = false,
  }) async {
    final targetMonth = month ?? _selectedMonth;
    final trimmedSearch = (searchTerm ?? _activeSearch).trim();
    setState(() {
      _selectedMonth = DateTime(targetMonth.year, targetMonth.month, 1);
      _activeSearch = trimmedSearch;
      if (syncController && _searchController.text.trim() != trimmedSearch) {
        _searchController.text = trimmedSearch;
      }
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _attendanceRepository.fetchAdminOverview(
        month: _selectedMonth,
        searchTerm: trimmedSearch.isEmpty ? null : trimmedSearch,
      );
      if (!mounted) return;
      setState(() => _overview = overview);
    } on AttendanceFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _overview = null;
        _errorMessage = error.message;
      });
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load attendance overview.';
      setState(() {
        _overview = null;
        _errorMessage = fallback;
      });
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearch() {
    if (_isLoading) return;
    final term = _searchController.text.trim();
    FocusScope.of(context).unfocus();
    if (term == _activeSearch) {
      return;
    }
    _loadOverview(searchTerm: term);
  }

  void _clearSearch() {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    _searchController.clear();
    if (_activeSearch.isEmpty) {
      return;
    }
    _loadOverview(searchTerm: '', syncController: true);
  }

  void _showDriverDetails(DriverAttendanceOverview driver) {
    final workedDates = driver.workedDates..sort();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(driver.driverName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.badge, size: 18),
                      label: Text(driver.displayRole),
                    ),
                    Chip(
                      avatar: const Icon(Icons.apartment, size: 18),
                      label: Text(driver.displayPlant),
                    ),
                    Chip(
                      avatar: const Icon(Icons.calendar_month, size: 18),
                      label: Text(
                        '${driver.daysWorked}/${driver.totalDays} days in $monthLabel',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Worked days', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                if (workedDates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No approved attendance records for this month.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                else
                  SizedBox(
                    height: 320,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: workedDates.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final date = workedDates[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              DateFormat('dd').format(date),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            DateFormat('EEEE, dd MMM yyyy').format(date),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthFormatter = DateFormat('MMMM yyyy');

    final filterCard = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withOpacity(0.85),
            theme.colorScheme.secondaryContainer.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview Filters',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<DateTime>(
            decoration: InputDecoration(
              labelText: 'Select month',
              filled: true,
              fillColor: theme.colorScheme.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            value: _selectedMonth,
            dropdownColor: theme.colorScheme.background,
            items: _monthOptions
                .map(
                  (month) => DropdownMenuItem<DateTime>(
                    value: month,
                    child: Text(monthFormatter.format(month)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _loadOverview(month: value);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _onSearch(),
                  decoration: InputDecoration(
                    labelText: 'Search driver or plant',
                    filled: true,
                    fillColor: theme.colorScheme.background,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _activeSearch.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: _clearSearch,
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _onSearch,
                icon: const Icon(Icons.manage_search),
                label: const Text('Search'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
          if (_activeSearch.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  InputChip(
                    avatar: const Icon(Icons.filter_alt, size: 18),
                    label: Text('Active filter: $_activeSearch'),
                    onDeleted: _clearSearch,
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final drivers = _overview?.drivers ?? const <DriverAttendanceOverview>[];
    final hasSearch = _activeSearch.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadOverview,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _overview == null
            ? Center(
                child: Text(
                  'No data available.',
                  style: theme.textTheme.bodyLarge,
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  filterCard,
                  const SizedBox(height: 16),
                  _MonthSummaryCard(
                    overview: _overview!,
                    hasSearch: hasSearch,
                    activeSearch: _activeSearch,
                    driverCount: drivers.length,
                  ),
                  const SizedBox(height: 16),
                  Text('Driver Attendance', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (drivers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        hasSearch
                            ? 'No drivers match the current search.'
                            : 'No active drivers found for this month.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else
                    ...drivers.map(_buildDriverCard),
                ],
              ),
      ),
    );
  }

  Widget _buildDriverCard(DriverAttendanceOverview driver) {
    final theme = Theme.of(context);
    final attendanceRatio = driver.totalDays == 0
        ? 0.0
        : (driver.daysWorked / driver.totalDays).clamp(0.0, 1.0);
    final percentageText = '${driver.attendancePercentage.toStringAsFixed(1)}%';

    Color progressColor;
    if (attendanceRatio >= 0.8) {
      progressColor = Colors.green;
    } else if (attendanceRatio >= 0.5) {
      progressColor = Colors.orange;
    } else {
      progressColor = Colors.red;
    }

    final avatar = driver.hasProfilePhoto
        ? CircleAvatar(
            radius: 30,
            backgroundImage: NetworkImage(driver.profilePhoto),
            backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
          )
        : CircleAvatar(
            radius: 30,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
            child: Text(
              driver.initials,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.secondaryContainer.withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showDriverDetails(driver),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.driverName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.badge, size: 16),
                                label: Text(driver.displayRole),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.apartment, size: 16),
                                label: Text(driver.displayPlant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${driver.daysWorked}/${driver.totalDays} days',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          percentageText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: progressColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: attendanceRatio,
                    backgroundColor: theme.colorScheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$percentageText attendance',
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton.icon(
                      onPressed: () => _showDriverDetails(driver),
                      icon: const Icon(Icons.event_note_outlined, size: 16),
                      label: const Text('View schedule'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthSummaryCard extends StatelessWidget {
  const _MonthSummaryCard({
    required this.overview,
    required this.hasSearch,
    required this.activeSearch,
    required this.driverCount,
  });

  final AdminAttendanceOverview overview;
  final bool hasSearch;
  final String activeSearch;
  final int driverCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalWorkedDays = overview.drivers.fold<int>(
      0,
      (total, driver) => total + driver.daysWorked,
    );
    final potentialDays =
        overview.totalDays *
        (overview.driverCount == 0 ? 1 : overview.driverCount);
    final averageAttendance = potentialDays == 0
        ? 0
        : (totalWorkedDays / potentialDays) * 100;
    final leader = overview.drivers.isEmpty
        ? null
        : overview.drivers.reduce(
            (best, current) =>
                current.daysWorked > best.daysWorked ? current : best,
          );

    final baseColor = theme.colorScheme.surface.withOpacity(0.95);
    final highlightColor = theme.colorScheme.primary.withOpacity(0.08);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: baseColor,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Month Snapshot',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: highlightColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  overview.formattedMonth,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  icon: Icons.people_outline,
                  label: 'Drivers',
                  value: overview.driverCount.toString(),
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryTile(
                  icon: Icons.fact_check_outlined,
                  label: 'Total Days Worked',
                  value: totalWorkedDays.toString(),
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryTile(
                  icon: Icons.percent,
                  label: 'Avg. Attendance',
                  value: '${averageAttendance.toStringAsFixed(1)}%',
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (leader != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.secondaryContainer.withOpacity(0.35),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Top performer',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${leader.driverName} • ${leader.daysWorked}/${leader.totalDays} days',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (overview.generatedAt != null || hasSearch)
            const SizedBox(height: 12),
          if (overview.generatedAt != null)
            Text(
              'Last updated: ${DateFormat('dd MMM yyyy, HH:mm').format(overview.generatedAt!.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (hasSearch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Filtered by "$activeSearch" • $driverCount driver(s)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
