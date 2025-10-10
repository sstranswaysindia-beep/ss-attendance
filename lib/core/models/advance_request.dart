class AdvanceRequest {
  const AdvanceRequest({
    required this.advanceRequestId,
    required this.amount,
    required this.purpose,
    required this.status,
    required this.requestedAt,
    this.approvalById,
    this.approvalAt,
    this.disbursedAt,
    this.remarks,
  });

  factory AdvanceRequest.fromJson(Map<String, dynamic> json) {
    return AdvanceRequest(
      advanceRequestId: json['advanceRequestId']?.toString() ?? json['id']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      purpose: json['purpose']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      requestedAt: json['requestedAt']?.toString() ?? '',
      approvalById: json['approvalById']?.toString(),
      approvalAt: json['approvalAt']?.toString(),
      disbursedAt: json['disbursedAt']?.toString(),
      remarks: json['remarks']?.toString(),
    );
  }

  final String advanceRequestId;
  final double amount;
  final String purpose;
  final String status;
  final String requestedAt;
  final String? approvalById;
  final String? approvalAt;
  final String? disbursedAt;
  final String? remarks;
}
