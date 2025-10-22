import '../../core/models/document_models.dart';
import '../../core/services/documents_repository.dart';

class DocumentDownloadResult {
  const DocumentDownloadResult({
    required this.path,
    required this.mimeType,
    required this.fileName,
    required this.isPublic,
  });

  final String path;
  final String mimeType;
  final String fileName;
  final bool isPublic;
}

abstract class DocumentFileHelper {
  static Future<DocumentDownloadResult?> download(
    DocumentRecord document,
    DocumentsRepository repository, {
    bool forceDownload = false,
  }) async =>
      null;
}
