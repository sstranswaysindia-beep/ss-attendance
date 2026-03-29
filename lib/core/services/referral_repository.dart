import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/referral.dart';

/// Repository that handles all referral-related API calls.
class ReferralRepository {
  ReferralRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://sstranswaysindia.com/api/mobile';

  static ReferralUploadFile? fromBytes({
    required Uint8List bytes,
    required String filename,
  }) {
    if (bytes.isEmpty) {
      return null;
    }
    final safeName = filename.trim().isEmpty ? 'upload.jpg' : filename.trim();
    return ReferralUploadFile(filename: safeName, bytes: bytes);
  }

  // ── Get or generate referral code for logged-in user ──────────────────
  Future<String> fetchReferralCode({required String userId}) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_code.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    final payload = _decode(response);
    return payload['referral_code']?.toString() ?? '';
  }

  // ── Register new user with referral code ──────────────────────────────
  Future<Map<String, dynamic>> registerWithReferral({
    required String username,
    required String password,
    required String referralCode,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_register.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'referral_code': referralCode,
      }),
    );
    return _decode(response);
  }

  // ── Submit profile details (name, mobile, Aadhar, DL) ─────────────────
  Future<Map<String, dynamic>> submitProfile({
    required String userId,
    required String name,
    required String mobile,
    required String type, // 'driver' or 'helper'
    String? aadharNo,
    String? dlNo,
    ReferralUploadFile? aadharPhoto,
    ReferralUploadFile? dlPhoto,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/referral_profile_submit.php'),
    );

    request.fields['user_id'] = userId;
    request.fields['name'] = name;
    request.fields['mobile'] = mobile;
    request.fields['type'] = type;
    if (aadharNo != null) request.fields['aadhar_no'] = aadharNo;
    if (dlNo != null) request.fields['dl_no'] = dlNo;

    if (aadharPhoto != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'aadhar_photo',
          aadharPhoto.bytes,
          filename: aadharPhoto.filename,
        ),
      );
    }
    if (dlPhoto != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'dl_photo',
          dlPhoto.bytes,
          filename: dlPhoto.filename,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _decode(response);
  }

  // ── Fetch all referrals for a user (tracker) ──────────────────────────
  Future<List<Referral>> fetchReferrals({required String userId}) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_list.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );

    final payload = _decode(response);
    final list = payload['referrals'] as List<dynamic>? ?? [];
    return list
        .map((e) => Referral.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Fetch current referral user's profile submission status ────────────
  Future<Map<String, dynamic>> fetchMyProfileStatus({
    required String userId,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_profile_status.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    return _decode(response);
  }

  // ── Fetch UPI ID for a user ────────────────────────────────────────────
  Future<String> fetchUpiId({required String userId}) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_upi.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'action': 'get'}),
    );
    final payload = _decode(response);
    return payload['upi_id']?.toString() ?? '';
  }

  // ── Save UPI ID for a user ─────────────────────────────────────────────
  Future<void> saveUpiId({
    required String userId,
    required String upiId,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_upi.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'action': 'save',
        'upi_id': upiId,
      }),
    );
    _decode(response);
  }

  // ── Request withdrawal ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> requestWithdrawal({
    required String userId,
    required double amount,
    required String upiId,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/referral_withdraw.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'amount': amount,
        'upi_id': upiId,
      }),
    );
    return _decode(response);
  }

  // ── JSON decode helper ────────────────────────────────────────────────
  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Invalid server response (status: ${response.statusCode})',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'ok') {
      throw Exception(
        payload['error']?.toString() ??
            'Request failed (${response.statusCode})',
      );
    }

    return payload;
  }
}

class ReferralUploadFile {
  const ReferralUploadFile({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}
