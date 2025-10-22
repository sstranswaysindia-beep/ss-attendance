enum DocumentStatus { active, dueSoon, expired, notApplicable }

DocumentStatus documentStatusFromString(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'duesoon':
    case 'due_soon':
    case 'due-soon':
    case 'due soon':
      return DocumentStatus.dueSoon;
    case 'expired':
      return DocumentStatus.expired;
    case 'notapplicable':
    case 'not_applicable':
    case 'not-applicable':
    case 'not applicable':
      return DocumentStatus.notApplicable;
    case 'active':
    default:
      return DocumentStatus.active;
  }
}

String documentStatusLabel(DocumentStatus status) {
  switch (status) {
    case DocumentStatus.dueSoon:
      return 'Due Soon';
    case DocumentStatus.expired:
      return 'Expired';
    case DocumentStatus.notApplicable:
      return 'Not Applicable';
    case DocumentStatus.active:
      return 'Active';
  }
}

class DocumentCounts {
  const DocumentCounts({
    required this.active,
    required this.dueSoon,
    required this.expired,
    required this.notApplicable,
  });

  final int active;
  final int dueSoon;
  final int expired;
  final int notApplicable;

  int get total => active + dueSoon + expired + notApplicable;

  factory DocumentCounts.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DocumentCounts.zero();
    }
    return DocumentCounts(
      active: _asInt(json['active']),
      dueSoon: _asInt(json['dueSoon']),
      expired: _asInt(json['expired']),
      notApplicable: _asInt(json['notApplicable']),
    );
  }

  const DocumentCounts.zero()
      : this(active: 0, dueSoon: 0, expired: 0, notApplicable: 0);
}

class DocumentPlant {
  const DocumentPlant({
    required this.plantId,
    required this.plantName,
  });

  final int plantId;
  final String plantName;

  factory DocumentPlant.fromJson(Map<String, dynamic> json) => DocumentPlant(
        plantId: _asInt(json['plantId']),
        plantName: (json['plantName'] ?? '') as String,
      );
}

class DocumentRecord {
  DocumentRecord({
    required this.documentId,
    required this.name,
    required this.type,
    required this.status,
    required this.statusLabel,
    this.expiryDate,
    this.daysUntilExpiry,
    this.googleDriveLink,
    this.filePath,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.uploadedAt,
    this.updatedAt,
    this.notes,
    this.isActive = true,
    this.naReason,
  });

  final int documentId;
  final String name;
  final String type;
  final DocumentStatus status;
  final String statusLabel;
  final DateTime? expiryDate;
  final int? daysUntilExpiry;
  final String? googleDriveLink;
  final String? filePath;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final DateTime? uploadedAt;
  final DateTime? updatedAt;
  final String? notes;
  final bool isActive;
  final String? naReason;

  factory DocumentRecord.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString();
    final parsedStatus = documentStatusFromString(rawStatus);
    return DocumentRecord(
      documentId: _asInt(json['documentId']),
      name: (json['name'] ?? '') as String,
      type: (json['type'] ?? '') as String,
      status: parsedStatus,
      statusLabel: (json['statusLabel'] ?? documentStatusLabel(parsedStatus))
          as String,
      expiryDate: _parseDate(json['expiryDate']),
      daysUntilExpiry: _asNullableInt(json['daysUntilExpiry']),
      googleDriveLink: _asNullableString(json['googleDriveLink']),
      filePath: _asNullableString(json['filePath']),
      fileName: _asNullableString(json['fileName']),
      mimeType: _asNullableString(json['mimeType']),
      fileSize: _asNullableInt(json['fileSize']),
      uploadedAt: _parseDateTime(json['uploadedAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      notes: _asNullableString(json['notes']),
      isActive: json['isActive'] == null ? true : json['isActive'] == true,
      naReason: _asNullableString(json['naReason']),
    );
  }

  bool get isNotApplicable => status == DocumentStatus.notApplicable;
}

class DocumentVehicle {
  DocumentVehicle({
    required this.vehicleId,
    required this.vehicleNumber,
    required this.plantId,
    required this.plantName,
    required this.documents,
  });

  final int vehicleId;
  final String vehicleNumber;
  final int? plantId;
  final String plantName;
  final List<DocumentRecord> documents;

