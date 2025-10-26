import 'package:flutter/material.dart';

import '../../../core/models/supervisor_today_attendance.dart';

class AdminTodayAttendanceList extends StatelessWidget {
  const AdminTodayAttendanceList({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.plants,
    required this.onRetry,
    this.padding = EdgeInsets.zero,
    this.showLoadingIndicator = true,
    this.emptyMessage =
        'No attendance activity recorded across plants today.',
  });

  final bool isLoading;
  final String? errorMessage;
  final List<SupervisorTodayAttendancePlant> plants;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry padding;
  final bool showLoadingIndicator;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDrivers = plants.any((plant) => plant.drivers.isNotEmpty);

    if (errorMessage != null && !hasDrivers) {
      return Padding(
        padding: padding,
        child: _ErrorCard(
          message: errorMessage!,
          onRetry: isLoading ? null : onRetry,
        ),
      );
    }

    final items = <Widget>[];

    if (errorMessage != null && hasDrivers) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }

    if (!hasDrivers) {
      items.add(
        Card(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(emptyMessage),
          ),
        ),
      );
    } else {
      for (final plant in plants) {
        items.add(_PlantAttendanceCard(plant: plant));
      }
    }

    if (isLoading && showLoadingIndicator && plants.isNotEmpty) {
      items.insert(
        0,
        const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlantAttendanceCard extends StatelessWidget {
  const _PlantAttendanceCard({required this.plant});

  final SupervisorTodayAttendancePlant plant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = plant.plantName.isEmpty ? 'Unassigned Plant' : plant.plantName;

    if (plant.drivers.isEmpty) {
      return Card(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.factory_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No active drivers linked to this plant.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.factory_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: plant.drivers
                  .map(
                    (driver) => _DriverAttendanceTile(driver: driver),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverAttendanceTile extends StatelessWidget {
  const _DriverAttendanceTile({required this.driver});

  final SupervisorTodayAttendanceDriver driver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCheckIn = driver.hasCheckIn;
    final hasCheckOut = driver.hasCheckOut;
    final hasAny = hasCheckIn || hasCheckOut;
    final isComplete = hasCheckIn && hasCheckOut;
    final isPartial = hasAny && !isComplete;

    final gradientColors = isComplete
        ? const [Color(0xFF00D100), Color(0xFF00AA00)]
        : isPartial
            ? const [Color(0xFFFFCE55), Color(0xFFFFB347)]
            : const [Color(0xFFED1C24), Color(0xFFB3121B)];

    const primaryTextColor = Colors.black87;
    const subtleTextColor = Colors.black54;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _DriverAvatar(driver: driver, textColor: primaryTextColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.driverName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${hasAny ? 'Done' : 'Not Done'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: primaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isPartial)
                  Text(
                    'Check-out pending',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtleTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.driver, required this.textColor});

  final SupervisorTodayAttendanceDriver driver;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final badge = driver.roleBadge;
    final photo = driver.profilePhoto?.trim();
    final avatarBackground = Colors.white.withOpacity(0.85);

    Widget baseAvatar;
    if (photo != null && photo.isNotEmpty) {
      baseAvatar = CircleAvatar(
        radius: 26,
        backgroundColor: avatarBackground,
        backgroundImage: NetworkImage(photo),
      );
    } else {
      baseAvatar = CircleAvatar(
        radius: 26,
        backgroundColor: avatarBackground,
        child: Text(
          _driverInitials(driver.driverName),
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        baseAvatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black87.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _driverInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'DR';
    }
    if (parts.length == 1) {
      final word = parts.first;
      if (word.length >= 2) {
        return word.substring(0, 2).toUpperCase();
      }
      return word.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
