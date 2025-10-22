import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/document_models.dart';
import '../../core/services/documents_repository.dart';
import 'document_file_helper_stub.dart';

class _DirectoryCandidate {
  const _DirectoryCandidate(this.directory, {required this.isPublic});

  final Directory directory;
  final bool isPublic;
}

void _logDownload(
  String message, {
  Map<String, Object?>? details,
  Object? error,
  StackTrace? stackTrace,
}) {}

class DocumentFileHelper {
  static Future<DocumentDownloadResult?> download(
    DocumentRecord document,
    DocumentsRepository repository, {
    bool forceDownload = false,
  }) async {
    final uri = repository.bestDocumentUri(document);
    if (uri == null) {
      _logDownload(
        'Download aborted: missing URI',
        details: {
          'documentId': document.documentId,
          'documentName': document.name,
        },
      );
      return null;
    }

    _logDownload(
      'Download requested',
      details: {
        'documentId': document.documentId,
        'documentName': document.name,
        'uri': uri.toString(),
        'forceDownload': forceDownload,
      },
    );

    final candidateUris = _candidateDownloadUris(uri);
    http.Response? response;
    Uri? responseUri;
    for (final candidate in candidateUris) {
      _logDownload(
        'Attempting download candidate',
        details: {'uri': candidate.toString()},
      );
      final attempt = await http.get(candidate);
      if (attempt.statusCode != 200) {
        _logDownload(
          'Candidate rejected: HTTP ${attempt.statusCode}',
          details: {'uri': candidate.toString()},
        );
        continue;
      }
      if (_isHtmlResponse(attempt)) {
        _logDownload(
          'Candidate rejected: response is HTML',
          details: {
            'uri': candidate.toString(),
            'contentType': attempt.headers['content-type'] ?? '',
          },
        );
        continue;
      }
      response = attempt;
      responseUri = candidate;
      break;
    }

    if (response == null || responseUri == null) {
      _logDownload(
        'Download failed: no valid response',
        details: {
          'candidates': candidateUris.map((e) => e.toString()).toList(),
        },
      );
      return null;
    }

    final fileName = _resolveFileName(
      document: document,
      uri: responseUri,
      mimeType: response.headers['content-type'],
      contentDisposition: response.headers['content-disposition'],
    );

    final bytes = response.bodyBytes;
    final resolvedMime = _resolveMimeType(
      explicit: document.mimeType,
      header: response.headers['content-type'],
      fileName: fileName,
      bytes: bytes,
    );

    final attempted = <String>{};

    Future<String?> attemptWrite(Directory baseDir) async {
      if (attempted.contains(baseDir.path)) {
        return null;
      }
      attempted.add(baseDir.path);

      try {
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }

        final docsHubDir = Directory(p.join(baseDir.path, 'SSTranswaysIndia'));
        if (!await docsHubDir.exists()) {
          await docsHubDir.create(recursive: true);
        }

        final filePath = p.join(docsHubDir.path, fileName);
        final resultPath = await _writeFile(filePath, bytes, forceDownload);
        if (resultPath != null) {
          _logDownload(
            'File written',
            details: {
              'path': resultPath,
              'directory': docsHubDir.path,
              'strategy': 'SSTranswaysIndia',
            },
          );
        }
        return resultPath;
      } catch (error, stackTrace) {
        _logDownload(
          'Write attempt failed',
          details: {'directory': baseDir.path},
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }

    final candidateDirs = await _candidateDirectories(
      forceDownload: forceDownload,
    );
    for (final candidate in candidateDirs) {
      final path = await attemptWrite(candidate.directory);
      if (path != null) {
        _logDownload(
          candidate.isPublic
              ? 'Download saved to public storage'
              : 'Download saved to app-specific external storage',
          details: {'path': path},
        );
        return DocumentDownloadResult(
          path: path,
          mimeType: resolvedMime,
          fileName: p.basename(path),
          isPublic: candidate.isPublic,
        );
      }
    }

    final fallback = await getApplicationDocumentsDirectory();
    final fallbackPath = await attemptWrite(fallback);
    if (fallbackPath == null) {
      _logDownload('Unable to persist document in any directory');
      return null;
    }

    _logDownload(
      'Download saved to app documents directory',
      details: {'path': fallbackPath},
    );

    return DocumentDownloadResult(
      path: fallbackPath,
      mimeType: resolvedMime,
      fileName: p.basename(fallbackPath),
      isPublic: false,
    );
  }

  static Future<List<_DirectoryCandidate>> _candidateDirectories({
    required bool forceDownload,
  }) async {
    if (!Platform.isAndroid) {
      return const <_DirectoryCandidate>[];
    }

    final seen = <String>{};
    final appSpecific = <_DirectoryCandidate>[];
    void addCandidate(
      List<_DirectoryCandidate> target,
      Directory? directory, {
      required bool isPublic,
    }) {
      if (directory == null) {
        return;
      }
      final normalized = p.normalize(directory.path);
      if (normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      target.add(_DirectoryCandidate(directory, isPublic: isPublic));
    }

    final appSpecificRoot = await getExternalStorageDirectory();
    addCandidate(appSpecific, appSpecificRoot, isPublic: false);

    final appSpecificDownloads = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );
    if (appSpecificDownloads != null) {
      for (final directory in appSpecificDownloads) {
        addCandidate(appSpecific, directory, isPublic: false);
      }
    }

    if (appSpecificRoot != null) {
      final siblingDownload = Directory(
        p.join(appSpecificRoot.path, 'Download'),
      );
      addCandidate(appSpecific, siblingDownload, isPublic: false);
    }

    return [...appSpecific];
  }

  static Future<String?> _writeFile(
    String path,
    List<int> bytes,
    bool forceDownload,
  ) async {
    final file = File(path);
    if (!forceDownload && await file.exists()) {
      return file.path;
    }

    try {
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (error, stackTrace) {
      _logDownload(
        'Write failed',
        details: {'path': path},
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static String _resolveFileName({
    required DocumentRecord document,
    required Uri uri,
    String? mimeType,
    String? contentDisposition,
  }) {
    final candidates = <String?>[
      _filenameFromContentDisposition(contentDisposition),
      document.fileName,
      document.filePath != null ? p.basename(document.filePath!) : null,
      document.name,
      uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null,
    ];

    final sanitized = candidates
        .whereType<String>()
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => name.replaceAll(RegExp(r'[\\/:"*?<>|]'), '_'))
        .toList();

    for (final candidate in sanitized) {
      if (p.extension(candidate).isNotEmpty) {
        return candidate;
      }
    }

    String baseName = sanitized.isNotEmpty ? sanitized.first : '';
    if (baseName.isEmpty) {
      baseName = 'document_${document.documentId}';
    }

    final ext =
        _extensionFromNameList(sanitized) ??
        _extensionFromMime(mimeType) ??
        _extensionFromDocType(document.type) ??
        'pdf';

    if (p.extension(baseName).isEmpty) {
      final cleanExt = ext.replaceAll('.', '');
      return '$baseName.$cleanExt';
    }

    return baseName;
  }

  static List<Uri> _candidateDownloadUris(Uri uri) {
    final candidates = <Uri>[];
    final seen = <String>{};

    void add(Uri candidate) {
      final key = candidate.toString();
      if (seen.add(key)) {
        candidates.add(candidate);
      }
    }

    add(uri);

    final driveDownload = _resolveGoogleDriveDownloadUri(uri);
    if (driveDownload != null) {
      add(driveDownload);
    }

    return candidates;
  }

  static Uri? _resolveGoogleDriveDownloadUri(Uri uri) {
    if (!uri.host.contains('drive.google.com')) {
      return null;
    }

    String? fileId;

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 3 && segments[0] == 'file' && segments[1] == 'd') {
      fileId = segments[2];
    }

    fileId ??= uri.queryParameters['id'];

    if (fileId == null || fileId.isEmpty) {
      return null;
    }

    return Uri.https('drive.google.com', '/uc', {
      'export': 'download',
      'id': fileId,
    });
  }

  static bool _isHtmlResponse(http.Response response) {
    final rawType = response.headers['content-type']?.toLowerCase() ?? '';
    if (rawType.contains('text/html')) {
      return true;
    }

    if (rawType.contains('text/plain')) {
      final prefix = _responsePrefix(response).trimLeft().toLowerCase();
      if (prefix.startsWith('<!doctype') || prefix.startsWith('<html')) {
        return true;
      }
    }

    if (rawType.isEmpty) {
      final prefix = _responsePrefix(response).trimLeft().toLowerCase();
      if (prefix.startsWith('<!doctype') || prefix.startsWith('<html')) {
        return true;
      }
    }

    return false;
  }

  static String _responsePrefix(http.Response response, {int maxLength = 128}) {
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      return '';
    }
    final length = bytes.length < maxLength ? bytes.length : maxLength;
    return String.fromCharCodes(bytes.sublist(0, length));
  }

  static String _resolveMimeType({
    String? explicit,
    String? header,
    required String fileName,
    required List<int> bytes,
  }) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit;
    }

    if (header != null &&
        header.isNotEmpty &&
        header.toLowerCase() != 'application/octet-stream') {
      return header;
    }

    final fromName = mime.lookupMimeType(fileName);
    if (fromName != null) {
      return fromName;
    }

    final fromBytes = mime.lookupMimeType('', headerBytes: bytes);
    if (fromBytes != null) {
      return fromBytes;
    }

    return 'application/octet-stream';
  }

