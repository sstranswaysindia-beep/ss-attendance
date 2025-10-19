import 'dart:convert';

import 'package:http/http.dart' as http;

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
  AuthRepository({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse(_defaultEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/api/mobile/mobile_login.php';

  final http.Client _client;
  final Uri _endpoint;

  Future<AppUser> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        _endpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'timestamp':
              DateTime.now().millisecondsSinceEpoch, // Force fresh data
        }),
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

      final role = _parseRole(userJson['role']?.toString());

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
