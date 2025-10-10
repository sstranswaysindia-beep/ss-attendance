class SalaryCredit {
  const SalaryCredit({
    required this.salaryCreditId,
    required this.amount,
    required this.creditedOn,
    this.referenceNo,
    this.notes,
    this.createdAt,
  });

  factory SalaryCredit.fromJson(Map<String, dynamic> json) {
    return SalaryCredit(
      salaryCreditId: json['salaryCreditId']?.toString() ?? json['id']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      creditedOn: json['creditedOn']?.toString() ?? '',
      referenceNo: json['referenceNo']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  final String salaryCreditId;
  final double amount;
  final String creditedOn;
  final String? referenceNo;
  final String? notes;
  final String? createdAt;
}
