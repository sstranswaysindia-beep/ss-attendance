class AdminDriver {
  const AdminDriver({
    required this.id,
    required this.empId,
    required this.name,
    required this.role,
    required this.status,
    required this.plantName,
    this.contact,
    this.dlNumber,
    this.dlValidity,
    this.joiningDate,
    this.profilePhoto,
    this.plantId,
  });

  final int id;
  final String empId;
  final String name;
  final String role;
  final String status;
  final String plantName;
  final String? contact;
  final String? dlNumber;
  final DateTime? dlValidity;
  final DateTime? joiningDate;
  final String? profilePhoto;
  final int? plantId;

  factory AdminDriver.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      final raw = value?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return AdminDriver(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      empId: json['empId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      plantName: json['plantName']?.toString() ?? '',
      contact: json['contact']?.toString(),
      dlNumber: json['dlNumber']?.toString(),
      dlValidity: parseDate(json['dlValidity']),
      joiningDate: parseDate(json['joiningDate']),
      profilePhoto: json['profilePhoto']?.toString(),
      plantId: int.tryParse(json['plantId']?.toString() ?? ''),
    );
  }

  bool get hasProfilePhoto {
    if ((profilePhoto ?? '').isEmpty) return false;
    final uri = Uri.tryParse(profilePhoto!);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  String get initials {
    final segments = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (segments.length >= 2) {
      return (segments[0][0] + segments[1][0]).toUpperCase();
    }
    if (segments.length == 1 && segments.first.isNotEmpty) {
      final word = segments.first;
      return word.length >= 2
          ? (word.substring(0, 2)).toUpperCase()
          : word.substring(0, 1).toUpperCase();
    }
    return 'DR';
  }

  String get displayRole {
    if (role.isEmpty) return 'Driver';
    final normalized = role.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return 'Driver';
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              part.substring(0, 1).toUpperCase() + part.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  bool get isActive => status.toLowerCase() == 'active';
}
