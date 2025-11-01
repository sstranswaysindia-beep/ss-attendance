import 'package:collection/collection.dart';

enum TyreCheckpointResult {
  acceptable('acceptable'),
  caution('caution'),
  nonAcceptable('non_acceptable');

  const TyreCheckpointResult(this.apiValue);
  final String apiValue;

  static TyreCheckpointResult fromApi(String value) {
    return TyreCheckpointResult.values.firstWhere(
      (item) => item.apiValue == value,
      orElse: () => TyreCheckpointResult.acceptable,
    );
  }
}

class SafetyModule {
  const SafetyModule({required this.key, required this.label});

  factory SafetyModule.fromJson(Map<String, dynamic> json) {
    return SafetyModule(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }

  final String key;
  final String label;
}

class TyreCheckpoint {
  const TyreCheckpoint({
    required this.number,
    required this.textHi,
    required this.textEn,
  });

  factory TyreCheckpoint.fromJson(Map<String, dynamic> json) {
    return TyreCheckpoint(
      number: json['no'] is int
          ? json['no'] as int
          : int.tryParse(json['no']?.toString() ?? '0') ?? 0,
      textHi: json['text_hi']?.toString() ?? '',
      textEn: json['text_en']?.toString() ?? '',
    );
  }

  final int number;
  final String textHi;
  final String textEn;
}

class TyreInstructions {
  const TyreInstructions({
    required this.checkpoints,
    required this.psiMin,
    required this.psiMax,
  });

  factory TyreInstructions.fromJson(Map<String, dynamic> json) {
    final checkpoints = (json['checkpoints'] as List<dynamic>?)
            ?.map((entry) => TyreCheckpoint.fromJson(
                  entry as Map<String, dynamic>,
                ))
            .toList(growable: false) ??
        const <TyreCheckpoint>[];

    final psi = json['psi'] as Map<String, dynamic>? ?? const {};

    return TyreInstructions(
      checkpoints: checkpoints,
      psiMin: _parseDouble(psi['min']) ?? 0,
      psiMax: _parseDouble(psi['max']) ?? 0,
    );
  }

  final List<TyreCheckpoint> checkpoints;
  final double psiMin;
  final double psiMax;
}

class SafetyVehicle {
  const SafetyVehicle({
    required this.id,
    required this.vehicleNumber,
    required this.plantId,
    required this.tyreCount,
    this.plantName,
  });

  factory SafetyVehicle.fromJson(Map<String, dynamic> json) {
    return SafetyVehicle(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      vehicleNumber: json['vehicle_no']?.toString() ?? '',
      plantId: int.tryParse(json['plant_id']?.toString() ?? '') ?? 0,
      tyreCount: int.tryParse(json['tyre_count']?.toString() ?? '') ?? 0,
      plantName: json['plant_name']?.toString(),
    );
  }

  final int id;
  final String vehicleNumber;
  final int plantId;
  final int tyreCount;
  final String? plantName;
}

class TyreInspectionStart {
  const TyreInspectionStart({
    required this.inspectionId,
    required this.positions,
  });

  factory TyreInspectionStart.fromJson(Map<String, dynamic> json) {
    final positions = (json['positions'] as List<dynamic>?)
            ?.map((entry) => entry.toString())
            .toList(growable: false) ??
        const <String>[];

    return TyreInspectionStart(
      inspectionId:
          int.tryParse(json['inspection_id']?.toString() ?? '') ?? 0,
      positions: positions,
    );
  }

  final int inspectionId;
  final List<String> positions;
}

class TyreAnswer {
  const TyreAnswer({
    required this.checkpointNo,
    required this.result,
    this.remark,
  });

  final int checkpointNo;
  final TyreCheckpointResult result;
  final String? remark;

  Map<String, dynamic> toJson() {
    return {
      'checkpoint_no': checkpointNo,
      'result': result.apiValue,
      if (remark != null && remark!.trim().isNotEmpty) 'remark': remark!.trim(),
    };
  }
}

class TyreChecklistTyreState {
  TyreChecklistTyreState({
    required this.position,
    required this.answers,
    required this.psi,
    this.photoUrl,
    this.photoPath,
    this.warnings = const <String>[],
    this.expectedCheckpoints = 8,
  });

  final String position;
  final List<TyreAnswer> answers;
  final double psi;
  final String? photoUrl;
  final String? photoPath;
  final List<String> warnings;
  final int expectedCheckpoints;

  bool get isComplete => answers.isNotEmpty && answers.length >= expectedCheckpoints;

  bool get hasCaution => answers
      .firstWhereOrNull((answer) => answer.result == TyreCheckpointResult.caution)
      ?.result !=
      null;

  bool get hasCriticalIssue => answers
      .firstWhereOrNull(
        (answer) => answer.result == TyreCheckpointResult.nonAcceptable,
      )
      ?.result !=
      null;

  bool get hasIssue => hasCriticalIssue || hasCaution;

  bool psiOutsideRange(double min, double max) {
    return psi < min || psi > max;
  }
}

class TyreSaveResponse {
  const TyreSaveResponse({this.photoUrl, this.warnings = const <String>[]});

  factory TyreSaveResponse.fromJson(Map<String, dynamic> json) {
    final warnings = (json['warnings'] as List<dynamic>?)
            ?.map((entry) => entry.toString())
            .toList(growable: false) ??
        const <String>[];

    return TyreSaveResponse(
      photoUrl: json['photo_url']?.toString(),
      warnings: warnings,
    );
  }

  final String? photoUrl;
  final List<String> warnings;
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
