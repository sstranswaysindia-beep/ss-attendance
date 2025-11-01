import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/app_user.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import 'tyre_instructions_screen.dart';

class SafetyHubScreen extends StatefulWidget {
  const SafetyHubScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<SafetyHubScreen> createState() => _SafetyHubScreenState();
}

class _SafetyHubScreenState extends State<SafetyHubScreen> {
  late final SafetyRepository _repository;
  late Future<List<SafetyModule>> _modulesFuture;

  @override
  void initState() {
    super.initState();
    _repository = SafetyRepository(currentUser: widget.user);
    _modulesFuture = _repository.fetchModules();
  }

  void _openModule(SafetyModule module) {
    switch (module.key) {
      case 'tyre_checklist':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TyreInstructionsScreen(
              user: widget.user,
              repository: _repository,
            ),
          ),
        );
        break;
      default:
        showAppToast(context, 'Module coming soon');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Safety',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        body: FutureBuilder<List<SafetyModule>>(
          future: _modulesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _SafetyError(
                message: snapshot.error?.toString() ?? 'Unable to load modules',
                onRetry: () {
                  setState(() {
                    _modulesFuture = _repository.fetchModules();
                  });
                },
              );
            }
            final modules = snapshot.data ?? const <SafetyModule>[];
            if (modules.isEmpty) {
              return const _SafetyEmptyState();
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                itemCount: modules.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.05,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemBuilder: (context, index) {
                  final module = modules[index];
                  return _SafetyModuleCard(
                    module: module,
                    onTap: () => _openModule(module),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SafetyModuleCard extends StatelessWidget {
  const _SafetyModuleCard({
    required this.module,
    required this.onTap,
  });

  final SafetyModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: _gradientForModule(module.key),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A0A0A0A),
                  blurRadius: 12,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _iconColorForModule(module.key).withOpacity(0.15),
                  ),
                  child: Icon(
                    _iconForModule(module.key),
                    color: _iconColorForModule(module.key),
                    size: 36,
                  ),
                ),
                const Spacer(),
                Text(
                  module.label,
                  style: GoogleFonts.josefinSans(
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F2949),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitleForModule(module.key),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF3A5A84),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForModule(String key) {
    switch (key) {
      case 'tyre_checklist':
        return Icons.build_circle_outlined;
      case 'incab':
        return Icons.event_seat;
      case 'spot_audit':
        return Icons.fact_check;
      case 'training':
        return Icons.school;
      default:
        return Icons.safety_check;
    }
  }

  LinearGradient _gradientForModule(String key) {
    switch (key) {
      case 'tyre_checklist':
        return const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'incab':
        return const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFDFF5FF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      case 'spot_audit':
        return const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE3F2FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'training':
        return const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFDDEBFF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
        );
    }
  }

  Color _iconColorForModule(String key) {
    switch (key) {
      case 'tyre_checklist':
        return const Color(0xFF1C7ED6);
      case 'incab':
        return const Color(0xFF00A896);
      case 'spot_audit':
        return const Color(0xFFF77F00);
      case 'training':
        return const Color(0xFF9D4EDD);
      default:
        return const Color(0xFF1C7ED6);
    }
  }

  String _subtitleForModule(String key) {
    switch (key) {
      case 'tyre_checklist':
        return 'Daily tyre inspection checklist';
      case 'incab':
        return 'Cabin housekeeping & safety';
      case 'spot_audit':
        return 'Random safety audits';
      case 'training':
        return 'Learning modules';
      default:
        return 'Safety workflow';
    }
  }
}

class _SafetyError extends StatelessWidget {
  const _SafetyError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'Unable to load Safety hub',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyEmptyState extends StatelessWidget {
  const _SafetyEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.safety_check, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'No safety modules available',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
