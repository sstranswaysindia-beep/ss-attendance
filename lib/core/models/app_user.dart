import 'driver_vehicle.dart';

enum UserRole { admin, supervisor, driver, referral }

class AppUser {
  AppUser({
    required this.id,
    required this.displayName,
    required this.role,
    this.username,
    this.employeeId,
    this.driverId,
    this.plantId,
    this.plantName,
    this.defaultPlantId,
    this.defaultPlantName,
    this.assignmentId,
    this.assignmentPlantId,
    this.assignmentPlantName,
    this.assignmentVehicleId,
    this.assignmentVehicleNumber,
    this.salary,
    this.profilePhoto,
    this.aadhaar,
    this.contactNumber,
    this.esiNumber,
    this.uanNumber,
    this.ifscCode,
    this.ifscVerified,
    this.bankAccount,
    this.branchName,
    this.fatherName,
    this.address,
    this.dlNumber,
    this.dlValidity,
    this.dlIssueDate,
    this.nomineeName,
    this.nomineeRelation,
    this.nomineeContact,
    this.vehicleNumber,
    this.driverRole,
    this.availableVehicles = const <DriverVehicle>[],
    this.joiningDate,
    this.supervisorName,
    this.supervisedPlants = const <Map<String, dynamic>>[],
    this.supervisedPlantIds = const <dynamic>[],
    this.canViewDocuments = false,
    this.geofencingEnabled = false,
    this.proxyEnabled = false,
    this.trainingRequired = false,
    this.advanceEntryAllowed = false,
    this.employeeRegEnabled = false,
  });

  final String id;
  final String displayName;
  final UserRole role;
  final String? username;
  final String? employeeId;
  final String? driverId;
  final String? plantId;
  final String? plantName;
  final String? defaultPlantId;
  final String? defaultPlantName;
  final String? assignmentId;
  final String? assignmentPlantId;
  final String? assignmentPlantName;
  final String? assignmentVehicleId;
  final String? assignmentVehicleNumber;
  final String? salary;
  String? profilePhoto;
  final String? aadhaar;
  final String? contactNumber;
  final String? esiNumber;
  final String? uanNumber;
  final String? ifscCode;
  final bool? ifscVerified;
  final String? bankAccount;
  final String? branchName;
  final String? fatherName;
  final String? address;
  final String? dlNumber;
  final String? dlValidity;
  final String? dlIssueDate;
  final String? nomineeName;
  final String? nomineeRelation;
  final String? nomineeContact;
  final String? vehicleNumber;
  final String? driverRole;
  final List<DriverVehicle> availableVehicles;
  final DateTime? joiningDate;
  final String? supervisorName;
  final List<Map<String, dynamic>> supervisedPlants;
  final List<dynamic> supervisedPlantIds;
  final bool canViewDocuments;
  final bool geofencingEnabled;
  final bool proxyEnabled;
  final bool trainingRequired;
  final bool advanceEntryAllowed;
  final bool employeeRegEnabled;

