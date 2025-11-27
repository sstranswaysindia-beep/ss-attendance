class AdminGeofencingPlant {
  const AdminGeofencingPlant({required this.id, required this.name});

  final int id;
  final String name;

  factory AdminGeofencingPlant.fromJson(Map<String, dynamic> json) {
    return AdminGeofencingPlant(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? json['plantName'] ?? '').toString(),
    );
  }
}

class AdminGeofencingUser {
  const AdminGeofencingUser({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.username,
    required this.geofencingEnabled,
    this.contact,
    this.employeeId,
    this.lastLogin,
    this.plants = const <AdminGeofencingPlant>[],
  });

  final int userId;
  final String fullName;
  final String role;
  final String username;
  final bool geofencingEnabled;
  final String? contact;
  final String? employeeId;
  final DateTime? lastLogin;
  final List<AdminGeofencingPlant> plants;

  AdminGeofencingUser copyWith({
    bool? geofencingEnabled,
  }) {
    return AdminGeofencingUser(
      userId: userId,
      fullName: fullName,
      role: role,
      username: username,
      geofencingEnabled: geofencingEnabled ?? this.geofencingEnabled,
      contact: contact,
      employeeId: employeeId,
      lastLogin: lastLogin,
      plants: plants,
    );
  }

  factory AdminGeofencingUser.fromJson(Map<String, dynamic> json) {
    final rawPlants = (json['plants'] as List<dynamic>?) ?? const [];
    return AdminGeofencingUser(
      userId: json['userId'] is int
          ? json['userId'] as int
          : int.tryParse('${json['userId']}') ?? 0,
      fullName: (json['fullName'] ?? json['name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      contact: (json['contact'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['contact'] as String?)?.trim(),
      employeeId: (json['employeeId'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['employeeId'] as String?)?.trim(),
      geofencingEnabled: _parseFlag(json['geofencingEnabled']),
      lastLogin: _parseDateTime(json['lastLoginAt'] ?? json['lastLogin']),
      plants: rawPlants
          .map((e) => AdminGeofencingPlant.fromJson(
              (e as Map<String, dynamic>?) ?? const <String, dynamic>{}))
          .toList(growable: false),
    );
  }
}

class AdminGeofencingPayload {
  const AdminGeofencingPayload({
    required this.users,
    required this.plants,
  });

  final List<AdminGeofencingUser> users;
  final List<AdminGeofencingPlant> plants;

  factory AdminGeofencingPayload.fromJson(Map<String, dynamic> json) {
    final usersJson = (json['users'] as List<dynamic>?) ?? const [];
    final plantsJson = (json['plants'] as List<dynamic>?) ?? const [];
    return AdminGeofencingPayload(
      users: usersJson
          .map((e) => AdminGeofencingUser.fromJson(
              (e as Map<String, dynamic>?) ?? const <String, dynamic>{}))
          .toList(growable: false),
      plants: plantsJson
          .map((e) => AdminGeofencingPlant.fromJson(
              (e as Map<String, dynamic>?) ?? const <String, dynamic>{}))
          .where((plant) => plant.id != 0)
          .toList(growable: false),
    );
  }
}

bool _parseFlag(dynamic value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  final normalized = value.toString().toLowerCase().trim();
  return normalized == 'y' ||
      normalized == 'yes' ||
      normalized == 'true' ||
      normalized == '1' ||
      normalized == 'enabled';
}

DateTime? _parseDateTime(dynamic raw) {
  if (raw == null) {
    return null;
  }
  final value = raw.toString().trim();
  if (value.isEmpty || value == '0000-00-00 00:00:00') {
    return null;
  }
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}
