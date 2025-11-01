import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/app_user.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import 'tyre_vehicle_picker_screen.dart';

class TyreInstructionsScreen extends StatefulWidget {
  const TyreInstructionsScreen({
    required this.user,
    required this.repository,
    super.key,
  });

  final AppUser user;
  final SafetyRepository repository;

  @override
  State<TyreInstructionsScreen> createState() => _TyreInstructionsScreenState();
}

class _TyreInstructionsScreenState extends State<TyreInstructionsScreen> {
  late Future<TyreInstructions> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchTyreInstructions();
  }

  void _handleProceed(TyreInstructions instructions) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TyreVehiclePickerScreen(
          user: widget.user,
          repository: widget.repository,
          instructions: instructions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Tyre Checklist',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: FutureBuilder<TyreInstructions>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _InstructionsError(
                message: snapshot.error?.toString() ??
                    'Unable to load tyre instructions',
                onRetry: () {
                  setState(() {
                    _future = widget.repository.fetchTyreInstructions();
                  });
                },
              );
            }

            final instructions = snapshot.data!;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    children: [
                      _SectionTitle(
                        labelHi: 'जाँच सूची',
                        labelEn: 'List of Checkpoints',
                      ),
                      const SizedBox(height: 12),
                      ...instructions.checkpoints.map(
                        (checkpoint) => _InstructionTile(
                          number: checkpoint.number,
                          textHi: checkpoint.textHi,
                          textEn: checkpoint.textEn,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        labelHi: 'टायर हवा का दबाव',
                        labelEn: 'PSI Guidance',
                      ),
                      const SizedBox(height: 12),
                      _PsiCard(
                        min: instructions.psiMin,
                        max: instructions.psiMax,
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1C7ED6), Color(0xFF5AA9FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(40)),
                      ),
                      child: FilledButton(
                        onPressed: () => _handleProceed(instructions),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size.fromHeight(52),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          'Proceed',
                          style: GoogleFonts.josefinSans(
                            textStyle: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.labelHi, required this.labelEn});

  final String labelHi;
  final String labelEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelHi,
          style: GoogleFonts.josefinSans(
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F2949),
            ),
          ),
        ),
        Text(
          labelEn,
          style: theme.textTheme.titleSmall?.copyWith(
            color: const Color(0xFF3A5A84),
          ),
        ),
      ],
    );
  }
}

class _InstructionTile extends StatelessWidget {
  const _InstructionTile({
    required this.number,
    required this.textHi,
    required this.textEn,
  });

  final int number;
  final String textHi;
  final String textEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A0A0A),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1C7ED6).withOpacity(0.12),
            child: Text(
              number.toString(),
              style: GoogleFonts.josefinSans(
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF1C7ED6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textHi,
                  style: GoogleFonts.josefinSans(
                    textStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F2949),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  textEn,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF3A5A84),
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

class _PsiCard extends StatelessWidget {
  const _PsiCard({required this.min, required this.max});

  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3B0),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommended pressure',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${min.toStringAsFixed(0)} – ${max.toStringAsFixed(0)} PSI',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'प्रति टायर सुझाया गया दबाव 120–130 PSI',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionsError extends StatelessWidget {
  const _InstructionsError({required this.message, required this.onRetry});

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
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 12),
            Text(
              'Unable to load instructions',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1C7ED6), Color(0xFF5AA9FF)],
                ),
                borderRadius: BorderRadius.all(Radius.circular(40)),
              ),
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
