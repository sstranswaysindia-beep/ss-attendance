import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/app_user.dart';
import '../services/gps_ping_repository.dart';

class GpsPingService {
  GpsPingService({
    required this.user,
    required this.repository,
    this.interval = const Duration(minutes: 30),
  });

  final AppUser user;
  final GpsPingRepository repository;
  final Duration interval;

  Timer? _timer;
  bool _isSending = false;
  bool _hasWarned = false;

  void start({required void Function(String message, {bool isError}) showToast}) {
    _timer?.cancel();
    _hasWarned = false;

    _timer = Timer.periodic(interval, (_) => _sendPing(showToast));
    _sendPing(showToast);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sendPing(void Function(String message, {bool isError}) showToast) async {
    if (_isSending) {
      return;
    }

    final driverId = user.driverId;
    if (driverId == null || driverId.isEmpty) {
      return;
    }

    _isSending = true;
    try {
      final position = await _captureLocation();
      if (position == null) {
        if (!_hasWarned) {
          _hasWarned = true;
          showToast('Location unavailable for GPS ping.', isError: true);
        }
        return;
      }

      await repository.sendPing(
        driverId: driverId,
        plantId: user.plantId ?? user.assignmentPlantId ?? user.defaultPlantId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        source: _timer == null ? 'mobile_fg' : 'mobile_bg',
      );
    } on GpsPingFailure catch (error) {
      if (!_hasWarned) {
        _hasWarned = true;
        showToast(error.message, isError: true);
      }
    } catch (_) {
      if (!_hasWarned) {
        _hasWarned = true;
        showToast('Unable to record GPS ping.', isError: true);
      }
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

    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }
}
