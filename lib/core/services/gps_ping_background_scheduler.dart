import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../models/app_user.dart';
import 'auth_storage_service.dart';
import 'gps_ping_repository.dart';
import 'gps_ping_throttle.dart';

const String _gpsPingTaskUniqueName = 'gps_ping_periodic_work';
const String _gpsPingTaskName = 'gps_ping_periodic_task';
const Duration _maxCachedLocationAge = Duration(minutes: 20);

@pragma('vm:entry-point')
void gpsPingCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (task != _gpsPingTaskName) {
      return true;
    }

    try {
      final user = await AuthStorageService.getUser();
      final driverId = user?.driverId;
      if (user == null || driverId == null || driverId.isEmpty) {
        return true;
      }

      final canSend = await GpsPingThrottle.shouldSend(driverId);
      if (!canSend) {
        return true;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return true;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return true;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      final position = _isFresh(lastKnown)
          ? lastKnown
          : await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 10),
            );
      if (position == null) {
        return true;
      }

      await GpsPingRepository().sendPing(
        driverId: driverId,
        plantId: user.plantId ?? user.assignmentPlantId ?? user.defaultPlantId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        source: 'mobile_bg_work',
      );
      await GpsPingThrottle.markSent(driverId);
    } catch (_) {
      // Best effort task: swallow errors and run again in next cycle.
    }

    return true;
  });
}

class GpsPingBackgroundScheduler {
  static bool _initialized = false;

  static bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!_isSupportedPlatform || _initialized) {
      return;
    }
    await Workmanager().initialize(
      gpsPingCallbackDispatcher,
    );
    _initialized = true;
  }

  static Future<void> scheduleForUser(AppUser? user) async {
    if (!_isSupportedPlatform) {
      return;
    }

    final driverId = user?.driverId;
    if (driverId == null || driverId.isEmpty) {
      await cancel();
      return;
    }

    await initialize();
    await Workmanager().registerPeriodicTask(
      _gpsPingTaskUniqueName,
      _gpsPingTaskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  static Future<void> cancel() async {
    if (!_isSupportedPlatform) {
      return;
    }
    await initialize();
    await Workmanager().cancelByUniqueName(_gpsPingTaskUniqueName);
  }
}

bool _isFresh(Position? position) {
  if (position == null) {
    return false;
  }
  final age = DateTime.now().difference(position.timestamp);
  return age <= _maxCachedLocationAge;
}
