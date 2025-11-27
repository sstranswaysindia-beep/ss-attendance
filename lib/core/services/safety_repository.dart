import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/safety_models.dart';

class SafetyRepository {
  SafetyRepository({http.Client? client, Uri? baseUri, AppUser? currentUser})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ??
            Uri.parse('https://sstranswaysindia.com/api/safety/'),
        _currentUser = currentUser;

  final http.Client _client;
  final Uri _baseUri;
  final AppUser? _currentUser;

  Uri _resolve(String path, [Map<String, String>? query]) {
    return _baseUri.replace(
      path: '${_baseUri.path}$path',
      queryParameters: query ?? _baseUri.queryParameters,
    );
  }

  Map<String, String> _authQuery([AppUser? user]) {
    final target = user ?? _currentUser;
    if (target == null) return const {};

    String? role;
    switch (target.role) {
      case UserRole.driver:
        role = 'driver';
        break;
      case UserRole.supervisor:
        role = 'supervisor';
        break;
      case UserRole.admin:
        role = 'admin';
        break;
    }

    Map<String, String> data = {
      if (role != null) 'role': role,
    };

    int? toInt(String? value) => value == null ? null : int.tryParse(value);

    final userId = toInt(target.id);
    if (userId != null) data['userId'] = userId.toString();

    final driverId = toInt(target.driverId);
    if (driverId != null) data['driverId'] = driverId.toString();

    final plantId = toInt(target.plantId ?? target.assignmentPlantId ?? target.defaultPlantId);
    if (plantId != null) data['plantId'] = plantId.toString();

    if (target.supervisedPlantIds.isNotEmpty) {
      data['supervisedPlantIds'] = target.supervisedPlantIds
          .map((entry) => entry.toString())
          .join(',');
    }

    return data;
  }

  Future<List<SafetyModule>> fetchModules() async {
    final uri = _resolve('modules.php');
    final response = await _client.get(uri);
    if (response.statusCode >= 300) {
      throw Exception('Failed to load safety modules (${response.statusCode})');
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (error, stackTrace) {
      debugPrint(
        'SafetyRepository.fetchVehicles: invalid JSON ${error.message}\n${response.body}',
      );
      throw Exception('Invalid response while loading vehicles');
    }
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to load modules');
    }

    final modules = (decoded['modules'] as List<dynamic>? ?? const [])
        .map((module) => SafetyModule.fromJson(module as Map<String, dynamic>))
        .toList(growable: false);

    if (modules.isEmpty) {
      return const [
        SafetyModule(key: 'tyre_checklist', label: 'Tyre Checklist'),
        SafetyModule(key: 'incab', label: 'In-Cab'),
        SafetyModule(key: 'spot_audit', label: 'Spot Audit'),
        SafetyModule(key: 'training', label: 'Training'),
      ];
    }
    return modules;
  }

  Future<TyreInstructions> fetchTyreInstructions() async {
    try {
      final uri = _resolve('tyres/instructions.php');
      final response = await _client.get(uri);
      if (response.statusCode >= 300) {
        throw Exception(
          'Failed to load tyre instructions (${response.statusCode})',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] != true) {
        throw Exception(
          decoded['error']?.toString() ?? 'Failed to load instructions',
        );
      }

      return TyreInstructions.fromJson(decoded);
    } catch (error, stackTrace) {
      debugPrint('SafetyRepository.fetchTyreInstructions fallback: $error\n$stackTrace');
      return _fallbackInstructions();
    }
  }

  Future<List<SafetyVehicle>> fetchVehicles({
    AppUser? user,
  }) async {
    final effectiveUser = user ?? _currentUser;
    final scope = effectiveUser?.role == UserRole.supervisor ? 'plant' : 'mine';
    final query = {
      'scope': scope,
      ..._authQuery(effectiveUser),
      if (effectiveUser?.assignmentPlantId != null &&
          effectiveUser!.assignmentPlantId!.isNotEmpty)
        'plantId': effectiveUser.assignmentPlantId!,
    };
    final uri = _resolve('vehicles.php', query);
    final response = await _client.get(uri);
    if (response.statusCode >= 300) {
      throw Exception('Failed to load vehicles (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to load vehicles');
    }

    final vehicles = (decoded['vehicles'] as List<dynamic>? ?? const [])
        .map((entry) => SafetyVehicle.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);

    vehicles.sort((a, b) => a.vehicleNumber.compareTo(b.vehicleNumber));
    return vehicles;
  }

