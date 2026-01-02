import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

typedef TyreTapCallback = void Function(String position);

class TyreVehicleCanvas extends StatelessWidget {
  const TyreVehicleCanvas({
    super.key,
    required this.vehicleNumber,
    required this.positions,
    required this.statusMap,
    required this.psiMin,
    required this.psiMax,
    this.onTyreTap,
    this.stepneyPosition = 'S',
  });

  final String vehicleNumber;
  final List<String> positions;
  final Map<String, TyreChipStatus> statusMap;
  final double psiMin;
  final double psiMax;
  final TyreTapCallback? onTyreTap;
  final String stepneyPosition;

  @override
  Widget build(BuildContext context) {
    final layout = _analyzePositions(positions);

    // Lock scaling so system font/display size does not affect layout
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: AspectRatio(
        // Taller canvas so the plotted layout box has more height
        aspectRatio: 9 / 12,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FAFC), Color(0xFFEFF3F8)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              return Stack(
                children: [
                  _Cabin(
                    vehicleNumber: vehicleNumber,
                    width: width,
                    height: height,
                  ),
                  _RearChassis(width: width, height: height),
                  ..._buildSteerAxle(
                    context,
                    width,
                    height,
                    layout.steerLeft,
                    layout.steerRight,
                  ),
                  ..._buildRearAxles(context, width, height, layout.rearAxles),
                  if ((layout.stepneyCode ?? stepneyPosition).isNotEmpty)
                    _buildStepney(
                      context,
                      width,
                      height,
                      layout.stepneyCode ?? stepneyPosition,
                    ),
                  Positioned(
                    left: 18,
                    top: 12,
                    child: Text(
                      'PSI: ${psiMin.toStringAsFixed(0)} – ${psiMax.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.blueGrey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSteerAxle(
    BuildContext context,
    double width,
    double height,
    List<String> leftCodes,
    List<String> rightCodes,
  ) {
    if (leftCodes.isEmpty && rightCodes.isEmpty) return const [];

    final widgets = <Widget>[];
    final centerY = height * 0.23;
    final leftX = width * 0.14;
    final rightX = width * 0.86;
    final maxGroupHeight = height * 0.28;

    widgets.addAll(
      _placeTyreGroup(
        context: context,
        codes: leftCodes,
        centerY: centerY,
        x: leftX,
        alignRight: false,
        isSteerGroup: true,
        maxGroupHeight: maxGroupHeight,
      ),
    );

    widgets.addAll(
      _placeTyreGroup(
        context: context,
        codes: rightCodes,
        centerY: centerY,
        x: rightX,
        alignRight: true,
        isSteerGroup: true,
        maxGroupHeight: maxGroupHeight,
      ),
    );

    widgets.add(
      Positioned(
        top: centerY - 24,
        left: (width / 2) - 48,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade900,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                offset: Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            'Steer Axle',
            style: GoogleFonts.josefinSans(
              textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );

    return widgets;
  }

  List<Widget> _buildRearAxles(
    BuildContext context,
    double width,
    double height,
    List<_RearAxleCodes> rearAxles,
  ) {
    if (rearAxles.isEmpty) return const [];

    final widgets = <Widget>[];
    const startYPct = 0.38;
    const endYPct = 0.88;
    final total = rearAxles.length + 1;
    final leftX = width * 0.16;
    final rightX = width * 0.84;

    for (var index = 0; index < rearAxles.length; index++) {
      final centerY =
          height * (startYPct + ((index + 1) * (endYPct - startYPct) / total));
      final spacingY = (endYPct - startYPct) * height / total;
      final maxGroupHeight = spacingY * 0.75;
      final axle = rearAxles[index];
      widgets.addAll(
        _placeTyreGroup(
          context: context,
          codes: axle.leftCodes,
          centerY: centerY,
          x: leftX,
          alignRight: false,
          isSteerGroup: false,
          maxGroupHeight: maxGroupHeight,
        ),
      );
      widgets.addAll(
        _placeTyreGroup(
          context: context,
          codes: axle.rightCodes,
          centerY: centerY,
          x: rightX,
          alignRight: true,
          isSteerGroup: false,
          maxGroupHeight: maxGroupHeight,
        ),
      );
    }
    return widgets;
  }

  Widget _buildStepney(
    BuildContext context,
    double width,
    double height,
    String code,
  ) {
    final state = statusMap[code];
    final color = state?.mapColor ?? Colors.blueGrey.shade900;
    // Match rear tyre sizing so S looks like L21/R21
    final tyreWidth = max(36.0, width * 0.082);
    final tyreHeight = tyreWidth * 1.15;

    return Positioned(
      left: (width / 2) - (tyreWidth / 2),
      // Bring stepney closer to the cargo/body (smaller gap)
      bottom: height * -0.015,
      child: _TyreChip(
        code: code,
        width: tyreWidth,
        height: tyreHeight,
        color: color,
        onTap: () => onTyreTap?.call(code),
      ),
    );
  }

  List<Widget> _placeTyreGroup({
    required BuildContext context,
    required List<String> codes,
    required double centerY,
    required double x,
    required bool alignRight,
    required bool isSteerGroup,
    double? maxGroupHeight,
  }) {
    if (codes.isEmpty) return const [];

    final baseWidth = MediaQuery.of(context).size.width;
    double tyreWidth = isSteerGroup
        ? max(26.0, baseWidth * 0.060)
        : max(36.0, baseWidth * 0.082);
    double tyreHeight = tyreWidth * (isSteerGroup ? 1.45 : 1.15);
    // No gap for rear pairs; moderate spacing for steer
    double spacing = isSteerGroup ? 8.0 : 0.0;

    if (isSteerGroup) {
      final totalHeight =
          (codes.length * tyreHeight) + spacing * max(0, codes.length - 1);
      if (maxGroupHeight != null && totalHeight > maxGroupHeight) {
        final scale = maxGroupHeight / totalHeight;
        tyreWidth *= scale;
        tyreHeight *= scale;
        spacing *= scale;
      }
      final startTop = centerY - totalHeight / 2;

      return List.generate(codes.length, (index) {
        final code = codes[index];
        final state = statusMap[code];
        final left = alignRight ? x - tyreWidth : x;
        final top = startTop + index * (tyreHeight + spacing);
        return Positioned(
          top: top,
          left: left,
          child: _TyreChip(
            code: code,
            width: tyreWidth,
            height: tyreHeight,
            color: state?.mapColor ?? Colors.blueGrey.shade900,
            onTap: () => onTyreTap?.call(code),
          ),
        );
      });
    }

    final totalWidth =
        (codes.length * tyreWidth) + spacing * max(0, codes.length - 1);
    final top = centerY - (tyreHeight / 2);
    final baseLeft = alignRight ? (x - totalWidth) : x;

    return List.generate(codes.length, (index) {
      final code = codes[index];
      final state = statusMap[code];
      final left = baseLeft + index * (tyreWidth + spacing);
      return Positioned(
        top: top,
        left: left,
        child: _TyreChip(
          code: code,
          width: tyreWidth,
          height: tyreHeight,
          color: state?.mapColor ?? Colors.blueGrey.shade900,
          onTap: () => onTyreTap?.call(code),
        ),
      );
    });
  }

  _TyreLayoutData _analyzePositions(List<String> codes) {
    final steerLeft = <String>[];
    final steerRight = <String>[];
    final rearBuilders = <int, _RearAxleBuilder>{};
    String? stepney;

    final regExp = RegExp(r'^([RL])(\d+)$');

    for (final raw in codes) {
      final code = raw.trim();
      if (code.isEmpty) continue;
      if (code.toUpperCase() == stepneyPosition.toUpperCase()) {
        stepney = code;
        continue;
      }

      final match = regExp.firstMatch(code);
      if (match == null) continue;

      final side = match.group(1)!;
      final digits = match.group(2)!;
      int axle = 0;
      int? slot;
      if (digits.length == 1) {
        axle = int.tryParse(digits) ?? 0;
      } else {
        final axleDigits = digits.substring(0, digits.length - 1);
        final slotDigits = digits.substring(digits.length - 1);
        axle = int.tryParse(axleDigits) ?? 0;
        slot = int.tryParse(slotDigits);
      }

      if (axle <= 1) {
        if (side == 'L') {
          if (!steerLeft.contains(code)) steerLeft.add(code);
        } else {
          if (!steerRight.contains(code)) steerRight.add(code);
        }
        continue;
      }

      final builder = rearBuilders.putIfAbsent(axle, () => _RearAxleBuilder());
      builder.add(side == 'L', code, slot);
    }

    steerLeft.sort((a, b) => _tyreCodeOrder(a).compareTo(_tyreCodeOrder(b)));
    steerRight.sort((a, b) => _tyreCodeOrder(a).compareTo(_tyreCodeOrder(b)));

    final rearAxles = rearBuilders.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final rear = rearAxles
        .map((entry) => entry.value.toAxleCodes())
        .toList(growable: false);

    return _TyreLayoutData(
      steerLeft: steerLeft,
      steerRight: steerRight,
      rearAxles: rear,
      stepneyCode: stepney,
    );
  }
}

class _Cabin extends StatelessWidget {
  const _Cabin({
    required this.vehicleNumber,
    required this.width,
    required this.height,
  });

  final String vehicleNumber;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cabinWidth = width * 0.72;
    final cabinHeight = height * 0.24;
    final left = (width - cabinWidth) / 2;

    return Positioned(
      left: left,
      top: height * 0.04,
      child: Container(
        width: cabinWidth,
        height: cabinHeight,
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade900,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Cabin · $vehicleNumber',
                    style: GoogleFonts.josefinSans(
                      textStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: cabinHeight * 0.34,
              left: (cabinWidth / 2) - (cabinWidth * 0.14),
              child: Container(
                width: cabinWidth * 0.28,
                height: cabinWidth * 0.28,
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade900,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      offset: Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.settings,
                  size: cabinWidth * 0.18,
                  color: Colors.blueGrey.shade200,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RearChassis extends StatelessWidget {
  const _RearChassis({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final chassisWidth = width * 0.72;
    // Increased height to give the cargo/body more vertical space
    final chassisHeight = height * 0.60;
    final left = (width - chassisWidth) / 2;
    final top = height * 0.34;

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: chassisWidth,
        height: chassisHeight,
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Cargo / Body',
                style: GoogleFonts.josefinSans(
                  textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TyreChip extends StatelessWidget {
  const _TyreChip({
    required this.code,
    required this.width,
    required this.height,
    required this.color,
    this.onTap,
  });

  final String code;
  final double width;
  final double height;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.10)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                offset: Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: Text(
              code,
              style: GoogleFonts.josefinSans(
                textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _TyreLayoutData {
  const _TyreLayoutData({
    required this.steerLeft,
    required this.steerRight,
    required this.rearAxles,
    required this.stepneyCode,
  });

  final List<String> steerLeft;
  final List<String> steerRight;
  final List<_RearAxleCodes> rearAxles;
  final String? stepneyCode;
}

class _RearAxleCodes {
  const _RearAxleCodes({required this.leftCodes, required this.rightCodes});

  final List<String> leftCodes;
  final List<String> rightCodes;
}

class _RearAxleBuilder {
  final List<_TyreSlot> _left = [];
  final List<_TyreSlot> _right = [];

  void add(bool isLeft, String code, int? slot) {
    final resolvedSlot = slot ?? (_list(isLeft).length + 1);
    _list(isLeft).add(_TyreSlot(code, resolvedSlot));
  }

  List<_TyreSlot> _list(bool isLeft) => isLeft ? _left : _right;

  _RearAxleCodes toAxleCodes() {
    _left.sort((a, b) => a.slot.compareTo(b.slot));
    _right.sort((a, b) => a.slot.compareTo(b.slot));
    return _RearAxleCodes(
      leftCodes: _left.map((e) => e.code).toList(growable: false),
      rightCodes: _right.map((e) => e.code).toList(growable: false),
    );
  }
}

class _TyreSlot {
  _TyreSlot(this.code, this.slot);
  final String code;
  final int slot;
}

int _tyreCodeOrder(String code) {
  final match = RegExp(r'^([RL])(\d+)$').firstMatch(code);
  if (match == null) return 0;
  final digits = match.group(2)!;
  if (digits.length == 1) {
    return (int.tryParse(digits) ?? 0) * 10;
  }
  final axle = int.tryParse(digits.substring(0, digits.length - 1)) ?? 0;
  final slot = int.tryParse(digits.substring(digits.length - 1)) ?? 0;
  return axle * 10 + slot;
}

enum TyreChipStatus { ok, caution, issue, draft }

extension TyreChipStatusColor on TyreChipStatus {
  Color get mapColor {
    switch (this) {
      case TyreChipStatus.ok:
        return const Color(0xFF22C55E);
      case TyreChipStatus.caution:
        return const Color(0xFFF59E0B);
      case TyreChipStatus.issue:
        return const Color(0xFFEF4444);
      case TyreChipStatus.draft:
        return const Color(0xFF64748B);
    }
  }
}
