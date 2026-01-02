import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_user.dart';
import '../models/driver_vehicle.dart';
import 'notification_service.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

class AuthRepository {
  AuthRepository({http.Client? client, Uri? endpoint, Uri? deviceEndpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse(_defaultEndpoint),
      _deviceEndpoint = deviceEndpoint ?? Uri.parse(_defaultDeviceEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/api/mobile/mobile_login.php';
  static const String _defaultDeviceEndpoint =
      'https://sstranswaysindia.com/api/mobile/user_device_sync.php';
  static const String _defaultTrainingReqStatusEndpoint =
      'https://sstranswaysindia.com/api/mobile/training_req_status.php';
  static const String _defaultTrainingReqClearEndpoint =
      'https://sstranswaysindia.com/api/mobile/training_req_clear.php';

  final http.Client _client;
  final Uri _endpoint;
  final Uri _deviceEndpoint;
  final Uri _trainingReqStatusEndpoint = Uri.parse(
    _defaultTrainingReqStatusEndpoint,
  );
  final Uri _trainingReqClearEndpoint = Uri.parse(
    _defaultTrainingReqClearEndpoint,
  );

  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  Future<AppUser> login({
    required String username,
    required String password,
    String appVariant = 'driver',
  }) async {
    try {
      Map<String, String> devicePayload = {};
      try {
        devicePayload = await _collectDeviceInfo(appVariant: appVariant);
      } catch (_) {
        devicePayload = {};
      }

      final requestBody = <String, dynamic>{
        'username': username,
        'password': password,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      requestBody.addAll(devicePayload);
      if (appVariant.isNotEmpty) {
        requestBody['appVariant'] = appVariant;
      }

      final response = await _client.post(
        _endpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      final statusCode = response.statusCode;
      final body = response.body;

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw AuthFailure(
          'Invalid response from server (status: $statusCode).',
        );
      }

      if (statusCode != 200 || payload['status'] != 'ok') {
        final errorMessage = payload['error']?.toString();
        throw AuthFailure(
          errorMessage ?? 'Login failed (status: $statusCode).',
        );
      }

      final userJson =
          payload['user'] as Map<String, dynamic>? ??
          (throw AuthFailure('Missing user information from server.'));

      // Debug: Print user data from API
      print('AuthRepository: User data from API: $userJson');

      // Send FCM token to server after successful login
      await _sendFCMTokenToServer(userJson['id']?.toString() ?? username);

      final userIdString = userJson['id']?.toString() ?? username;
      final userNameString = userJson['username']?.toString() ?? username;
      if (devicePayload.isNotEmpty) {
        await _postDeviceInfo(
          payload: devicePayload,
          userId: userIdString,
          username: userNameString,
        );
      }

      final role = _parseRole(userJson['role']?.toString());
      final bool canViewDocuments = _parseFlag(
        userJson['view_document'] ?? userJson['viewDocument'],
      );
      final bool geofencingEnabled = _parseFlag(
        userJson['geofencing_enable'] ?? userJson['geofencingEnabled'],
      );
      final bool proxyEnabled = _parseFlag(
        userJson['proxy_enabled'] ?? userJson['proxyEnabled'],
      );
      final bool trainingRequired = _parseFlag(
        userJson['training_req'] ?? userJson['trainingRequired'],
      );

      Map<String, dynamic>? driverJson =
          payload['driver'] as Map<String, dynamic>?;
      Map<String, dynamic>? supervisorJson =
          payload['supervisor'] as Map<String, dynamic>?;

      // Debug: Print flow information
      print('AuthRepository: Role: $role');
      print('AuthRepository: Has driverJson: ${driverJson != null}');
      print('AuthRepository: Has supervisorJson: ${supervisorJson != null}');

      // Handle admin users
      if (role == UserRole.admin && driverJson == null) {
        final displayName =
            userJson['full_name']?.toString() ??
            userJson['username']?.toString() ??
            username;

        return AppUser(
          id: userJson['id']?.toString() ?? username,
          displayName: displayName,
          role: role,
          canViewDocuments: canViewDocuments,
          geofencingEnabled: geofencingEnabled,
          proxyEnabled: proxyEnabled,
          trainingRequired: trainingRequired,
        );
      }

      // Handle supervisors without driver_id (fallback case)
      if (role == UserRole.supervisor &&
          driverJson == null &&
          supervisorJson != null) {
        final displayName =
            userJson['full_name']?.toString() ??
            userJson['username']?.toString() ??
            username;

        // Process vehicles for supervisors without driver_id
        final vehiclesJson = payload['vehicles'] as List<dynamic>? ?? const [];
        print(
          'AuthRepository: Processing vehicles for supervisor without driver_id',
        );
        print('AuthRepository: Vehicles JSON count: ${vehiclesJson.length}');
        final vehicles = vehiclesJson
            .map((item) {
              print('AuthRepository: Vehicle item: $item');
              return DriverVehicle.fromJson(item as Map<String, dynamic>);
            })
            .where((vehicle) {
              final isValid =
                  vehicle.vehicleNumber.isNotEmpty && vehicle.id.isNotEmpty;
              print(
                'AuthRepository: Vehicle ${vehicle.vehicleNumber} (ID: ${vehicle.id}) - Valid: $isValid',
              );
              return isValid;
            })
            .toList(growable: false);
        print(
          'AuthRepository: Final vehicles count for supervisor: ${vehicles.length}',
        );

        // Get plant information for supervisors without driver_id
        final supervisedPlants =
            (supervisorJson['supervisedPlants'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
        final supervisedPlantIds =
            supervisorJson['supervisedPlantIds'] as List<dynamic>? ?? [];

        // Set default plant information from first supervised plant
        String? defaultPlantId;
        String? defaultPlantName;
        if (supervisedPlantIds.isNotEmpty && supervisedPlants.isNotEmpty) {
          defaultPlantId = supervisedPlantIds.first.toString();
          defaultPlantName = supervisedPlants.first['plant_name']?.toString();
        }

        return AppUser(
          id: userJson['id']?.toString() ?? username,
          displayName: displayName,
          role: role,
          // Set plant information for attendance and other features
          plantId: defaultPlantId,
          plantName: defaultPlantName,
          defaultPlantId: defaultPlantId,
          defaultPlantName: defaultPlantName,
          supervisedPlants: supervisedPlants,
          supervisedPlantIds: supervisedPlantIds,
          availableVehicles: vehicles,
          canViewDocuments: canViewDocuments,
          geofencingEnabled: geofencingEnabled,
          proxyEnabled: proxyEnabled,
          trainingRequired: trainingRequired,
        );
      }

      // Handle drivers or supervisors with driver_id
      if (role != UserRole.admin && driverJson == null) {
        throw AuthFailure('Missing driver mapping from server.');
      }

      driverJson ??= <String, dynamic>{};

      final assignmentJson = driverJson['assignment'] as Map<String, dynamic>?;

      final defaultPlantId =
          driverJson['defaultPlantId']?.toString() ??
          driverJson['plantId']?.toString();
      final defaultPlantName = driverJson['defaultPlantName']?.toString();
      final assignmentPlantId = assignmentJson?['plantId']?.toString();
      final assignmentPlantName = assignmentJson?['plantName']?.toString();
      final assignmentVehicleId = assignmentJson?['vehicleId']?.toString();
      final assignmentVehicleNumber = assignmentJson?['vehicleNumber']
          ?.toString();
      final assignmentId = assignmentJson?['assignmentId']?.toString();
      final supervisorName = driverJson['supervisorName']?.toString();
      final joiningDateRaw = driverJson['joiningDate']?.toString();
      DateTime? joiningDate;
      if (joiningDateRaw != null && joiningDateRaw.isNotEmpty) {
        joiningDate = DateTime.tryParse(joiningDateRaw);
      }

      final plantId =
          (assignmentPlantId != null && assignmentPlantId.isNotEmpty)
          ? assignmentPlantId
          : defaultPlantId;
      final plantName =
          (assignmentPlantName != null && assignmentPlantName.isNotEmpty)
          ? assignmentPlantName
          : defaultPlantName;

      final vehicleNumber = assignmentVehicleNumber?.isNotEmpty == true
          ? assignmentVehicleNumber
          : driverJson['vehicleNumber']?.toString();

      final vehiclesJson = payload['vehicles'] as List<dynamic>? ?? const [];
      print(
        'AuthRepository: Processing vehicles for driver/supervisor with driver_id',
      );
      print('AuthRepository: Vehicles JSON count: ${vehiclesJson.length}');
      final vehicles = vehiclesJson
          .map((item) {
            print('AuthRepository: Vehicle item: $item');
            return DriverVehicle.fromJson(item as Map<String, dynamic>);
          })
          .where((vehicle) {
            final isValid =
                vehicle.vehicleNumber.isNotEmpty && vehicle.id.isNotEmpty;
            print(
              'AuthRepository: Vehicle ${vehicle.vehicleNumber} (ID: ${vehicle.id}) - Valid: $isValid',
            );
            return isValid;
          })
          .toList(growable: false);
      print('AuthRepository: Final vehicles count: ${vehicles.length}');

      // For supervisors, prioritize full_name from users table over driver name
      final displayName =
          (role == UserRole.supervisor &&
              userJson['full_name']?.toString().isNotEmpty == true)
          ? userJson['full_name']?.toString() ?? username
          : (driverJson['name']?.toString() ?? username);

      return AppUser(
        id: userJson['id']?.toString() ?? username,
        displayName: displayName,
        role: role,
        employeeId: driverJson['employeeId']?.toString(),
        driverId: driverJson['driverId']?.toString(),
        plantId: plantId,
        plantName: plantName,
        defaultPlantId: defaultPlantId,
        defaultPlantName: defaultPlantName,
        assignmentId: assignmentId,
        assignmentPlantId: assignmentPlantId,
        assignmentPlantName: assignmentPlantName,
        assignmentVehicleId: assignmentVehicleId,
        assignmentVehicleNumber: assignmentVehicleNumber,
        salary: driverJson['salary']?.toString(),
        profilePhoto: driverJson['profilePhoto']?.toString(),
        aadhaar: driverJson['aadhaar']?.toString(),
        esiNumber: driverJson['esiNumber']?.toString(),
        uanNumber: driverJson['uanNumber']?.toString(),
        ifscCode: driverJson['ifsc']?.toString(),
        ifscVerified: driverJson['ifscVerified'] == true,
        bankAccount: driverJson['bankAccount']?.toString(),
        branchName: driverJson['branchName']?.toString(),
        fatherName: driverJson['fatherName']?.toString(),
        address: driverJson['address']?.toString(),
        vehicleNumber: vehicleNumber,
        driverRole: driverJson['role']?.toString(),
        availableVehicles: vehicles,
        joiningDate: joiningDate,
        supervisorName: supervisorName,
        supervisedPlants:
            (supervisorJson?['supervisedPlants'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
        supervisedPlantIds:
            supervisorJson?['supervisedPlantIds'] as List<dynamic>? ?? [],
        canViewDocuments: canViewDocuments,
        geofencingEnabled: geofencingEnabled,
        proxyEnabled: proxyEnabled,
        trainingRequired: trainingRequired,
      );
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw AuthFailure('Unable to reach server. Please try again later.');
    }
  }

  UserRole _parseRole(String? raw) {
    switch (raw) {
      case 'admin':
        return UserRole.admin;
      case 'supervisor':
        return UserRole.supervisor;
      case 'driver':
        return UserRole.driver;
      default:
        return UserRole.driver;
    }
  }

  bool _parseFlag(dynamic raw) {
    if (raw == null) {
      return false;
    }
    if (raw is bool) {
      return raw;
    }
    final normalized = raw.toString().trim().toLowerCase();
    return normalized == 'y' ||
        normalized == 'yes' ||
        normalized == '1' ||
        normalized == 'true';
  }

  Future<Map<String, String>> _collectDeviceInfo({
    String appVariant = 'driver',
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();

    String platform = 'unknown';
    String deviceId = '';
    String deviceModel = '';
    String osVersion = '';
    String deviceBrand = '';
    String architecture = '';

    try {
      if (Platform.isAndroid) {
        platform = 'android';
        final info = await _deviceInfoPlugin.androidInfo;
        deviceId = info.id;
        deviceBrand = info.brand ?? '';
        final manufacturer = info.manufacturer ?? '';
        final model = info.model ?? '';
        deviceModel = (manufacturer.isNotEmpty ? '$manufacturer ' : '') + model;
        osVersion = 'Android ${info.version.release ?? ''}'.trim();
        architecture = info.supportedAbis?.join(', ') ?? '';
        if (deviceId.isEmpty) {
          deviceId = info.serialNumber;
        }
      } else if (Platform.isIOS) {
        platform = 'ios';
        final info = await _deviceInfoPlugin.iosInfo;
        deviceId = info.identifierForVendor ?? '';
        deviceModel = info.utsname.machine ?? info.model ?? '';
        osVersion = '${info.systemName ?? 'iOS'} ${info.systemVersion ?? ''}'
            .trim();
      } else if (Platform.isMacOS) {
        platform = 'macos';
        final info = await _deviceInfoPlugin.macOsInfo;
        deviceModel = info.model;
        osVersion = 'macOS ${info.osRelease}'.trim();
        architecture = info.arch;
        deviceId = info.systemGUID ?? '';
      } else if (Platform.isWindows) {
        platform = 'windows';
        final info = await _deviceInfoPlugin.windowsInfo;
        deviceModel = info.computerName ?? '';
        osVersion = info.displayVersion ?? Platform.operatingSystemVersion;
        deviceId = info.deviceId ?? '';
      } else if (Platform.isLinux) {
        platform = 'linux';
        final info = await _deviceInfoPlugin.linuxInfo;
        deviceModel = info.name ?? Platform.operatingSystemVersion;
        osVersion = info.version ?? Platform.operatingSystem;
        deviceId = info.machineId ?? '';
      }
    } catch (_) {
      // Best-effort only; fall back to defaults.
    }

    if (deviceId.isEmpty) {
      deviceId =
          '${platform}_${packageInfo.packageName}_${DateTime.now().millisecondsSinceEpoch}';
    }

    final payload = <String, String>{
      'deviceId': deviceId,
      'devicePlatform': platform,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'appVersion': packageInfo.version,
      'appBuild': packageInfo.buildNumber,
      'appIdentifier': packageInfo.packageName,
    };

    if (deviceBrand.isNotEmpty) {
      payload['deviceBrand'] = deviceBrand;
    }
    if (architecture.isNotEmpty) {
      payload['architecture'] = architecture;
    }
    if (appVariant.isNotEmpty) {
      payload['appVariant'] = appVariant;
    }

    return payload;
  }

  Future<void> _postDeviceInfo({
    required Map<String, String> payload,
    required String userId,
    String? username,
  }) async {
    final body = Map<String, String>.from(payload)..['userId'] = userId;
    if (username != null && username.isNotEmpty) {
      body['username'] = username;
    }
    try {
      await _client.post(
        _deviceEndpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      // Ignore errors; device reporting is best-effort.
    }
  }

  Future<void> syncDeviceInfo({
    required AppUser user,
    String appVariant = 'driver',
  }) async {
    try {
      final payload = await _collectDeviceInfo(appVariant: appVariant);
      await _postDeviceInfo(
        payload: payload,
        userId: user.id,
        username: user.displayName,
      );
    } catch (_) {
      // Ignore failures.
    }
  }

  Future<bool?> fetchTrainingRequired({
    required String userId,
    String? username,
  }) async {
    try {
      final response = await _client.post(
        _trainingReqStatusEndpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'username': username}),
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['status'] != 'ok') {
        throw AuthFailure(
          payload['error']?.toString() ?? 'Unable to check flag',
        );
      }
      final raw = payload['training_req'] ?? payload['trainingRequired'];
      return _parseFlag(raw);
    } catch (_) {
      // Best-effort; do not block app flow if server not reachable.
      return null;
    }
  }

  Future<void> clearTrainingRequired({
    required String userId,
    String? username,
  }) async {
    final response = await _client.post(
      _trainingReqClearEndpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'username': username}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw AuthFailure(payload['error']?.toString() ?? 'Unable to clear flag');
    }
  }

  /// Send FCM token to server for push notifications
  Future<void> _sendFCMTokenToServer(String userId) async {
    try {
      final notificationService = NotificationService();
      final fcmToken = notificationService.fcmToken;

      if (fcmToken != null && fcmToken.isNotEmpty) {
        final response = await _client.post(
          Uri.parse(
            'https://sstranswaysindia.com/api/mobile/fcm_token_update.php',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': userId,
            'fcmToken': fcmToken,
            'platform': 'mobile',
          }),
        );

        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          if (payload['status'] == 'ok') {
            print('FCM token sent to server successfully');
          } else {
            print('Failed to send FCM token to server: ${payload['error']}');
          }
        } else {
          print('Failed to send FCM token to server: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('Error sending FCM token to server: $e');
      // Don't throw error as this shouldn't block login
    }
  }
}
