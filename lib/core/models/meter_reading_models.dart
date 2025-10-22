import 'package:intl/intl.dart';

class MeterWindowInfo {
  const MeterWindowInfo({
    required this.label,
    required this.isOpen,
    required this.currentDate,
    this.reason,
  });

  final String label;
  final bool isOpen;
  final DateTime currentDate;
  final String? reason;

  factory MeterWindowInfo.fromJson(Map<String, dynamic> json) {
    final currentDateRaw = json['currentDate'] as String?;
    final currentDate = currentDateRaw != null
        ? DateTime.tryParse(currentDateRaw) ?? DateTime.now()
        : DateTime.now();
    return MeterWindowInfo(
      label: json['label']?.toString() ?? 'closed',
      isOpen: json['isOpen'] == true,
      reason: json['reason']?.toString(),
      currentDate: currentDate,
    );
  }
}

class MeterVehicleStatus {
  const MeterVehicleStatus({
    required this.vehicleId,
    required this.vehicleNumber,
    required this.status,
    required this.statusLabel,
    this.readingKm,
    this.submittedAt,
    this.photoUrl,
    this.notes,
    this.driverId,
    this.driverName,
    this.submissionStatus,
    this.submissionId,
  });

  final int vehicleId;
  final String vehicleNumber;
  final String status;
  final String statusLabel;
  final double? readingKm;
  final DateTime? submittedAt;
  final String? photoUrl;
  final String? notes;
  final int? driverId;
  final String? driverName;
  final String? submissionStatus;
  final int? submissionId;

  bool get isSubmitted => status == 'submitted';

  String get formattedReading {
    if (readingKm == null) {
      return '--';
    }
    final formatter = NumberFormat('#,##0.0');
    return formatter.format(readingKm);
  }

  factory MeterVehicleStatus.fromJson(Map<String, dynamic> json) {
    DateTime? submittedAt;
    final submittedRaw = json['submittedAt']?.toString();
    if (submittedRaw != null && submittedRaw.isNotEmpty) {
      submittedAt = DateTime.tryParse(submittedRaw);
    }
    return MeterVehicleStatus(
      vehicleId: int.tryParse(json['vehicleId'].toString()) ?? 0,
      vehicleNumber: json['vehicleNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? 'due',
      statusLabel: json['statusLabel']?.toString() ?? 'Pending',
      readingKm: json['readingKm'] != null
          ? double.tryParse(json['readingKm'].toString())
          : null,
      submittedAt: submittedAt,
      photoUrl: json['photoUrl']?.toString(),
      notes: json['notes']?.toString(),
      driverId: json['driverId'] != null
          ? int.tryParse(json['driverId'].toString())
          : null,
      driverName: json['driverName']?.toString(),
      submissionStatus: json['submissionStatus']?.toString(),
      submissionId: json['submissionId'] != null
          ? int.tryParse(json['submissionId'].toString())
          : null,
    );
  }
}

class MeterPlantStatus {
  const MeterPlantStatus({
    required this.plantId,
    required this.plantName,
    required this.vehicles,
  });

  final int plantId;
  final String plantName;
  final List<MeterVehicleStatus> vehicles;

  factory MeterPlantStatus.fromJson(Map<String, dynamic> json) {
    final vehiclesJson = json['vehicles'] as List<dynamic>? ?? const [];
    return MeterPlantStatus(
      plantId: int.tryParse(json['plantId'].toString()) ?? 0,
      plantName: json['plantName']?.toString() ?? '',
      vehicles: vehiclesJson
          .map(
            (item) => MeterVehicleStatus.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class MeterStatusData {
  const MeterStatusData({
    required this.monthKey,
    required this.window,
    required this.sections,
    required this.pendingCount,
  });

  final String monthKey;
  final MeterWindowInfo window;
  final List<MeterPlantStatus> sections;
  final int pendingCount;

  factory MeterStatusData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final sectionsJson = data['sections'] as List<dynamic>? ?? const [];
    return MeterStatusData(
      monthKey:
          data['monthKey']?.toString() ??
          DateFormat('yyyy-MM').format(DateTime.now()),
      window: MeterWindowInfo.fromJson(
        (data['window'] as Map<String, dynamic>?) ?? const {},
      ),
      sections: sectionsJson
          .map(
            (item) => MeterPlantStatus.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      pendingCount: data['pendingCount'] is num
          ? (data['pendingCount'] as num).toInt()
          : int.tryParse(data['pendingCount']?.toString() ?? '0') ?? 0,
    );
  }
}

class MeterHistoryEntry {
  const MeterHistoryEntry({
    required this.id,
    required this.monthKey,
    required this.readingKm,
    required this.photoUrl,
    this.notes,
    this.status,
    this.submittedAt,
    this.reviewedAt,
    this.reviewNote,
    this.driverName,
    this.source,
  });

  final int id;
  final String monthKey;
  final double readingKm;
  final String photoUrl;
  final String? notes;
  final String? status;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? driverName;
  final String? source;

  factory MeterHistoryEntry.fromJson(Map<String, dynamic> json) {
    DateTime? submitted;
    if (json['submitted_at'] != null) {
      submitted = DateTime.tryParse(json['submitted_at'].toString());
    }
    DateTime? reviewed;
    if (json['reviewed_at'] != null) {
      reviewed = DateTime.tryParse(json['reviewed_at'].toString());
    }
    return MeterHistoryEntry(
      id: int.tryParse(json['id'].toString()) ?? 0,
      monthKey: json['month_key']?.toString() ?? '',
      readingKm: double.tryParse(json['reading_km'].toString()) ?? 0.0,
      photoUrl: json['photo_url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      status: json['status']?.toString(),
      submittedAt: submitted,
      reviewedAt: reviewed,
      reviewNote: json['review_note']?.toString(),
      driverName: json['driver_name']?.toString(),
      source: json['source']?.toString(),
    );
  }
}

class MeterReadingRequest {
  MeterReadingRequest({
    required this.userId,
    required this.driverId,
    required this.vehicleId,
    required this.readingKm,
    required this.photoPath,
    this.notes,
  });

  final int userId;
  final int driverId;
  final int vehicleId;
  final double readingKm;
  final String photoPath;
  final String? notes;
}
