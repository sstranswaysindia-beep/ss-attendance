/// Status of a referral entry.
enum ReferralStatus { pending, verified, rejected }

/// Type of referral – driver or helper.
enum ReferralType { driver, helper }

/// Represents one referral record, either for tracking (referrer view)
/// or for profile completion (referred user view).
class Referral {
  Referral({
    required this.id,
    required this.referrerUserId,
    required this.referralCode,
    required this.referredName,
    required this.referredMobile,
    required this.referredType,
    required this.status,
    required this.amount,
    required this.createdAt,
    this.aadharNo,
    this.dlNo,
    this.aadharPhotoUrl,
    this.dlPhotoUrl,
    this.verifiedAt,
    this.referredUsername,
    this.referredPassword,
  });

  final String id;
  final String referrerUserId;
  final String referralCode;
  final String referredName;
  final String referredMobile;
  final ReferralType referredType;
  final ReferralStatus status;
  final double amount;
  final DateTime createdAt;
  final String? aadharNo;
  final String? dlNo;
  final String? aadharPhotoUrl;
  final String? dlPhotoUrl;
  final DateTime? verifiedAt;
  final String? referredUsername;
  final String? referredPassword;

  /// Parse JSON from server into a [Referral] instance.
  factory Referral.fromJson(Map<String, dynamic> json) {
    return Referral(
      id: json['id']?.toString() ?? '',
      referrerUserId: json['referrer_user_id']?.toString() ?? '',
      referralCode: json['referral_code']?.toString() ?? '',
      referredName: json['referred_name']?.toString() ?? '',
      referredMobile: json['referred_mobile']?.toString() ?? '',
      referredType: _parseType(json['referred_type']?.toString()),
      status: _parseStatus(json['status']?.toString()),
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      aadharNo: json['aadhar_no']?.toString(),
      dlNo: json['dl_no']?.toString(),
      aadharPhotoUrl: json['aadhar_photo_url']?.toString(),
      dlPhotoUrl: json['dl_photo_url']?.toString(),
      verifiedAt: json['verified_at'] != null
          ? DateTime.tryParse(json['verified_at'].toString())
          : null,
      referredUsername: json['referred_username']?.toString(),
      referredPassword: json['referred_password']?.toString(),
    );
  }

  static ReferralStatus _parseStatus(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'verified':
        return ReferralStatus.verified;
      case 'rejected':
        return ReferralStatus.rejected;
      default:
        return ReferralStatus.pending;
    }
  }

  static ReferralType _parseType(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'helper':
        return ReferralType.helper;
      default:
        return ReferralType.driver;
    }
  }

  String get statusLabel {
    switch (status) {
      case ReferralStatus.pending:
        return 'Pending';
      case ReferralStatus.verified:
        return 'Verified';
      case ReferralStatus.rejected:
        return 'Rejected';
    }
  }

  String get typeLabel {
    switch (referredType) {
      case ReferralType.driver:
        return 'Driver';
      case ReferralType.helper:
        return 'Helper';
    }
  }
}