  Future<TyreInspectionStart> startInspection({
    required int vehicleId,
    AppUser? user,
  }) async {
    final uri = _resolve('tyres/inspections/start.php', _authQuery(user));
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'vehicle_id': vehicleId}),
    );

    if (response.statusCode >= 300) {
      String? message;
      try {
        final decodedError = jsonDecode(response.body);
        if (decodedError is Map<String, dynamic>) {
          message = decodedError['error']?.toString();
        }
      } catch (_) {
        // ignore parse errors
      }
      throw Exception(message ?? 'Failed to start inspection (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to start inspection');
    }

    return TyreInspectionStart.fromJson(decoded);
  }

  Future<TyreSaveResponse> saveTyre({
    required int inspectionId,
    required String positionCode,
    required double psi,
    List<TyreAnswer> answers = const [],
    String? photoBase64,
    AppUser? user,
  }) async {
    final uri = _resolve('tyres/inspections/save_tyre.php', _authQuery(user));
    final payload = <String, dynamic>{
      'inspection_id': inspectionId,
      'position_code': positionCode,
      'psi': psi,
      'answers': answers.map((answer) => answer.toJson()).toList(),
    };
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      payload['photo_base64'] = photoBase64;
    }
    debugPrint(
      'SafetyRepository.saveTyre payload '
      'inspection=$inspectionId, position=$positionCode -> ${jsonEncode(payload)}',
    );

    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    debugPrint(
      'SafetyRepository.saveTyre($inspectionId, $positionCode) '
      '-> ${response.statusCode}: ${response.body}',
    );

    if (response.statusCode >= 300) {
      throw Exception('Failed to save tyre (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to save tyre');
    }

    if (decoded.containsKey('warnings')) {
      return TyreSaveResponse.fromJson(decoded);
    }
    return TyreSaveResponse(photoUrl: decoded['photo_url']?.toString());
  }

  Future<TyreChecklistTyreState?> fetchTyreState({
    required int inspectionId,
    required String positionCode,
    int expectedCheckpoints = 8,
    AppUser? user,
  }) async {
    final uri = _resolve('tyres/inspections/get_tyre.php', _authQuery(user));
    final payload = {
      'inspection_id': inspectionId,
      'position_code': positionCode,
    };

    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    debugPrint(
      'SafetyRepository.fetchTyreState($inspectionId, $positionCode) '
      '-> ${response.statusCode}: ${response.body}',
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode >= 300) {
      throw Exception('Failed to load tyre state (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to load tyre state');
    }

    final answers = (decoded['answers'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) {
      final map = entry as Map<String, dynamic>;
      return TyreAnswer(
        checkpointNo: map['checkpoint_no'] is int
            ? map['checkpoint_no'] as int
            : int.tryParse(map['checkpoint_no']?.toString() ?? '0') ?? 0,
        result: TyreCheckpointResult.fromApi(map['result']?.toString() ?? 'acceptable'),
        remark: (map['remark']?.toString().trim().isEmpty ?? true)
            ? null
            : map['remark']?.toString().trim(),
      );
    }).toList(growable: false);

    final psi = decoded['psi'];
    return TyreChecklistTyreState(
      position: positionCode,
      answers: answers,
      psi: psi is num ? psi.toDouble() : 0,
      photoUrl: decoded['photo_url']?.toString(),
      warnings: (decoded['warnings'] as List<dynamic>? ?? const <dynamic>[]) // propagate warnings if any
          .map((entry) => entry.toString())
          .toList(growable: false),
      expectedCheckpoints: expectedCheckpoints,
    );
  }

  Future<void> submitInspection({
    required int inspectionId,
    String? overallNote,
    AppUser? user,
  }) async {
    final uri = _resolve('tyres/inspections/submit.php', _authQuery(user));
    final payload = <String, dynamic>{
      'inspection_id': inspectionId,
      if (overallNote != null && overallNote.trim().isNotEmpty)
        'overall_note': overallNote.trim(),
    };

    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('Failed to submit inspection (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Failed to submit inspection');
    }
  }

  TyreInstructions _fallbackInstructions() {
    const checkpoints = [
      TyreCheckpoint(
        number: 1,
        textHi: 'टायर में कील / पत्थर के लिए जाँच।',
        textEn: 'Check visually for Nails / stones.',
      ),
      TyreCheckpoint(
        number: 2,
        textHi: 'संभावित लीक (वाल्व कैप्स / एक्सटेंशन वाल्व) के लिए जाँच।',
        textEn: 'Check visually for possible leakage (valve caps / extension valves).',
      ),
      TyreCheckpoint(
        number: 3,
        textHi: 'टायर में हवा का दबाव जाँच।',
        textEn: 'Check air pressure in the tyre.',
      ),
      TyreCheckpoint(
        number: 4,
        textHi: 'फुलाव और कट्स के लिए टायर की साइडवॉल्स की जाँच।',
        textEn: 'Check visually for bumps and cuts on tyre sidewalls.',
      ),
      TyreCheckpoint(
        number: 5,
        textHi: 'अगर अनियमित घिसाव है — वाहन के सस्पेंशन / रिम के नट्स की जाँच करें।',
        textEn: 'If irregular wear—check suspension / nuts on rims.',
      ),
      TyreCheckpoint(
        number: 6,
        textHi: 'टायर की ट्रेड गहराई 75% चौड़ाई और परिधि पर जाँचें।',
        textEn: 'Check tread depth ~75% across width and circumference.',
      ),
      TyreCheckpoint(
        number: 7,
        textHi: 'एक ही धुरी/एक्सल पर एक ही प्रकार/आकार/कंपनी के टायर इस्तेमाल हों।',
        textEn: 'Same manufacturer/type/size/service description/wear on same axle.',
      ),
      TyreCheckpoint(
        number: 8,
        textHi: 'दिशात्मक टायर विपरीत दिशा में न लगाएँ।',
        textEn: 'Do not use directional tyres in opposite direction.',
      ),
    ];

    return const TyreInstructions(
      checkpoints: checkpoints,
      psiMin: 120,
      psiMax: 130,
    );
  }
}
