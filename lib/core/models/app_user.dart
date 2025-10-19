import 'driver_vehicle.dart';

enum UserRole { admin, supervisor, driver }

class AppUser {
  AppUser({
    required this.id,
    required this.displayName,
    required this.role,
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
    this.esiNumber,
    this.uanNumber,
    this.ifscCode,
    this.ifscVerified,
    this.bankAccount,
    this.branchName,
    this.fatherName,
    this.address,
    this.vehicleNumber,
    this.driverRole,
    this.availableVehicles = const <DriverVehicle>[],
    this.joiningDate,
    this.supervisorName,
    this.supervisedPlants = const <Map<String, dynamic>>[],
    this.supervisedPlantIds = const <dynamic>[],
  });

  final String id;
  final String displayName;
  final UserRole role;
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
  final String? esiNumber;
  final String? uanNumber;
  final String? ifscCode;
  final bool? ifscVerified;
  final String? bankAccount;
  final String? branchName;
  final String? fatherName;
  final String? address;
  final String? vehicleNumber;
  final String? driverRole;
  final List<DriverVehicle> availableVehicles;
  final DateTime? joiningDate;
  final String? supervisorName;
  final List<Map<String, dynamic>> supervisedPlants;
  final List<dynamic> supervisedPlantIds;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'role': role.name,
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
      'esiNumber': esiNumber,
      'uanNumber': uanNumber,
      'ifscCode': ifscCode,
      'ifscVerified': ifscVerified,
      'bankAccount': bankAccount,
      'branchName': branchName,
      'fatherName': fatherName,
      'address': address,
      'vehicleNumber': vehicleNumber,
      'driverRole': driverRole,
      'availableVehicles': availableVehicles.map((v) => v.toJson()).toList(),
      'joiningDate': joiningDate?.toIso8601String(),
      'supervisorName': supervisorName,
      'supervisedPlants': supervisedPlants,
      'supervisedPlantIds': supervisedPlantIds,
    };
  }

  static AppUser fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      role: UserRole.values.firstWhere((e) => e.name == json['role']),
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
      esiNumber: json['esiNumber'] as String?,
      uanNumber: json['uanNumber'] as String?,
      ifscCode: json['ifscCode'] as String?,
      ifscVerified: json['ifscVerified'] as bool?,
      bankAccount: json['bankAccount'] as String?,
      branchName: json['branchName'] as String?,
      fatherName: json['fatherName'] as String?,
      address: json['address'] as String?,
      vehicleNumber: json['vehicleNumber'] as String?,
      driverRole: json['driverRole'] as String?,
      availableVehicles: (json['availableVehicles'] as List<dynamic>?)
          ?.map((v) => DriverVehicle.fromJson(v as Map<String, dynamic>))
          .toList() ?? [],
      joiningDate: json['joiningDate'] != null 
          ? DateTime.parse(json['joiningDate'] as String) 
          : null,
      supervisorName: json['supervisorName'] as String?,
      supervisedPlants: (json['supervisedPlants'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ?? [],
      supervisedPlantIds: json['supervisedPlantIds'] as List<dynamic>? ?? [],
    );
  }
}
