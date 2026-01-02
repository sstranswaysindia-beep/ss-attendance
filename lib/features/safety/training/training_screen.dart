import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/training_models.dart';
import '../../../core/services/safety_repository.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/auth_repository.dart';
import '../../../core/services/session_event_bus.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_loader.dart';
import 'training_player_screen.dart';
import '../../../core/services/training_flag_service.dart';
import '../../../core/services/auth_storage_service.dart';

class SafetyTrainingScreen extends StatefulWidget {
  const SafetyTrainingScreen({
    required this.user,
    required this.repository,
    super.key,
  });

  final AppUser user;
  final SafetyRepository repository;

  @override
  State<SafetyTrainingScreen> createState() => _SafetyTrainingScreenState();
}

class _SafetyTrainingScreenState extends State<SafetyTrainingScreen> {
  late Future<List<TrainingModule>> _future;
  bool _refreshing = false;
  final AuthRepository _authRepository = AuthRepository();
  bool _completionDialogShowing = false;

  @override
  void initState() {
    super.initState();
    NotificationService().requestBellHide();
    _future = widget.repository.fetchTrainingModules();
  }

  @override
  void dispose() {
    NotificationService().releaseBellHide();
    super.dispose();
  }

  Future<void> _refreshAndMaybeExit() async {
    setState(() => _refreshing = true);
    try {
      final modules = await widget.repository.fetchTrainingModules();
      final allCompleted =
          modules.isNotEmpty && modules.every((m) => m.progress.completed);
      setState(() {
        _future = Future.value(modules);
      });
      if (allCompleted) {
        await _showCompletedTrainingDialogAndExit();
      } else {
        if (mounted) {
          showAppToast(
            context,
            'Training not yet complete. Please finish remaining modules.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          'Unable to refresh training status',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _openModule(TrainingModule module) {
    if (module.locked) {
      showAppToast(context, 'Complete previous training first');
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TrainingPlayerScreen(
              user: widget.user,
              repository: widget.repository,
              module: module,
            ),
          ),
        )
        .then((_) async {
          final modules = await widget.repository.fetchTrainingModules();
          if (!mounted) return;
          setState(() {
            _future = Future.value(modules);
          });
          final allCompleted =
              modules.isNotEmpty && modules.every((m) => m.progress.completed);
          if (allCompleted) {
            await _showCompletedTrainingDialogAndExit();
          }
        });
  }

  Future<void> _showCompletedTrainingDialogAndExit() async {
    if (_completionDialogShowing) return;
    _completionDialogShowing = true;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Training completed'),
          content: const Text(
            'You have completed all training modules.\n\nTap "Completed" to continue to the dashboard.',
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                try {
                  // Clear backend flag (training_req = N) for this user.
                  await _authRepository.clearTrainingRequired(
                    userId: widget.user.id,
                    username: widget.user.username,
                  );
                } catch (_) {
                  // If backend call fails, still allow user to continue (best-effort).
                }

                // Clear any front-end override and persisted trainingRequired flag.
                await TrainingFlagService.clear();
                final savedUser = await AuthStorageService.getUser();
                if (savedUser != null && savedUser.trainingRequired) {
                  final updatedUser = savedUser.copyWith(trainingRequired: false);
                  await AuthStorageService.updateUser(updatedUser);
                }

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Completed'),
            ),
          ],
        );
      },
    );

    _completionDialogShowing = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(
            0xFF12355B,
          ), // Dark blue (same as spot audit/incab)
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Training',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh status',
              onPressed: _refreshing ? null : _refreshAndMaybeExit,
              icon: _refreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: AppLoader(size: 20),
                    )
                  : const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: () async {
                // Close training and logout globally.
                SessionEventBus.requestLogout();
              },
              icon: const Icon(Icons.logout),
            ),
          ],
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: FutureBuilder<List<TrainingModule>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: AppLoader());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not load trainings',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(snapshot.error?.toString() ?? ''),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => setState(
                          () => _future = widget.repository
                              .fetchTrainingModules(),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final modules = snapshot.data ?? const <TrainingModule>[];
            if (modules.isEmpty) {
              return const Center(child: Text('No training modules yet'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: modules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final module = modules[index];
                return _TrainingCard(
                  module: module,
                  onTap: () => _openModule(module),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.module, required this.onTap});

  final TrainingModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = module.progress;
    final percent = module.duration != null && module.duration! > 0
        ? (progress.position / module.duration!).clamp(0, 1)
        : 0.0;
    final locked = module.locked;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F1FF), Color(0xFFD7E9FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.school,
                    color: locked ? Colors.grey : const Color(0xFF1C7ED6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      module.title,
                      style: GoogleFonts.josefinSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (locked)
                    const Icon(Icons.lock, color: Colors.redAccent)
                  else if (progress.completed)
                    const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
              const SizedBox(height: 8),
              if (module.description != null && module.description!.isNotEmpty)
                Text(
                  module.description!,
                  style: const TextStyle(color: Colors.black87),
                ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.completed
                      ? 1.0
                      : (percent is double ? percent : percent.toDouble()),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE9ECEF),
                  color: progress.completed
                      ? const Color(0xFF2F9E44)
                      : const Color(0xFF1C7ED6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                progress.completed
                    ? 'Completed'
                    : module.duration != null
                    ? 'Progress: ${(percent * 100).toStringAsFixed(0)}%'
                    : 'Tap to continue',
                style: const TextStyle(color: Colors.black87, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
