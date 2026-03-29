import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/app_user.dart';
import '../../core/models/document_models.dart';
import '../../core/services/documents_repository.dart';
import '../../core/widgets/app_toast.dart';
import 'document_preview_screen.dart';
import 'document_file_helper_stub.dart'
    if (dart.library.io) 'document_file_helper_io.dart'
    as doc_helper;

const Color _adminPrimaryColor = Color(0xFF00296B);

Future<void> showPersonalDocumentsSheet(BuildContext context, AppUser user) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PersonalDocumentsSheet(user: user);
    },
  );
}

class _PersonalDocumentsSheet extends StatefulWidget {
  const _PersonalDocumentsSheet({required this.user});

  final AppUser user;

  @override
  State<_PersonalDocumentsSheet> createState() =>
      _PersonalDocumentsSheetState();
}

class _PersonalDocumentsSheetState extends State<_PersonalDocumentsSheet> {
  static const String _listUrl =
      'https://sstranswaysindia.com/api/mobile/driver_documents_list.php';
  final DateFormat _dateFormat = DateFormat('dd-MM-yyyy');
  final DocumentsRepository _documentsRepository = DocumentsRepository();
  bool _canPreviewInline = false;

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _documents = const [];
  List<String> _documentTypes = const [];
  Map<String, String> _typeLabels = const {};
  String? _selectedType;
  Map<String, dynamic>? _selectedDoc;
  WebViewController? _previewController;
  double _previewProgress = 0;
  String? _previewError;
  String? _previewUrl;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _canPreviewInline = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    _loadDocuments();
  }

  int? _resolveDriverId() {
    final driverId = (widget.user.driverId ?? '').trim();
    final userId = widget.user.id.trim();
    return int.tryParse(driverId) ?? int.tryParse(userId);
  }

  Future<void> _loadDocuments() async {
    final driverId = _resolveDriverId();
    if (driverId == null) {
      setState(() {
        _error = 'Driver ID is missing.';
        _documents = const [];
        _selectedDoc = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse(_listUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId}),
      );
      final body = utf8.decode(response.bodyBytes);
      Map<String, dynamic> data;
      try {
        data = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = 'Invalid response from server.';
          _documents = const [];
          _documentTypes = const [];
          _selectedType = null;
          _selectedDoc = null;
          _resetPreview();
        });
        return;
      }
      if (response.statusCode == 200 && data['status'] == 'ok') {
        final docs = (data['documents'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .where((doc) {
              final name = (doc['document_name'] ?? '').toString().toLowerCase();
              return !name.contains('reason: not applicable');
            })
            .toList(growable: false);
        if (!mounted) return;
        setState(() {
          _documents = docs;
          _documentTypes = _buildDocumentTypes(docs);
          _typeLabels = _buildTypeLabels(_documentTypes);
          _selectedType =
              _documentTypes.isNotEmpty ? _documentTypes.first : null;
          _selectedDoc = _firstDocForType(_selectedType);
          _loadPreviewForDoc(_selectedDoc);
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error =
              data['error']?.toString() ?? 'Unable to load documents.';
          _documents = const [];
          _documentTypes = const [];
          _typeLabels = const {};
          _selectedType = null;
          _selectedDoc = null;
          _resetPreview();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load documents. ${e.toString()}';
        _documents = const [];
        _documentTypes = const [];
        _typeLabels = const {};
        _selectedType = null;
        _selectedDoc = null;
        _resetPreview();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return _dateFormat.format(parsed);
  }

  List<String> _buildDocumentTypes(List<Map<String, dynamic>> docs) {
    final seen = <String>{};
    final types = <String>[];
    for (final doc in docs) {
      final type = (doc['document_type'] ?? '').toString();
      if (type.isEmpty || seen.contains(type)) continue;
      seen.add(type);
      types.add(type);
    }
    return types;
  }

  Map<String, String> _buildTypeLabels(List<String> types) {
    final labels = <String, String>{};
    for (final type in types) {
      labels[type] = _toTitleCase(type);
    }
    return labels;
  }

  String _toTitleCase(String value) {
    final cleaned = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return value;
    return cleaned
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) return part;
          final lower = part.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  Map<String, dynamic>? _firstDocForType(String? type) {
    if (type == null) return null;
    return _documents.firstWhere(
      (doc) => (doc['document_type'] ?? '').toString() == type,
      orElse: () => {},
    );
  }

  List<Map<String, dynamic>> _docsForType(String? type) {
    if (type == null) return const [];
    return _documents
        .where(
          (doc) => (doc['document_type'] ?? '').toString() == type,
        )
        .toList(growable: false);
  }

  int _uniqueDocNameCount(String? type) {
    final docs = _docsForType(type);
    if (docs.isEmpty) return 0;
    final names = <String>{};
    for (final doc in docs) {
      final name = (doc['document_name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    return names.length;
  }

  String _docTypeLabel(Map<String, dynamic> doc) {
    final type = (doc['document_type'] ?? '').toString();
    if (type.isEmpty) return 'Document';
    return _typeLabels[type] ?? _toTitleCase(type);
  }

  void _resetPreview() {
    _previewController = null;
    _previewProgress = 0;
    _previewError = null;
    _previewUrl = null;
  }

  bool _isPdfDoc(Map<String, dynamic> doc) {
    final mime = (doc['mime_type'] ?? '').toString().toLowerCase();
    if (mime.contains('pdf')) return true;
    final filePath = (doc['file_path'] ?? '').toString().toLowerCase();
    final localPath = (doc['local_path'] ?? '').toString().toLowerCase();
    return filePath.endsWith('.pdf') || localPath.endsWith('.pdf');
  }

  String? _resolvePreviewUrl(Map<String, dynamic> doc) {
    final url = _resolveDocUrl(doc);
    if (url == null) return null;
    if (!_isPdfDoc(doc)) return url;
    final encoded = Uri.encodeComponent(url);
    return 'https://docs.google.com/gview?embedded=1&url=$encoded';
  }

  void _loadPreviewForDoc(Map<String, dynamic>? doc) {
    if (doc == null) {
      _resetPreview();
      return;
    }
    final url = _resolvePreviewUrl(doc);
    if (url == null) {
      setState(() {
        _previewError = 'Document link not available.';
        _previewController = null;
        _previewUrl = null;
      });
      return;
    }
    if (!_canPreviewInline) {
      setState(() {
        _previewError = kIsWeb ? null : 'Inline preview not supported on this device.';
        _previewController = null;
        _previewUrl = url;
      });
      return;
    }

    _previewUrl = url;
    _previewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _previewProgress = progress / 100);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _previewError = null;
              _previewProgress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _previewProgress = 1);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() => _previewError = error.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  String? _resolveDocUrl(Map<String, dynamic> doc) {
    final localPath = (doc['local_path'] ?? '').toString().trim();
    if (localPath.isNotEmpty) {
      if (localPath.startsWith('http://') ||
          localPath.startsWith('https://')) {
        return localPath;
      }
      final normalized = localPath.startsWith('/')
          ? localPath.substring(1)
          : localPath;
      return 'https://sstranswaysindia.com/$normalized';
    }

    final drive = (doc['google_drive_link'] ?? '').toString().trim();
    if (drive.isNotEmpty) return drive;

    final filePath = (doc['file_path'] ?? '').toString().trim();
    if (filePath.isEmpty) return null;

    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    if (filePath.startsWith('/')) {
      return 'https://sstranswaysindia.com$filePath';
    }
    if (!filePath.contains('/')) {
      return 'https://sstranswaysindia.com/DriverDocs/uploads/$filePath';
    }
    return 'https://sstranswaysindia.com/$filePath';
  }

  bool _isImageDoc(Map<String, dynamic> doc) {
    final mime = (doc['mime_type'] ?? '').toString().toLowerCase();
    if (mime.startsWith('image/')) return true;
    final filePath = (doc['file_path'] ?? '').toString().toLowerCase();
    final localPath = (doc['local_path'] ?? '').toString().toLowerCase();
    return filePath.endsWith('.png') ||
        filePath.endsWith('.jpg') ||
        filePath.endsWith('.jpeg') ||
        filePath.endsWith('.gif') ||
        localPath.endsWith('.png') ||
        localPath.endsWith('.jpg') ||
        localPath.endsWith('.jpeg') ||
        localPath.endsWith('.gif');
  }

  DocumentRecord _toDocumentRecord(Map<String, dynamic> doc) {
    final docId = int.tryParse((doc['id'] ?? '').toString()) ?? 0;
    final name = (doc['document_name'] ?? '').toString();
    final type = (doc['document_type'] ?? '').toString();
    final localPath = (doc['local_path'] ?? '').toString();
    final filePath = localPath.isNotEmpty
        ? localPath
        : (doc['file_path'] ?? '').toString();
    final driveLink = (doc['google_drive_link'] ?? '').toString();
    final mimeType = (doc['mime_type'] ?? '').toString();

    return DocumentRecord(
      documentId: docId,
      name: name.isEmpty ? type : name,
      type: type,
      status: DocumentStatus.active,
      statusLabel: documentStatusLabel(DocumentStatus.active),
      googleDriveLink: driveLink.isEmpty ? null : driveLink,
      filePath: filePath.isEmpty ? null : filePath,
      fileName: filePath.isEmpty ? null : filePath,
      mimeType: mimeType.isEmpty ? null : mimeType,
    );
  }

  Future<void> _openDocument({required bool isDownload}) async {
    final doc = _selectedDoc;
    if (doc == null) {
      showAppToast(context, 'Select a document first.', isError: true);
      return;
    }
    final url = _resolvePreviewUrl(doc);
    if (url == null) {
      showAppToast(context, 'Document link not available.', isError: true);
      return;
    }
    if (!isDownload) {
      if (!_canPreviewInline) {
        showAppToast(
          context,
          'Preview not supported on this device.',
          isError: true,
        );
        return;
      }
      if (_previewUrl == null || _previewUrl!.isEmpty) {
        showAppToast(
          context,
          'Preview link not available.',
          isError: true,
        );
        return;
      }
      if (_isImageDoc(doc)) {
        final imageUrl = _resolveDocUrl(doc);
        if (imageUrl == null) {
          showAppToast(
            context,
            'Preview link not available.',
            isError: true,
          );
          return;
        }
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => _ImagePreviewScreen(
              title: _docTypeLabel(doc),
              imageUrl: imageUrl,
            ),
          ),
        );
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            title: _docTypeLabel(doc),
            initialUri: Uri.parse(url),
          ),
        ),
      );
      return;
    }
    if (_isSharing) return;
    setState(() => _isSharing = true);
    final record = _toDocumentRecord(doc);
    final result = await doc_helper.DocumentFileHelper.download(
      record,
      _documentsRepository,
    );
    if (!mounted) return;
    if (result == null) {
      showAppToast(
        context,
        'Unable to prepare file for sharing on this platform.',
        isError: true,
      );
      setState(() => _isSharing = false);
      return;
    }
    await Share.shareXFiles(
      [XFile(result.path, mimeType: result.mimeType, name: result.fileName)],
      subject: record.name,
    );
    if (mounted) {
      setState(() => _isSharing = false);
    }
  }

  Widget _buildDocumentDetails() {
    if (_selectedDoc == null) {
      return const Text('Select a document to view details.');
    }

    final doc = _selectedDoc!;
    final expiry = _formatDate(doc['expiry_date']?.toString());
    final mime = (doc['mime_type'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _docTypeLabel(doc),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text('Document Name: ${(doc['document_name'] ?? '').toString()}'),
        if (mime.isNotEmpty) Text('Mime: $mime'),
        if (expiry.isNotEmpty) Text('Expiry: $expiry'),
      ],
    );
  }

  Widget _buildBody(TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            style: textTheme.bodyMedium?.copyWith(color: Colors.red.shade700),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadDocuments,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (_documents.isEmpty) {
      return Text(
        'No personal documents available.',
        style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedType,
          items: _documentTypes
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(_typeLabels[type] ?? _toTitleCase(type)),
                ),
              )
              .toList(),
          decoration: const InputDecoration(
            labelText: 'Document Type',
          ),
          dropdownColor: Colors.white,
          onChanged: (value) {
            setState(() {
              _selectedType = value;
              final docsForType = _docsForType(value);
              _selectedDoc = docsForType.isNotEmpty ? docsForType.first : null;
              _loadPreviewForDoc(_selectedDoc);
            });
          },
        ),
        if (_uniqueDocNameCount(_selectedType) > 1) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<Map<String, dynamic>>(
            value: _selectedDoc,
            items: _docsForType(_selectedType)
                .map(
                  (doc) => DropdownMenuItem(
                    value: doc,
                    child:
                        Text((doc['document_name'] ?? '').toString()),
                  ),
                )
                .toList(),
            decoration: const InputDecoration(
              labelText: 'Document Name',
            ),
            dropdownColor: Colors.white,
            onChanged: (value) {
              setState(() {
                _selectedDoc = value;
                _loadPreviewForDoc(_selectedDoc);
              });
            },
          ),
        ],
        const SizedBox(height: 16),
        Card(
          elevation: 0.5,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildDocumentDetails(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _openDocument(isDownload: false),
                icon: const Icon(Icons.preview),
                label: const Text('Preview'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isSharing ? null : () => _openDocument(isDownload: true),
                icon: _isSharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.share),
                label: const Text('Share'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        if ((_canPreviewInline && _previewController != null) ||
            (kIsWeb && _previewUrl != null && _previewUrl!.isNotEmpty)) ...[
          const SizedBox(height: 16),
          Text(
            'Preview',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_canPreviewInline &&
              _previewController != null &&
              _selectedDoc != null &&
              !_isImageDoc(_selectedDoc!))
            Container(
              height: 360,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  WebViewWidget(controller: _previewController!),
                  if (_previewProgress < 1)
                    LinearProgressIndicator(value: _previewProgress),
                  if (_previewError != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 40),
                            const SizedBox(height: 8),
                            Text(
                              _previewError!,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ),
                ],
              ),
            )
          else if (_selectedDoc != null && _isImageDoc(_selectedDoc!))
            Container(
              height: 360,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: Image.network(
                _resolveDocUrl(_selectedDoc!) ?? '',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.broken_image_outlined),
                  );
                },
              ),
            )
          else
            Container(
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Preview not available inside the app on this device.',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  color: _adminPrimaryColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Personal Documents',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Personal Documents',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select a document to view and download.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.hintColor),
                      ),
                      const SizedBox(height: 16),
                      _buildBody(theme.textTheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  const _ImagePreviewScreen({
    required this.title,
    required this.imageUrl,
  });

  final String title;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 48,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
