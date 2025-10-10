import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/trip_driver.dart';
import '../models/trip_helper.dart';
import '../models/trip_meta.dart';
import '../models/trip_plant.dart';
import '../models/trip_record.dart';
import '../models/trip_summary.dart';
import '../models/trip_vehicle.dart';

class TripFailure implements Exception {
  TripFailure(this.message);

  final String message;

  @override
  String toString() => 'TripFailure: $message';
}

class TripOverviewResponse {
  const TripOverviewResponse({
    required this.summary,
    required this.trips,
    required this.plants,
  });

  final TripSummary summary;
  final List<TripRecord> trips;
  final List<Map<String, dynamic>> plants;
}

class TripEndResult {
  const TripEndResult({required this.tripId, required this.totalKm});

  final int tripId;
  final int totalKm;
}

class TripRepository {
  TripRepository({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse(_defaultEndpoint);

  static const String _defaultEndpoint =
      'https://sstranswaysindia.com/TripDetails/api/mobile/trips_overview.php';
  static const String _mobileBase =
      'https://sstranswaysindia.com/TripDetails/api/mobile/';

  final http.Client _client;
  final Uri _endpoint;

  Future<TripMeta> fetchMetaForUser(AppUser user) async {
    final fallbackDrivers = _buildFallbackDrivers(user);
    final fallbackHelpers = _buildFallbackHelpers(user);
    final fallbackCustomers = _buildFallbackCustomers(user);

    try {
      final uri = Uri.parse('${_mobileBase}meta.php');
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'role': _roleToString(user.role),
          if (_tryParseInt(user.id) != null) 'userId': _tryParseInt(user.id),
          if (_tryParseInt(user.driverId) != null)
            'driverId': _tryParseInt(user.driverId),
        }),
      );

      if (response.statusCode >= 300) {
        debugPrint(
          'TripRepository.fetchMetaForUser: HTTP ${response.statusCode}',
        );
        if (fallbackDrivers.isNotEmpty ||
            fallbackHelpers.isNotEmpty ||
            fallbackCustomers.isNotEmpty) {
          return TripMeta(
            drivers: fallbackDrivers,
            helpers: fallbackHelpers,
            customers: fallbackCustomers,
          );
        }
        throw TripFailure(
          'Unable to load people (status: ${response.statusCode}).',
        );
      }

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        debugPrint(
          'TripRepository.fetchMetaForUser: bad JSON ${error.runtimeType}',
        );
        if (fallbackDrivers.isNotEmpty ||
            fallbackHelpers.isNotEmpty ||
            fallbackCustomers.isNotEmpty) {
          return TripMeta(
            drivers: fallbackDrivers,
            helpers: fallbackHelpers,
            customers: fallbackCustomers,
          );
        }
        throw TripFailure('Unable to load drivers and helpers.');
      }

      if (payload['status'] != 'ok') {
        debugPrint(
          'TripRepository.fetchMetaForUser: server error ${payload['error']}',
        );
        if (fallbackDrivers.isNotEmpty ||
            fallbackHelpers.isNotEmpty ||
            fallbackCustomers.isNotEmpty) {
          return TripMeta(
            drivers: fallbackDrivers,
            helpers: fallbackHelpers,
            customers: fallbackCustomers,
          );
        }
        throw TripFailure(
          payload['error']?.toString() ?? 'Unable to load drivers and helpers.',
        );
      }

      final driversJson = payload['drivers'] as List<dynamic>? ?? const [];
      final helpersJson = payload['helpers'] as List<dynamic>? ?? const [];
      final customersJson = payload['customers'] as List<dynamic>? ?? const [];

      final driverMap = <int, TripDriver>{
        for (final driver in fallbackDrivers) driver.id: driver,
      };
      for (final item in driversJson) {
        final driver = TripDriver.fromJson(item as Map<String, dynamic>);
        if (driver.id > 0 && driver.name.isNotEmpty) {
          driverMap[driver.id] = driver;
        }
      }

      final helperMap = <int, TripHelper>{
        for (final helper in fallbackHelpers) helper.id: helper,
      };
      for (final item in helpersJson) {
        final helper = TripHelper.fromJson(item as Map<String, dynamic>);
        if (helper.id > 0 && helper.name.isNotEmpty) {
          helperMap[helper.id] = helper;
        }
      }