  AppUser copyWith({
    String? id,
    String? displayName,
    UserRole? role,
    String? username,
    String? employeeId,
    String? driverId,
    String? plantId,
    String? plantName,
    String? defaultPlantId,
    String? defaultPlantName,
    String? assignmentId,
    String? assignmentPlantId,
    String? assignmentPlantName,
    String? assignmentVehicleId,
    String? assignmentVehicleNumber,
    String? salary,
    String? profilePhoto,
    String? aadhaar,
    String? contactNumber,
    String? esiNumber,
    String? uanNumber,
    String? ifscCode,
    bool? ifscVerified,
    String? bankAccount,
    String? branchName,
    String? fatherName,
    String? address,
    String? dlNumber,
    String? dlValidity,
    String? dlIssueDate,
    String? nomineeName,
    String? nomineeRelation,
    String? nomineeContact,
    String? vehicleNumber,
    String? driverRole,
    List<DriverVehicle>? availableVehicles,
    DateTime? joiningDate,
    String? supervisorName,
    List<Map<String, dynamic>>? supervisedPlants,
    List<dynamic>? supervisedPlantIds,
    bool? canViewDocuments,
    bool? geofencingEnabled,
    bool? proxyEnabled,
    bool? trainingRequired,
    bool? advanceEntryAllowed,
    bool? employeeRegEnabled,
  }) {
    return AppUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      username: username ?? this.username,
      employeeId: employeeId ?? this.employeeId,
      driverId: driverId ?? this.driverId,
      plantId: plantId ?? this.plantId,
      plantName: plantName ?? this.plantName,
      defaultPlantId: defaultPlantId ?? this.defaultPlantId,
      defaultPlantName: defaultPlantName ?? this.defaultPlantName,
      assignmentId: assignmentId ?? this.assignmentId,
      assignmentPlantId: assignmentPlantId ?? this.assignmentPlantId,
      assignmentPlantName: assignmentPlantName ?? this.assignmentPlantName,
      assignmentVehicleId: assignmentVehicleId ?? this.assignmentVehicleId,
      assignmentVehicleNumber:
          assignmentVehicleNumber ?? this.assignmentVehicleNumber,
      salary: salary ?? this.salary,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      aadhaar: aadhaar ?? this.aadhaar,
      contactNumber: contactNumber ?? this.contactNumber,
      esiNumber: esiNumber ?? this.esiNumber,
      uanNumber: uanNumber ?? this.uanNumber,
      ifscCode: ifscCode ?? this.ifscCode,
      ifscVerified: ifscVerified ?? this.ifscVerified,
      bankAccount: bankAccount ?? this.bankAccount,
      branchName: branchName ?? this.branchName,
      fatherName: fatherName ?? this.fatherName,
      address: address ?? this.address,
      dlNumber: dlNumber ?? this.dlNumber,
      dlValidity: dlValidity ?? this.dlValidity,
      dlIssueDate: dlIssueDate ?? this.dlIssueDate,
      nomineeName: nomineeName ?? this.nomineeName,
      nomineeRelation: nomineeRelation ?? this.nomineeRelation,
      nomineeContact: nomineeContact ?? this.nomineeContact,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      driverRole: driverRole ?? this.driverRole,
      availableVehicles: availableVehicles ?? this.availableVehicles,
      joiningDate: joiningDate ?? this.joiningDate,
      supervisorName: supervisorName ?? this.supervisorName,
      supervisedPlants: supervisedPlants ?? this.supervisedPlants,
      supervisedPlantIds: supervisedPlantIds ?? this.supervisedPlantIds,
      canViewDocuments: canViewDocuments ?? this.canViewDocuments,
      geofencingEnabled: geofencingEnabled ?? this.geofencingEnabled,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      trainingRequired: trainingRequired ?? this.trainingRequired,
      advanceEntryAllowed: advanceEntryAllowed ?? this.advanceEntryAllowed,
      employeeRegEnabled: employeeRegEnabled ?? this.employeeRegEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'role': role.name,
      'username': username,
      'employeeId': employeeId,
      'driverId': driverId,
      'plantId': plantId,
      'plantName': plantName,
      'defaultPlantId': defaultPlantId,
      'defaultPlantName': defaultPlantName,
      'assignmentId': assignmentId,
      'assignmentPlantId': assignmentPlantId,
      'assignmentPlantName': assignmentPlantName,
      'assignmentVehicleId': assignmentVehicleId,
      'assignmentVehicleNumber': assignmentVehicleNumber,
      'salary': salary,
      'profilePhoto': profilePhoto,
      'aadhaar': aadhaar,
      'contactNumber': contactNumber,
      'esiNumber': esiNumber,
      'uanNumber': uanNumber,
      'ifscCode': ifscCode,
      'ifscVerified': ifscVerified,
      'bankAccount': bankAccount,
      'branchName': branchName,
      'fatherName': fatherName,
      'address': address,
      'dlNumber': dlNumber,
      'dlValidity': dlValidity,
      'dlIssueDate': dlIssueDate,
      'nomineeName': nomineeName,
      'nomineeRelation': nomineeRelation,
      'nomineeContact': nomineeContact,
      'vehicleNumber': vehicleNumber,
      'driverRole': driverRole,
      'availableVehicles': availableVehicles.map((v) => v.toJson()).toList(),
      'joiningDate': joiningDate?.toIso8601String(),
      'supervisorName': supervisorName,
      'supervisedPlants': supervisedPlants,
      'supervisedPlantIds': supervisedPlantIds,
      'canViewDocuments': canViewDocuments,
      'geofencingEnabled': geofencingEnabled,
      'proxyEnabled': proxyEnabled,
      'trainingRequired': trainingRequired,
      'advanceEntryAllowed': advanceEntryAllowed,
      'employeeRegEnabled': employeeRegEnabled,
    };
  }

  static AppUser fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      role: UserRole.values.firstWhere((e) => e.name == json['role']),
      username: json['username'] as String?,
      employeeId: json['employeeId'] as String?,
      driverId: json['driverId'] as String?,
      plantId: json['plantId'] as String?,
      plantName: json['plantName'] as String?,
      defaultPlantId: json['defaultPlantId'] as String?,
      defaultPlantName: json['defaultPlantName'] as String?,
      assignmentId: json['assignmentId'] as String?,
      assignmentPlantId: json['assignmentPlantId'] as String?,
      assignmentPlantName: json['assignmentPlantName'] as String?,
      assignmentVehicleId: json['assignmentVehicleId'] as String?,
      assignmentVehicleNumber: json['assignmentVehicleNumber'] as String?,
      salary: json['salary'] as String?,
      profilePhoto: json['profilePhoto'] as String?,
      aadhaar: json['aadhaar'] as String?,
      contactNumber:
          (json['contactNumber'] ?? json['contact'] ?? json['contact_number'])
              as String?,
      esiNumber: json['esiNumber'] as String?,
      uanNumber: json['uanNumber'] as String?,
      ifscCode: json['ifscCode'] as String?,
      ifscVerified: json['ifscVerified'] as bool?,
      bankAccount: json['bankAccount'] as String?,
      branchName: json['branchName'] as String?,
      fatherName: json['fatherName'] as String?,
      address: json['address'] as String?,
      dlNumber: (json['dlNumber'] ?? json['dl_number']) as String?,
      dlValidity:
          (json['dlValidity'] ??
                  json['dl_validity'] ??
                  json['license_expiry_date'])
              as String?,
      dlIssueDate: (json['dlIssueDate'] ?? json['dl_issue_date']) as String?,
      nomineeName: (json['nomineeName'] ?? json['nominee_name']) as String?,
      nomineeRelation:
          (json['nomineeRelation'] ?? json['relation_nominee']) as String?,
      nomineeContact:
          (json['nomineeContact'] ?? json['nominee_contact']) as String?,
      vehicleNumber: json['vehicleNumber'] as String?,
      driverRole: json['driverRole'] as String?,
      availableVehicles:
          (json['availableVehicles'] as List<dynamic>?)
              ?.map((v) => DriverVehicle.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      joiningDate: json['joiningDate'] != null
          ? DateTime.parse(json['joiningDate'] as String)
          : null,
      supervisorName: json['supervisorName'] as String?,
      supervisedPlants:
          (json['supervisedPlants'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [],
      supervisedPlantIds: json['supervisedPlantIds'] as List<dynamic>? ?? [],
      canViewDocuments: json['canViewDocuments'] == true,
      geofencingEnabled: _parseGeofenceFlag(
        json['geofencingEnabled'] ?? json['geofencing_enable'],
      ),
      proxyEnabled: _parseGeofenceFlag(
        json['proxyEnabled'] ?? json['proxy_enabled'],
      ),
      trainingRequired: _parseGeofenceFlag(
        json['trainingRequired'] ?? json['training_req'],
      ),
      advanceEntryAllowed: _parseGeofenceFlag(
        json['advanceEntryAllowed'] ?? json['advance_entry'],
      ),
      employeeRegEnabled: _parseGeofenceFlag(
        json['employeeRegEnabled'] ?? json['employee_reg'],
      ),
    );
  }

  static bool _parseGeofenceFlag(dynamic raw) {
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
}
