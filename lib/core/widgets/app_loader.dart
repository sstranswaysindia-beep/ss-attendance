import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../constants/assets.dart';

class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 144});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(
          'assets/animations/blue_loading.json',
          fit: BoxFit.contain,
          repeat: true,
        ),
      ),
    );
  }
}

class AppStartupLoader extends StatelessWidget {
  const AppStartupLoader({super.key, this.title = 'SS Transways India'});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const logoHeight = 138.0;

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppAssets.logoNew,
                  height: logoHeight,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Image.asset(
                    AppAssets.logo,
                    height: logoHeight,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF163A63),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Loading your workspace...',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: const Color(0xFF6E8096),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                const AppLoader(size: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
