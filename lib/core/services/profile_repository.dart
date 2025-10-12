import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class ProfileFailure implements Exception {
  ProfileFailure(this.message);

  final String message;

  @override
  String toString() => 'ProfileFailure: $message';
}

class ProfileRepository {
  ProfileRepository({http.Client? client, Uri? uploadEndpoint})
    : _client = client ?? http.Client(),
      _uploadEndpoint = uploadEndpoint ?? Uri.parse(_defaultUploadEndpoint);

  static const String _defaultUploadEndpoint =
      'https://sstranswaysindia.com/api/mobile/profile_photo_upload.php';
  static const String _userUploadEndpoint =
      'https://sstranswaysindia.com/api/mobile/user_profile_photo_upload.php';

  final http.Client _client;
  final Uri _uploadEndpoint;

  Future<String> uploadProfilePhoto({
    required String driverId,
    required File file,
  }) async {
    // Compress the image before uploading
    final compressedFile = await _compressImage(file);

    final request = http.MultipartRequest('POST', _uploadEndpoint)
      ..fields['driverId'] = driverId
      ..files.add(
        await http.MultipartFile.fromPath('photo', compressedFile.path),
      );

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

    // Clean up the temporary compressed file
    try {
      await compressedFile.delete();
    } catch (_) {
      // Ignore cleanup errors
    }

    return url;
  }

  /// Upload profile photo for supervisors without driver_id (using user ID)
  Future<String> uploadUserProfilePhoto({
    required String userId,
    required File file,
  }) async {
    // Compress the image before uploading
    final compressedFile = await _compressImage(file);

    final request =
        http.MultipartRequest('POST', Uri.parse(_userUploadEndpoint))
          ..fields['userId'] = userId
          ..files.add(
            await http.MultipartFile.fromPath('photo', compressedFile.path),
          );

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

    // Clean up the temporary compressed file
    try {
      await compressedFile.delete();
    } catch (_) {
      // Ignore cleanup errors
    }

    return url;
  }

  Future<File> _compressImage(File file) async {
    try {
      // Read the image file
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw ProfileFailure('Unable to decode image');
      }

      // Resize image to maximum 800x800 while maintaining aspect ratio
      final resizedImage = img.copyResize(
        image,
        width: image.width > image.height ? 800 : null,
        height: image.height > image.width ? 800 : null,
        maintainAspect: true,
      );

      // Encode as JPEG with 85% quality
      final compressedBytes = img.encodeJpg(resizedImage, quality: 85);

      // Create a temporary file for the compressed image
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/compressed_profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(compressedBytes);

      return tempFile;
    } catch (e) {
      throw ProfileFailure('Failed to compress image: $e');
    }
  }
}
