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
  final List<DriverVehicle> availableVehicles;
  final DateTime? joiningDate;
  final String? supervisorName;
  final List<Map<String, dynamic>> supervisedPlants;
  final List<dynamic> supervisedPlantIds;
}
