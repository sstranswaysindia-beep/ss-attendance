import 'package:flutter/material.dart';

/// Provides the branded gradient blobs used across app backgrounds.
class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({
    required this.child,
    this.padding,
    this.useSafeArea = false,
    super.key,
  });

  /// Primary gradient colors reused for accents and buttons.
  static const List<Color> primaryColors = <Color>[
    Color(0xFF020024),
    Color(0xFF5050B5),
    Color(0xFF00D4FF),
  ];

  /// Convenience gradient for horizontal fills.
  static const LinearGradient primaryLinearGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: primaryColors,
  );

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.surface;

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    if (useSafeArea) {
      content = SafeArea(child: content);
    }

    return Container(
      color: baseColor,
      child: Stack(
        children: [
          const _BackgroundBlobs(),
          Positioned.fill(child: content),
        ],
      ),
    );
  }
}

class _BackgroundBlobs extends StatelessWidget {
  const _BackgroundBlobs();

  static const List<Color> _radialColors = <Color>[
    Color.fromRGBO(2, 0, 36, 0.85),
    Color.fromRGBO(80, 80, 181, 0.7),
    Color.fromRGBO(0, 212, 255, 0.0),
  ];

  static const List<double> _stops = <double>[0.0, 0.55, 1.0];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -140,
            child: Container(
              width: 460,
              height: 460,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.0,
                  colors: _radialColors,
                  stops: _stops,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -200,
            left: -160,
            child: Container(
              width: 520,
              height: 520,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomLeft,
                  radius: 1.0,
                  colors: _radialColors,
                  stops: _stops,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