  static String? _extensionFromMime(String? mimeValue) {
    if (mimeValue == null || mimeValue.isEmpty) {
      return null;
    }

    switch (mimeValue.toLowerCase()) {
      case 'application/pdf':
        return 'pdf';
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'application/msword':
        return 'doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return 'docx';
      case 'application/vnd.ms-excel':
        return 'xls';
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return 'xlsx';
      case 'application/vnd.ms-powerpoint':
        return 'ppt';
      case 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        return 'pptx';
      case 'text/plain':
        return 'txt';
    }

    if (mimeValue.startsWith('image/') ||
        mimeValue.startsWith('video/') ||
        mimeValue.startsWith('audio/')) {
      final parts = mimeValue.split('/');
      if (parts.length == 2 && parts[1].isNotEmpty) {
        return parts[1];
      }
    }

    final parsed = mimeValue.split('/');
    if (parsed.length == 2 && parsed[1].isNotEmpty) {
      return parsed[1];
    }

    return null;
  }

  static String? _extensionFromNameList(List<String> names) {
    for (final name in names) {
      final ext = p.extension(name);
      if (ext.isNotEmpty) {
        return ext.replaceFirst('.', '');
      }
    }
    return null;
  }

  static String? _extensionFromDocType(String? docType) {
    if (docType == null || docType.isEmpty) {
      return null;
    }

    final lower = docType.toLowerCase().trim();

    const known = <String, String>{
      'pdf': 'pdf',
      'jpg': 'jpg',
      'jpeg': 'jpg',
      'png': 'png',
      'gif': 'gif',
      'webp': 'webp',
      'image': 'jpg',
      'photo': 'jpg',
      'picture': 'jpg',
      'doc': 'doc',
      'docx': 'docx',
      'xls': 'xls',
      'xlsx': 'xlsx',
      'license': 'pdf',
      'insurance': 'pdf',
      'document': 'pdf',
      'aadhar': 'pdf',
      'aadhaar': 'pdf',
      'pan': 'pdf',
      'fire extinguisher': 'pdf',
      'fitness': 'pdf',
      'insurance policy': 'pdf',
    };

    if (known.containsKey(lower)) {
      return known[lower];
    }

    if (lower.contains('.')) {
      final part = lower.split('.').last.trim();
      return part.isNotEmpty ? part : null;
    }

    if (lower.contains(' ') || lower.length > 5) {
      return null;
    }

    return lower.isNotEmpty ? lower : null;
  }

  static String? _filenameFromContentDisposition(String? header) {
    if (header == null || header.isEmpty) {
      return null;
    }

    final parts = header.split(';');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.toLowerCase().startsWith('filename*=')) {
        final value = trimmed.substring(9);
        final segments = value.split("''");
        final encodedName = segments.length == 2 ? segments[1] : segments.last;
        return Uri.decodeFull(encodedName);
      }
      if (trimmed.toLowerCase().startsWith('filename=')) {
        var value = trimmed.substring(9).trim();
        if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
          value = value.substring(1, value.length - 1);
        }
        return value;
      }
    }

    return null;
  }
}
