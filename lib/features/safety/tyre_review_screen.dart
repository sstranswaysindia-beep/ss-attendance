import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import 'widgets/tyre_vehicle_canvas.dart';

class TyreReviewScreen extends StatefulWidget {
  const TyreReviewScreen({
    required this.repository,
    required this.inspectionId,
    required this.instructions,
    required this.vehicle,
    required this.tyreStates,
    super.key,
  });

  final SafetyRepository repository;
  final int inspectionId;
  final TyreInstructions instructions;
  final SafetyVehicle vehicle;
  final List<TyreChecklistTyreState> tyreStates;

  @override
  State<TyreReviewScreen> createState() => _TyreReviewScreenState();
}

class _TyreReviewScreenState extends State<TyreReviewScreen> {
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  TyreChipStatus _statusFor(TyreChecklistTyreState state) {
    final hasCritical = state.hasCriticalIssue;
    final caution = state.hasCaution ||
        state.psiOutsideRange(widget.instructions.psiMin, widget.instructions.psiMax);
    if (hasCritical) return TyreChipStatus.issue;
    if (caution) return TyreChipStatus.caution;
    if (state.isComplete) return TyreChipStatus.ok;
    return TyreChipStatus.draft;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.repository.submitInspection(
        inspectionId: widget.inspectionId,
        overallNote: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error, stackTrace) {
      debugPrint('TyreReview submit error: $error\n$stackTrace');
      if (mounted) {
        showAppToast(context, 'Failed to submit inspection: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final psiRange = '${widget.instructions.psiMin.toStringAsFixed(0)}–'
        '${widget.instructions.psiMax.toStringAsFixed(0)} PSI';

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review Inspection',
                style: GoogleFonts.josefinSans(
                  textStyle: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.vehicle.vehicleNumber,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ensure every tyre has completed checklist before submitting. PSI guidance: $psiRange',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                itemCount: widget.tyreStates.length + 1,
                itemBuilder: (context, index) {
                  if (index < widget.tyreStates.length) {
                    final tyreState = widget.tyreStates[index];
                    final status = _statusFor(tyreState);
                    final palette = switch (status) {
                      TyreChipStatus.ok => (
                          bg: Colors.green.shade50,
                          iconColor: Colors.green,
                          icon: Icons.check_circle
                        ),
                      TyreChipStatus.caution => (
                          bg: Colors.orange.shade50,
                          iconColor: Colors.orange.shade700,
                          icon: Icons.error_outline
                        ),
                      TyreChipStatus.issue => (
                          bg: Colors.red.shade50,
                          iconColor: Colors.red,
                          icon: Icons.close
                        ),
                      TyreChipStatus.draft => (
                          bg: Colors.blueGrey.shade50,
                          iconColor: Colors.blueGrey,
                          icon: Icons.help_outline
                        ),
                    };
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: palette.bg,
                          child: Icon(
                            palette.icon,
                            color: palette.iconColor,
                          ),
                        ),
                        title: Text(
                          tyreState.position,
                          style: GoogleFonts.josefinSans(
                            textStyle: theme.textTheme.titleMedium,
                          ),
                        ),
                        subtitle: Text(
                          '${tyreState.psi.toStringAsFixed(1)} PSI',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: status == TyreChipStatus.issue
                                ? Colors.red
                                : status == TyreChipStatus.caution
                                    ? Colors.orange.shade700
                                    : theme.colorScheme.outline,
                          ),
                        ),
                        trailing: Icon(palette.icon, color: palette.iconColor),
                      ),
                    );
                  }

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall notes (optional)',
                            style: GoogleFonts.josefinSans(
                              textStyle: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _notesController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Add notes for supervisor review',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Submit Inspection',
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
          ],
        ),
      ),
    );
  }
}
