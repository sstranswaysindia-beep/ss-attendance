import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import 'tyre_detail_screen.dart';
import 'tyre_review_screen.dart';
import 'widgets/tyre_vehicle_canvas.dart';

class TyreLayoutScreen extends StatefulWidget {
  const TyreLayoutScreen({
    required this.repository,
    required this.instructions,
    required this.vehicle,
    required this.inspectionId,
    required this.positions,
    super.key,
  });

  final SafetyRepository repository;
  final TyreInstructions instructions;
  final SafetyVehicle vehicle;
  final int inspectionId;
  final List<String> positions;

  @override
  State<TyreLayoutScreen> createState() => _TyreLayoutScreenState();
}

class _TyreLayoutScreenState extends State<TyreLayoutScreen> {
  final Map<String, TyreChecklistTyreState> _tyreStates = {};
  bool _navigating = false;
  bool _isInitialising = true;
  String? _initialError;
  final Map<String, String> _displayToOriginal = {};

  List<String> get _applicablePositions => _mapPositions(widget.positions);

  List<String> _mapPositions(List<String> positions) {
    final mapped = <String>[];
    _displayToOriginal.clear();
    for (final code in positions) {
      final display = _mapCode(code);
      mapped.add(display);
      _displayToOriginal[display] = code;
    }
    // Ensure uniqueness while preserving order
    final seen = <String>{};
    return mapped
        .where((p) {
          final isNew = !seen.contains(p);
          seen.add(p);
          return isNew;
        })
        .toList(growable: false);
  }

  String _mapCode(String code) {
    final isSix = widget.vehicle.tyreCount == 6;
    final isTen = widget.vehicle.tyreCount == 10;
    if (isSix) {
      switch (code) {
        case 'L21':
          return 'L31';
        case 'L22':
          return 'L32';
        case 'R21':
          return 'R31';
        case 'R22':
          return 'R32';
      }
    }
    if (isTen) {
      switch (code) {
        case 'L21':
          return 'L41';
        case 'L22':
          return 'L42';
        case 'R21':
          return 'R41';
        case 'R22':
          return 'R42';
      }
    }
    return code;
  }

  bool get _allPositionsCompleted => _applicablePositions.every(
    (position) => _tyreStates[position]?.isComplete == true,
  );

  @override
  void initState() {
    super.initState();
    _hydrateExistingStates();
  }

  Future<void> _hydrateExistingStates() async {
    setState(() {
      _isInitialising = true;
      _initialError = null;
    });

    try {
      final expectedCheckpoints = widget.instructions.checkpoints.length;
      final futures = _applicablePositions
          .map((displayPosition) async {
            final apiPosition =
                _displayToOriginal[displayPosition] ?? displayPosition;
            final state = await widget.repository.fetchTyreState(
              inspectionId: widget.inspectionId,
              positionCode: apiPosition,
              expectedCheckpoints: expectedCheckpoints,
            );
            if (state != null) {
              _tyreStates[displayPosition] = state;
            }
          })
          .toList(growable: false);

      await Future.wait(futures);

      if (mounted) {
        setState(() {
          _isInitialising = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('TyreLayout hydrate error: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _initialError = error.toString();
          _isInitialising = false;
        });
      }
    }
  }

  Map<String, TyreChipStatus> _buildStatusMap() {
    final map = <String, TyreChipStatus>{};
    for (final position in _applicablePositions) {
      map[position] = _statusFor(_tyreStates[position]);
    }
    map['S'] = _statusFor(_tyreStates['S']);
    return map;
  }

  TyreChipStatus _statusFor(TyreChecklistTyreState? state) {
    if (state == null) return TyreChipStatus.draft;
    final hasCritical = state.hasCriticalIssue;
    final caution =
        state.hasCaution ||
        state.psiOutsideRange(
          widget.instructions.psiMin,
          widget.instructions.psiMax,
        );
    if (hasCritical) return TyreChipStatus.issue;
    if (!state.isComplete) return TyreChipStatus.draft;
    if (caution) return TyreChipStatus.caution;
    if (state.isComplete) return TyreChipStatus.ok;
    return TyreChipStatus.draft;
  }

  Future<void> _openTyre(String position) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    try {
      final updatedState = await Navigator.of(context)
          .push<TyreChecklistTyreState>(
            MaterialPageRoute(
              builder: (_) => TyreDetailScreen(
                repository: widget.repository,
                inspectionId: widget.inspectionId,
                position: position,
                apiPosition: _displayToOriginal[position] ?? position,
                instructions: widget.instructions,
                initialState: _tyreStates[position],
              ),
            ),
          );

      if (updatedState != null && mounted) {
        setState(() {
          _tyreStates[position] = updatedState;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _navigating = false);
      }
    }
  }

  Future<void> _openReview() async {
    if (!_allPositionsCompleted || _navigating) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TyreReviewScreen(
          repository: widget.repository,
          inspectionId: widget.inspectionId,
          instructions: widget.instructions,
          vehicle: widget.vehicle,
          tyreStates: _applicablePositions
              .map((position) => _tyreStates[position])
              .whereType<TyreChecklistTyreState>()
              .toList(growable: false),
        ),
      ),
    );

