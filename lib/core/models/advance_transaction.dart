class AdvanceTransaction {
  const AdvanceTransaction({
    required this.id,
    required this.driverId,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
    this.runningBalance,
    this.receiptPath,
  });

  factory AdvanceTransaction.fromJson(Map<String, dynamic> json) {
    return AdvanceTransaction(
      id: json['id']?.toString() ?? '',
      driverId:
          json['driver_id']?.toString() ?? json['driverId']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      description: json['description']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      runningBalance:
          double.tryParse(json['running_balance']?.toString() ?? '0') ?? 0.0,
      receiptPath: json['receipt_path']?.toString(),
    );
  }

  final String id;
  final String driverId;
  final String type;
  final double amount;
  final String description;
  final String createdAt;
  final double? runningBalance;
  final String? receiptPath;

  bool get isAdvanceReceived => type == 'advance_received';
  bool get isExpense => type == 'expense';

  String get formattedAmount {
    return '₹${amount.toStringAsFixed(0)}';
  }

  String get formattedBalance {
    if (runningBalance == null) return '';
    return '₹${runningBalance!.toStringAsFixed(0)}';
  }

  String get formattedDate {
    try {
      final date = DateTime.parse(createdAt);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final transactionDate = DateTime(date.year, date.month, date.day);

      if (transactionDate == today) {
        return '${_formatDay(date)} • Today';
      } else if (transactionDate == today.subtract(const Duration(days: 1))) {
        return '${_formatDay(date)} • Yesterday';
      } else {
        return _formatDay(date);
      }
    } catch (e) {
      return createdAt;
    }
  }

  String _formatDay(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year.toString().substring(2)}';
  }

  String get formattedTime {
    try {
      final date = DateTime.parse(createdAt);
      final hour = date.hour > 12 ? date.hour - 12 : date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '${hour == 0 ? 12 : hour}:$minute $period';
    } catch (e) {
      return '';
    }
  }
}