      final customers = <String>[...fallbackCustomers];
      for (final item in customersJson) {
        final name = item is Map<String, dynamic>
            ? item['name']?.toString()
            : item?.toString();
        if (name != null &&
            name.trim().isNotEmpty &&
            !customers.contains(name.trim())) {
          customers.add(name.trim());
        }
      }

      return TripMeta(
        drivers: driverMap.values.toList(growable: false),
        helpers: helperMap.values.toList(growable: false),
        customers: customers,
      );
    } on TripFailure {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        'TripRepository.fetchMetaForUser: unexpected $error\n$stackTrace',
      );
      if (fallbackDrivers.isNotEmpty ||
          fallbackHelpers.isNotEmpty ||
          fallbackCustomers.isNotEmpty) {
        return TripMeta(
          drivers: fallbackDrivers,
          helpers: fallbackHelpers,
          customers: fallbackCustomers,
        );
      }
      throw TripFailure('Unable to load drivers and helpers.');
    }
  }

  Future<TripOverviewResponse> fetchOverview({
    required DateTime from,
    required DateTime to,
    String status = 'All',
    String? plantId,
    String? vehicleId,
  }) async {
    final queryParams = <String, String>{
      'from': _formatDate(from),
      'to': _formatDate(to),
      'status': status,
      if (plantId != null && plantId.isNotEmpty) 'plantId': plantId,
      if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
    };

    final uri = _endpoint.replace(queryParameters: queryParams);

    try {
      final response = await _client.get(uri);
      if (response.statusCode >= 300) {
        throw TripFailure(
          'Unable to load trips (status: ${response.statusCode}).',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') {
        throw TripFailure(
          payload['error']?.toString() ?? 'Unable to load trips.',
        );
      }

      final summary = TripSummary.fromJson(
        payload['summary'] as Map<String, dynamic>?,
      );
      final tripsJson = payload['trips'] as List<dynamic>? ?? const [];
      final trips = tripsJson
          .map((item) => TripRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      final plantsJson = payload['plants'] as List<dynamic>? ?? const [];
      final plants = plantsJson
          .map((item) => item as Map<String, dynamic>)
          .toList(growable: false);

      return TripOverviewResponse(
        summary: summary,
        trips: trips,
        plants: plants,
      );
    } on TripFailure {
      rethrow;
    } catch (_) {
      throw TripFailure('Unable to load trips.');
    }
  }

  Future<int> createTrip({
    required int vehicleId,
    required String startDate,
    required int startKm,
    required List<int> driverIds,
    List<int> helperIds = const <int>[],
    required List<String> customerNames,
    String note = '',
    double? gpsLat,
    double? gpsLng,
  }) async {
    final uri = Uri.parse('${_mobileBase}trips_create.php');
    final payload = <String, dynamic>{
      'vehicle_id': vehicleId,
      'start_date': startDate,
      'start_km': startKm,
      'driver_ids': driverIds,
      if (helperIds.isNotEmpty) 'helper_ids': helperIds,
      'customer_names': customerNames,
      if (note.isNotEmpty) 'note': note,
      if (gpsLat != null) 'gps_lat': gpsLat,
      if (gpsLng != null) 'gps_lng': gpsLng,
    };

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 300) {
        throw TripFailure(
          'Start trip failed (status: ${response.statusCode}).',
        );
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        throw TripFailure('Start trip failed (bad JSON response).');
      }

      if (json['status'] != 'ok') {
        throw TripFailure(json['error']?.toString() ?? 'Start trip failed.');
      }

      return int.tryParse(json['trip_id']?.toString() ?? '') ?? 0;
    } on TripFailure {
      rethrow;
    } catch (_) {
      throw TripFailure('Could not reach server while starting trip.');
    }
  }

  Future<TripEndResult> endTrip({
    required int tripId,
    required String endDate,
    required int endKm,
  }) async {
    final uri = Uri.parse('${_mobileBase}trips_end.php');
    final payload = <String, dynamic>{
      'trip_id': tripId,
      'end_date': endDate,
      'end_km': endKm,
    };

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 300) {
        throw TripFailure('End trip failed (status: ${response.statusCode}).');
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw TripFailure('End trip failed (bad JSON response).');
      }

      if (json['status'] != 'ok') {
        throw TripFailure(json['error']?.toString() ?? 'End trip failed.');
      }

      final tripIdParsed =
          int.tryParse(json['trip_id']?.toString() ?? '') ?? tripId;
      final totalKm = int.tryParse(json['total_km']?.toString() ?? '') ?? 0;

      return TripEndResult(tripId: tripIdParsed, totalKm: totalKm);
    } on TripFailure {
      rethrow;
    } catch (_) {
      throw TripFailure('Could not reach server while ending trip.');
    }
  }

  Future<void> deleteTrip(int tripId) async {
    final uri = Uri.parse('${_mobileBase}trips_delete.php');
    final payload = <String, dynamic>{'trip_id': tripId};

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 300) {
        throw TripFailure(
          'Delete trip failed (status: ${response.statusCode}).',
        );
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw TripFailure('Delete trip failed (bad JSON response).');
      }

      if (json['status'] != 'ok') {
        throw TripFailure(json['error']?.toString() ?? 'Delete trip failed.');
      }
    } on TripFailure {
      rethrow;
    } catch (_) {
      throw TripFailure('Could not reach server while deleting trip.');
    }
  }

  Future<void> updateTrip({
    required AppUser user,
    required int tripId,
    List<String>? addCustomerNames,
    List<String>? setCustomerNames,
    int? helperId,
    String? note,
    List<int>? setDriverIds,
  }) async {
    final uri = Uri.parse('${_mobileBase}trips_update.php');
    final payload = <String, dynamic>{
      'trip_id': tripId,
      'role': _roleToString(user.role),
      if (_tryParseInt(user.id) != null) 'userId': _tryParseInt(user.id),
      if (_tryParseInt(user.driverId) != null)
        'driverId': _tryParseInt(user.driverId),
    };

    if (addCustomerNames != null && addCustomerNames.isNotEmpty) {
      payload['add_customer_names'] = addCustomerNames;
    }

    if (setCustomerNames != null && setCustomerNames.isNotEmpty) {
      payload['set_customer_names'] = setCustomerNames;
    }

    if (helperId != null) {
      payload['helper_id'] = helperId;
    }

    if (note != null) {
      payload['note'] = note;
    }

    if (setDriverIds != null && setDriverIds.isNotEmpty) {
      payload['set_driver_ids'] = setDriverIds;
    }

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 300) {
        throw TripFailure(
          'Update trip failed (status: ${response.statusCode}).',
        );
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw TripFailure('Update trip failed (bad JSON response).');
      }

      if (json['status'] != 'ok' && json['ok'] != true) {
        throw TripFailure(json['error']?.toString() ?? 'Update trip failed.');
      }
    } on TripFailure {
      rethrow;
    } catch (_) {
      throw TripFailure('Could not reach server while updating trip.');
    }
  }

  Future<List<TripPlant>> fetchPlantsForUser(AppUser user) async {
    final fallbackPlants = _buildFallbackPlants(user);

    try {
      final uri = Uri.parse('${_mobileBase}plants.php');
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'role': _roleToString(user.role),
          if (_tryParseInt(user.id) != null) 'userId': _tryParseInt(user.id),
          if (_tryParseInt(user.driverId) != null)
            'driverId': _tryParseInt(user.driverId),
        }),
      );

      if (response.statusCode >= 300) {
        debugPrint(
          'TripRepository.fetchPlantsForUser: HTTP ${response.statusCode}',
        );
        if (fallbackPlants.isNotEmpty) return fallbackPlants;
        throw TripFailure(
          'Unable to load plants (status: ${response.statusCode}).',
        );
      }

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        debugPrint(
          'TripRepository.fetchPlantsForUser: bad JSON ${error.runtimeType}',
        );
        if (fallbackPlants.isNotEmpty) return fallbackPlants;
        throw TripFailure('Unable to load plants.');
      }

      if (payload['status'] != 'ok') {
        debugPrint(
          'TripRepository.fetchPlantsForUser: server error ${payload['error']}',
        );
        if (fallbackPlants.isNotEmpty) return fallbackPlants;
        throw TripFailure(
          payload['error']?.toString() ?? 'Unable to load plants.',
        );
      }

      final plantsJson = payload['plants'] as List<dynamic>? ?? const [];
      final uniquePlants = <int, TripPlant>{};

      for (final plant in fallbackPlants) {
        uniquePlants[plant.id] = plant;
      }

      for (final item in plantsJson) {
        final plant = TripPlant.fromJson(item as Map<String, dynamic>);
        if (plant.id > 0) {
          uniquePlants[plant.id] = plant;
        }
      }

      if (uniquePlants.isNotEmpty) {
        return uniquePlants.values.toList(growable: false);
      }

      return const <TripPlant>[];
    } on TripFailure {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        'TripRepository.fetchPlantsForUser: unexpected $error\n$stackTrace',
      );
      if (fallbackPlants.isNotEmpty) return fallbackPlants;
      throw TripFailure('Unable to load plants.');
    }
  }

  List<TripPlant> _buildFallbackPlants(AppUser user) {
    final uniquePlants = <int, TripPlant>{};

    void addFallback(String? idRaw, String? nameRaw) {
      final id = _tryParseInt(idRaw);
      if (id == null || id <= 0) {
        return;
      }
      final name = (nameRaw != null && nameRaw.isNotEmpty)
          ? nameRaw
          : 'Plant $id';
      uniquePlants.putIfAbsent(id, () => TripPlant(id: id, name: name));
    }

    addFallback(user.assignmentPlantId, user.assignmentPlantName);
    addFallback(user.plantId, user.plantName);
    addFallback(user.defaultPlantId, user.defaultPlantName);

    return uniquePlants.values.toList(growable: false);
  }

  Future<List<TripVehicle>> fetchVehiclesForPlant({
    required AppUser user,
    required String plantId,
  }) async {
    final fallbackVehicles = _buildFallbackVehicles(user);

    try {
      final uri = Uri.parse('${_mobileBase}vehicles.php');
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'role': _roleToString(user.role),
          if (_tryParseInt(user.id) != null) 'userId': _tryParseInt(user.id),
          if (_tryParseInt(user.driverId) != null)
            'driverId': _tryParseInt(user.driverId),
          'plantId': _tryParseInt(plantId) ?? plantId,
        }),
      );

      if (response.statusCode >= 300) {
        debugPrint(
          'TripRepository.fetchVehiclesForPlant: HTTP ${response.statusCode}',
        );
        if (fallbackVehicles.isNotEmpty) return fallbackVehicles;
        throw TripFailure(
          'Unable to load vehicles (status: ${response.statusCode}).',
        );
      }

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        debugPrint(
          'TripRepository.fetchVehiclesForPlant: bad JSON ${error.runtimeType}',
        );
        if (fallbackVehicles.isNotEmpty) return fallbackVehicles;
        throw TripFailure('Unable to load vehicles.');
      }

      if (payload['status'] != 'ok') {
        debugPrint(
          'TripRepository.fetchVehiclesForPlant: server error ${payload['error']}',
        );
        if (fallbackVehicles.isNotEmpty) return fallbackVehicles;
        throw TripFailure(
          payload['error']?.toString() ?? 'Unable to load vehicles.',
        );
      }

      final vehiclesJson = payload['vehicles'] as List<dynamic>? ?? const [];
      final uniqueVehicles = <int, TripVehicle>{
        for (final vehicle in fallbackVehicles) vehicle.id: vehicle,
      };

      for (final item in vehiclesJson) {
        final vehicle = TripVehicle.fromJson(item as Map<String, dynamic>);
        if (vehicle.id > 0 && vehicle.number.isNotEmpty) {
          uniqueVehicles[vehicle.id] = vehicle;
        }
      }

      if (uniqueVehicles.isNotEmpty) {
        return uniqueVehicles.values.toList(growable: false);
      }

      return const <TripVehicle>[];
    } on TripFailure {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        'TripRepository.fetchVehiclesForPlant: unexpected $error\n$stackTrace',
      );
      if (fallbackVehicles.isNotEmpty) return fallbackVehicles;
      throw TripFailure('Unable to load vehicles.');
    }
  }

  List<TripVehicle> _buildFallbackVehicles(AppUser user) {
    final unique = <int, TripVehicle>{};

    void add(String? idRaw, String? numberRaw) {
      final id = int.tryParse(idRaw ?? '');
      final number = numberRaw?.trim() ?? '';
      if (id == null || id <= 0 || number.isEmpty) {
        return;
      }
      unique.putIfAbsent(id, () => TripVehicle(id: id, number: number));
    }

    for (final driverVehicle in user.availableVehicles) {
      add(driverVehicle.id, driverVehicle.vehicleNumber);
    }

    add(user.assignmentVehicleId, user.assignmentVehicleNumber);

    return unique.values.toList(growable: false);
  }

  Future<List<TripHelper>> fetchHelpersForPlant({
    required AppUser user,
    required String plantId,
    String? vehicleId,
  }) async {
    final fallbackHelpers = _buildFallbackHelpers(user);

    try {
      final uri = Uri.parse('${_mobileBase}helpers.php');
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'role': _roleToString(user.role),
          if (_tryParseInt(user.id) != null) 'userId': _tryParseInt(user.id),
          if (_tryParseInt(user.driverId) != null)
            'driverId': _tryParseInt(user.driverId),
          'plantId': _tryParseInt(plantId) ?? plantId,
          if (vehicleId != null && vehicleId.isNotEmpty)
            'vehicleId': _tryParseInt(vehicleId) ?? vehicleId,
        }),
      );

      if (response.statusCode >= 300) {
        debugPrint(
          'TripRepository.fetchHelpersForPlant: HTTP ${response.statusCode}',
        );
        return fallbackHelpers;
      }

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        debugPrint(
          'TripRepository.fetchHelpersForPlant: bad JSON ${error.runtimeType}',
        );
        return fallbackHelpers;
      }

      if (payload['status'] != 'ok') {
        debugPrint(
          'TripRepository.fetchHelpersForPlant: server error ${payload['error']}',
        );
        return fallbackHelpers;
      }

      final helpersJson = payload['helpers'] as List<dynamic>? ?? const [];
      final helperMap = <int, TripHelper>{
        for (final helper in fallbackHelpers) helper.id: helper,
      };

      for (final item in helpersJson) {
        final helper = TripHelper.fromJson(item as Map<String, dynamic>);
        if (helper.id > 0 && helper.name.isNotEmpty) {
          helperMap[helper.id] = helper;
        }
      }

      return helperMap.values.toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint(
        'TripRepository.fetchHelpersForPlant: unexpected $error\n$stackTrace',
      );
      return fallbackHelpers;
    }
  }

  List<TripDriver> _buildFallbackDrivers(AppUser user) {
    final drivers = <int, TripDriver>{};

    void add(String? idRaw, String? nameRaw, {String? plantRaw}) {
      final id = int.tryParse(idRaw ?? '');
      final name = nameRaw?.trim() ?? '';
      if (id == null || id <= 0 || name.isEmpty) {
        return;
      }
      final plantId = int.tryParse(plantRaw ?? '');
      drivers.putIfAbsent(
        id,
        () => TripDriver(id: id, name: name, plantId: plantId),
      );
    }

    add(
      user.driverId,
      user.displayName,
      plantRaw: user.plantId ?? user.assignmentPlantId,
    );

    return drivers.values.toList(growable: false);
  }

  List<TripHelper> _buildFallbackHelpers(AppUser user) {
    return const <TripHelper>[];
  }

  List<String> _buildFallbackCustomers(AppUser user) {
    final fallback = <String>[];
    return fallback;
  }

  String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'admin';
      case UserRole.supervisor:
        return 'supervisor';
      case UserRole.driver:
        return 'driver';
    }
  }

  int? _tryParseInt(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return int.tryParse(value);
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  /// Fetches the assigned vehicle for a driver from the driver_vehicle.php API
  Future<int?> getAssignedVehicleId({
    required AppUser user,
    required String plantId,
  }) async {
    try {
      final uri = Uri.parse('${_mobileBase}driver_vehicle.php');
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'role': _roleToString(user.role),
          if (_tryParseInt(user.id) != null) 'userId': _tryParseInt(user.id),
          if (_tryParseInt(user.driverId) != null)
            'driverId': _tryParseInt(user.driverId),
          'plant_id': _tryParseInt(plantId) ?? plantId,
        }),
      );

      if (response.statusCode >= 300) {
        debugPrint(
          'TripRepository.getAssignedVehicleId: HTTP ${response.statusCode}',
        );
        return null;
      }

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        debugPrint(
          'TripRepository.getAssignedVehicleId: bad JSON ${error.runtimeType}',
        );
        return null;
      }

      if (payload['ok'] != true) {
        debugPrint(
          'TripRepository.getAssignedVehicleId: server error ${payload['error']}',
        );
        return null;
      }

      final vehicleId = payload['vehicle_id'];
      if (vehicleId is int && vehicleId > 0) {
        return vehicleId;
      }

      return null;
    } catch (error, stackTrace) {
      debugPrint(
        'TripRepository.getAssignedVehicleId: unexpected $error\n$stackTrace',
      );
      return null;
    }
  }
}
