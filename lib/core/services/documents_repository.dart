import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/document_models.dart';

class DocumentFailure implements Exception {
  DocumentFailure(this.message);

  final String message;

  @override
  String toString() => 'DocumentFailure: $message';
}

class DocumentsRepository {
  DocumentsRepository({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        _baseUri = baseUri ?? Uri.parse(_defaultBaseUrl),
        _originUri = _originFrom(baseUri ?? Uri.parse(_defaultBaseUrl));

  static const String _defaultBaseUrl =
      'https://sstranswaysindia.com/api/mobile/';

  final http.Client _client;
  final Uri _baseUri;
  final Uri _originUri;

  Future<DocumentOverviewData> fetchOverview({
    required String userId,
  }) async {
    try {
      final uri = _baseUri.resolve('documents_overview.php').replace(
        queryParameters: {
          'userId': userId,
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        throw DocumentFailure(
          'Unable to load documents overview (${response.statusCode}).',
        );
      }

      final payload =
          jsonDecode(response.body) as Map<String, dynamic>? ?? const {};
      if (payload['status'] != 'ok') {
        throw DocumentFailure(
          payload['error']?.toString() ?? 'Unexpected response from server.',
        );
      }

      return DocumentOverviewData.fromJson(payload);
    } catch (error) {
      if (error is DocumentFailure) {
        rethrow;
      }
      throw DocumentFailure('Failed to load documents overview.');
    }
  }

  Uri? bestDocumentUri(DocumentRecord document) {
    final driveLink = document.googleDriveLink?.trim();
    if (driveLink != null && driveLink.isNotEmpty) {
      final driveUri = Uri.tryParse(driveLink);
      if (driveUri != null) {
        return driveUri;
      }
    }

    final filePath = document.filePath?.trim() ?? '';
    final fileName = document.fileName?.trim() ?? '';
    final fallback = filePath.isNotEmpty ? filePath : fileName;
    if (fallback.isEmpty) {
      return null;
    }

    if (fallback.startsWith('http://') || fallback.startsWith('https://')) {
      return Uri.tryParse(fallback);
    }

    final normalized = fallback.startsWith('/')
        ? fallback.substring(1)
        : fallback;
    return _originUri.resolve(normalized);
  }

  static Uri _originFrom(Uri uri) => Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      );
}
