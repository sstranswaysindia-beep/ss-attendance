import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ProfileFailure implements Exception {
  ProfileFailure(this.message);

  final String message;

  @override
  String toString() => 'ProfileFailure: $message';
}

class ProfileRepository {
  ProfileRepository({
    http.Client? client,
    Uri? uploadEndpoint,
  })  : _client = client ?? http.Client(),
        _uploadEndpoint =
            uploadEndpoint ?? Uri.parse(_defaultUploadEndpoint);

  static const String _defaultUploadEndpoint =
      'https://sstranswaysindia.com/api/mobile/profile_photo_upload.php';

  final http.Client _client;
  final Uri _uploadEndpoint;

  Future<String> uploadProfilePhoto({
    required String driverId,
    required File file,
  }) async {
    final request = http.MultipartRequest('POST', _uploadEndpoint)
      ..fields['driverId'] = driverId
      ..files.add(await http.MultipartFile.fromPath('photo', file.path));

    final response = await http.Response.fromStream(await request.send());

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ProfileFailure(
        'Invalid response from server (status: ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 300 || payload['status'] != 'ok') {
      throw ProfileFailure(
        payload['error']?.toString() ?? 'Unable to upload profile photo.',
      );
    }

    final url = payload['photoUrl']?.toString();
    if (url == null || url.isEmpty) {
      throw ProfileFailure('Server did not return the uploaded photo URL.');
    }
    return url;
  }
}
