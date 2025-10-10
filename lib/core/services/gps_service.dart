import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  /// Get current GPS coordinates
  Future<Position?> getCurrentLocation() async {
    if (kIsWeb) {
      // GPS not available on web
      return null;
    }

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } catch (e) {
      // GPS error - return null silently
      return null;
    }
  }

  /// Get GPS coordinates with prompt (like index.html)
  Future<Map<String, double>?> getLocationWithPrompt() async {
    final position = await getCurrentLocation();
    if (position == null) return null;

    return {
      'lat': position.latitude,
      'lng': position.longitude,
    };
  }
}