  factory DocumentVehicle.fromJson(Map<String, dynamic> json) {
    final docsJson = json['documents'] as List<dynamic>? ?? const [];
    return DocumentVehicle(
      vehicleId: _asInt(json['vehicleId']),
      vehicleNumber: (json['vehicleNumber'] ?? '') as String,
      plantId: _asNullableInt(json['plantId']),
      plantName: (json['plantName'] ?? '') as String,
      documents: docsJson
          .map((item) => DocumentRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class DocumentDriver {
  DocumentDriver({
    required this.driverId,
    required this.driverName,
    required this.role,
    required this.plantId,
    required this.plantName,
    required this.documents,
  });

  final int driverId;
  final String driverName;
  final String role;
  final int? plantId;
  final String plantName;
  final List<DocumentRecord> documents;

  factory DocumentDriver.fromJson(Map<String, dynamic> json) {
    final docsJson = json['documents'] as List<dynamic>? ?? const [];
    return DocumentDriver(
      driverId: _asInt(json['driverId']),
      driverName: (json['driverName'] ?? '') as String,
      role: (json['role'] ?? '') as String,
      plantId: _asNullableInt(json['plantId']),
      plantName: (json['plantName'] ?? '') as String,
      documents: docsJson
          .map((item) => DocumentRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class DocumentFilters {
  DocumentFilters({
    required this.plants,
    required this.roles,
    required this.vehicleDocTypes,
    required this.driverDocTypes,
  });

  final List<DocumentPlant> plants;
  final List<String> roles;
  final List<String> vehicleDocTypes;
  final List<String> driverDocTypes;

  factory DocumentFilters.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return DocumentFilters(
        plants: const [],
        roles: const [],
        vehicleDocTypes: const [],
        driverDocTypes: const [],
      );
    }
    final plantsJson = json['plants'] as List<dynamic>? ?? const [];
    return DocumentFilters(
      plants: plantsJson
          .map((item) => DocumentPlant.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      vehicleDocTypes: (json['documentTypes']?['vehicle'] as List<dynamic>? ??
              const [])
          .map((e) => e.toString())
          .toList(growable: false),
      driverDocTypes: (json['documentTypes']?['driver'] as List<dynamic>? ??
              const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}

class DocumentOverviewData {
  DocumentOverviewData({
    required this.vehicleCounts,
    required this.driverCounts,
    required this.totalCounts,
    required this.filters,
    required this.vehicles,
    required this.drivers,
    required this.statusWindowDays,
    this.generatedAt,
  });

  final DocumentCounts vehicleCounts;
  final DocumentCounts driverCounts;
  final DocumentCounts totalCounts;
  final DocumentFilters filters;
  final List<DocumentVehicle> vehicles;
  final List<DocumentDriver> drivers;
  final int statusWindowDays;
  final DateTime? generatedAt;

  DocumentVehicle? vehicleById(int? id) {
    if (id == null) {
      return null;
    }
    for (final vehicle in vehicles) {
      if (vehicle.vehicleId == id) {
        return vehicle;
      }
    }
    return null;
  }

  DocumentDriver? driverById(int? id) {
    if (id == null) {
      return null;
    }
    for (final driver in drivers) {
      if (driver.driverId == id) {
        return driver;
      }
    }
    return null;
  }

  factory DocumentOverviewData.fromJson(Map<String, dynamic> json) {
    final vehiclesJson = json['vehicles'] as List<dynamic>? ?? const [];
    final driversJson = json['drivers'] as List<dynamic>? ?? const [];
    return DocumentOverviewData(
      vehicleCounts:
          DocumentCounts.fromJson(json['summary']?['vehicles'] as Map<String, dynamic>?),
      driverCounts:
          DocumentCounts.fromJson(json['summary']?['drivers'] as Map<String, dynamic>?),
      totalCounts:
          DocumentCounts.fromJson(json['summary']?['total'] as Map<String, dynamic>?),
      filters: DocumentFilters.fromJson(json['filters'] as Map<String, dynamic>?),
      vehicles: vehiclesJson
          .map((item) => DocumentVehicle.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      drivers: driversJson
          .map((item) => DocumentDriver.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      statusWindowDays:
          json['statusWindowDays'] is int ? json['statusWindowDays'] as int : 30,
      generatedAt: _parseDateTime(json['generatedAt']),
    );
  }
}

int _asInt(dynamic value) {
  if (value == null) {
    return 0;
  }
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  final parsed = int.tryParse(value.toString());
  return parsed ?? 0;
}

int? _asNullableInt(dynamic value) {
  if (value == null || value == '') {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  return int.tryParse(value.toString());
}

String? _asNullableString(dynamic value) {
  if (value == null) {
    return null;
  }
  final stringValue = value.toString();
  return stringValue.isEmpty ? null : stringValue;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) {
    return null;
  }
  final stringValue = value.toString();
  if (stringValue.isEmpty || stringValue == '0000-00-00') {
    return null;
  }
  return DateTime.tryParse(stringValue);
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  final stringValue = value.toString();
  if (stringValue.isEmpty) {
    return null;
  }
  return DateTime.tryParse(stringValue);
}