    if (result == true && mounted) {
      showAppToast(context, 'Inspection submitted successfully');
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildVehicleInfoCard(BuildContext context, String psiRange) {
    final theme = Theme.of(context);
    final plantLabel = widget.vehicle.plantName?.trim();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A0A0A),
            blurRadius: 14,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF1C7ED6), Color(0xFF5AA9FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.directions_bus,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.vehicle.vehicleNumber,
                  style: GoogleFonts.josefinSans(
                    textStyle: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F2949),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _buildInfoPill(
                      context,
                      icon: Icons.blur_circular,
                      iconColor: const Color(0xFF1C7ED6),
                      label: 'Tyres ${widget.vehicle.tyreCount}',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFFFFF), Color(0xFFDFF5FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    if (plantLabel != null && plantLabel.isNotEmpty)
                      _buildInfoPill(
                        context,
                        icon: Icons.location_on_outlined,
                        iconColor: const Color(0xFF00A896),
                        label: plantLabel,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFFFFF), Color(0xFFE3F2FD)],
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                        ),
                      ),
                    _buildInfoPill(
                      context,
                      icon: Icons.speed,
                      iconColor: const Color(0xFFF59E0B),
                      label: 'PSI $psiRange',
                      backgroundColor: const Color(0xFFFFF3B0),
                      textColor: Colors.black87,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    Gradient? gradient,
    Color? backgroundColor,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? backgroundColor ?? Colors.white : null,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100A0A0A),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor ?? const Color(0xFF0F2949),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLegend(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status legend',
          style: GoogleFonts.josefinSans(
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F2949),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _buildLegendChip(
              context,
              color: TyreChipStatus.ok.mapColor,
              title: 'OK',
              description: 'All checks passed',
            ),
            _buildLegendChip(
              context,
              color: TyreChipStatus.caution.mapColor,
              title: 'Caution',
              description: 'Review PSI / notes',
            ),
            _buildLegendChip(
              context,
              color: TyreChipStatus.issue.mapColor,
              title: 'Issue',
              description: 'Critical finding logged',
            ),
            _buildLegendChip(
              context,
              color: TyreChipStatus.draft.mapColor,
              title: 'Pending',
              description: 'Awaiting inspection',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendChip(
    BuildContext context, {
    required Color color,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F2949),
                ),
              ),
              Text(
                description,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF3A5A84),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamp textScaler to prevent scaling from both font size and display size settings
    final psiRange =
        '${widget.instructions.psiMin.toStringAsFixed(0)}'
        '–${widget.instructions.psiMax.toStringAsFixed(0)} PSI';

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: _buildContent(context, theme, psiRange),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, String psiRange) {
    if (_isInitialising) {
      return const AppGradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_initialError != null) {
      return AppGradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load saved tyre data.',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _initialError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1C7ED6), Color(0xFF5AA9FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(40)),
                    ),
                    child: FilledButton(
                      onPressed: _hydrateExistingStates,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: const Color(
            0xFF12355B,
          ), // Dark blue (same as training/spot audit)
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.vehicle.vehicleNumber,
                style: GoogleFonts.josefinSans(
                  textStyle: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tyres: ${widget.vehicle.tyreCount} · PSI guide $psiRange',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildVehicleInfoCard(context, psiRange),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFE6F3FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x160A0A0A),
                        blurRadius: 22,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    child: Column(
                      children: [
                        TyreVehicleCanvas(
                          vehicleNumber: widget.vehicle.vehicleNumber,
                          positions: _applicablePositions,
                          statusMap: _buildStatusMap(),
                          psiMin: widget.instructions.psiMin,
                          psiMax: widget.instructions.psiMax,
                          onTyreTap: _openTyre,
                        ),
                        const SizedBox(height: 24),
                        _buildStatusLegend(context),
                      ],
                    ),
                  ),
                ),
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
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x160A0A0A),
                        blurRadius: 16,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: _allPositionsCompleted ? _openReview : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'Review & Submit',
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
        ),
      ),
    );
  }
}
