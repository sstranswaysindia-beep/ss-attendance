import 'dart:io';

import 'package:in_app_update/in_app_update.dart';

class AppUpdateStatus {
  const AppUpdateStatus({
    required this.isUpdateAvailable,
    this.availableVersionCode,
  });

  final bool isUpdateAvailable;
  final int? availableVersionCode;
}

class AppUpdateService {
  static const String androidPackageName = 'com.sstranswaysindia.app';

  Future<AppUpdateStatus> checkForUpdate() async {
    if (!Platform.isAndroid) {
      return const AppUpdateStatus(isUpdateAvailable: false);
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      final isAvailable =
          info.updateAvailability == UpdateAvailability.updateAvailable;
      return AppUpdateStatus(
        isUpdateAvailable: isAvailable,
        availableVersionCode: info.availableVersionCode,
      );
    } catch (_) {
      return const AppUpdateStatus(isUpdateAvailable: false);
    }
  }
}
