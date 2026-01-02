import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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


