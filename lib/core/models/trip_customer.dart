class TripCustomer {
  const TripCustomer({
    required this.id,
    required this.customerName,
    required this.shortCode,
    required this.status,
    this.createdAt,
  });

  factory TripCustomer.fromJson(Map<String, dynamic> json) {
    final createdAtRaw =
        json['created_at']?.toString() ?? json['createdAt']?.toString();
    return TripCustomer(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      customerName:
          json['customer_name']?.toString() ??
          json['customerName']?.toString() ??
          json['name']?.toString() ??
          '',
      shortCode:
          json['short_code']?.toString() ??
          json['shortCode']?.toString() ??
          json['code']?.toString() ??
          '',
      status: json['status']?.toString() ?? 'Active',
      createdAt: createdAtRaw == null || createdAtRaw.isEmpty
          ? null
          : DateTime.tryParse(createdAtRaw),
    );
  }

  final int id;
  final String customerName;
  final String shortCode;
  final String status;
  final DateTime? createdAt;

  TripCustomer copyWith({
    int? id,
    String? customerName,
    String? shortCode,
    String? status,
    DateTime? createdAt,
  }) {
    return TripCustomer(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      shortCode: shortCode ?? this.shortCode,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
