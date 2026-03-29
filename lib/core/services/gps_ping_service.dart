import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/app_user.dart';
import '../services/gps_ping_repository.dart';
import 'gps_ping_throttle.dart';

class GpsPingService {
  GpsPingService({
    required this.user,
    required this.repository,
    this.interval = const Duration(minutes: 15),
  });

  final AppUser user;
  final GpsPingRepository repository;
  final Duration interval;

  Timer? _timer;
  bool _isSending = false;
  bool _hasWarned = false;
  static const Duration _maxCachedLocationAge = Duration(minutes: 20);

  void start({
    required void Function(String message, {bool isError}) showToast,
  }) {
    // Skip GPS pinging on web platform
    if (kIsWeb) {
      return;
    }

    _timer?.cancel();
    _hasWarned = false;

    _timer = Timer.periodic(interval, (_) => _sendPing(showToast));
    _sendPing(showToast);
  }

  Future<bool> sendImmediatePing({
    void Function(String message, {bool isError})? showToast,
    String source = 'mobile_fg',
    bool bypassThrottle = false,
  }) async {
    return _sendPing(
      showToast ?? _noopToast,
      source: source,
      bypassThrottle: bypassThrottle,
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> _sendPing(
    void Function(String message, {bool isError}) showToast, {
    String source = 'mobile_fg',
    bool bypassThrottle = false,
  }) async {
    if (_isSending) {
      return false;
    }

    final driverId = user.driverId;
    if (driverId == null || driverId.isEmpty) {
      return false;
    }

    final canSend = bypassThrottle
        ? true
        : await GpsPingThrottle.shouldSend(driverId);
    if (!canSend) {
      return false;
    }

    _isSending = true;
    try {
      final position = await _captureLocation();
      if (position == null) {
        if (!_hasWarned) {
          _hasWarned = true;
          showToast('Location unavailable for GPS ping.', isError: true);
        }
        return false;
      }

      await repository.sendPing(
        driverId: driverId,
        plantId: user.plantId ?? user.assignmentPlantId ?? user.defaultPlantId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        source: source,
      );
      await GpsPingThrottle.markSent(driverId);
      return true;
    } on GpsPingFailure catch (error) {
      if (!_hasWarned) {
        _hasWarned = true;
        showToast(error.message, isError: true);
      }
      return false;
    } catch (_) {
      if (!_hasWarned) {
        _hasWarned = true;
        showToast('Unable to record GPS ping.', isError: true);
      }
      return false;
    } finally {
      _isSending = false;
    }
  }

  Future<Position?> _captureLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (_isFresh(lastKnown)) {
      return lastKnown;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
    } on TimeoutException {
      return lastKnown;
    } catch (_) {
      return lastKnown;
    }
  }

  bool _isFresh(Position? position) {
    if (position == null) {
      return false;
    }
    final age = DateTime.now().difference(position.timestamp);
    return age <= _maxCachedLocationAge;
  }

  void _noopToast(String message, {bool isError = false}) {}
}
