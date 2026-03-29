import 'dart:convert';

import 'package:flutter/gestures.dart';
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

// ─── Design tokens (matches salary_advance_screen.dart) ───────────────────────
const Color _primaryColor = Color(0xFF12355B);
const Color _accentColor = Color(0xFF00BFA6);
const Color _gradientStart = Color(0xFF0A1628);
const Color _gradientEnd = Color(0xFF1B3A5C);
const Color _surfaceCard = Color(0xFFF8FAFF);
const Color _pageBackground = Color(0xFFF0F4F8);

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

class _PersonalDocumentsSheetState extends State<_PersonalDocumentsSheet>
    with SingleTickerProviderStateMixin {
  static const String _listUrl =
      'https://sstranswaysindia.com/api/mobile/driver_documents_list.php';
  static final Set<Factory<OneSequenceGestureRecognizer>>
  _webViewGestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };
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

  late final AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _canPreviewInline =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    _loadDocuments();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
    super.dispose();
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
              final name = (doc['document_name'] ?? '')
                  .toString()
                  .toLowerCase();
              return !name.contains('reason: not applicable');
            })
            .toList(growable: false);
        if (!mounted) return;
        setState(() {
          _documents = docs;
          _documentTypes = _buildDocumentTypes(docs);
          _typeLabels = _buildTypeLabels(_documentTypes);
          _selectedType = _documentTypes.isNotEmpty
              ? _documentTypes.first
              : null;
          _selectedDoc = _firstDocForType(_selectedType);
          _loadPreviewForDoc(_selectedDoc);
        });
        _fadeIn.forward(from: 0);
      } else {
        if (!mounted) return;
        setState(() {
          _error = data['error']?.toString() ?? 'Unable to load documents.';
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
        .where((doc) => (doc['document_type'] ?? '').toString() == type)
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
        _previewError = kIsWeb
            ? null
            : 'Inline preview not supported on this device.';
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
      if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
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
        showAppToast(context, 'Preview link not available.', isError: true);
        return;
      }
      if (_isImageDoc(doc)) {
        final imageUrl = _resolveDocUrl(doc);
        if (imageUrl == null) {
          showAppToast(context, 'Preview link not available.', isError: true);
          return;
        }
        await showDialog<void>(
          context: context,
          useRootNavigator: true,
          builder: (_) => DocumentImagePreviewDialog(
            title: _docTypeLabel(doc),
            imageUrl: imageUrl,
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => DocumentPreviewDialog(
          title: _docTypeLabel(doc),
          initialUri: Uri.parse(url),
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
    await Share.shareXFiles([
      XFile(result.path, mimeType: result.mimeType, name: result.fileName),
    ], subject: record.name);
    if (mounted) {
      setState(() => _isSharing = false);
    }
  }

  // ─── Premium helper widgets ─────────────────────────────────────────────────

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
    Color? color,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color ?? _surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _sectionTitle(String text, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, _accentColor],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildPremiumDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required String label,
    IconData? icon,
  }) {
    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: _accentColor),
          dropdownColor: Colors.white,
          hint: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: _accentColor),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ],
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDocumentInfoCard() {
    if (_selectedDoc == null) {
      return _glassCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                color: Colors.grey.shade400,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'Select a document to view details.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final doc = _selectedDoc!;
    final expiry = _formatDate(doc['expiry_date']?.toString());
    final mime = (doc['mime_type'] ?? '').toString();
    final docName = (doc['document_name'] ?? '').toString();
    final isPdf = _isPdfDoc(doc);
    final isImg = _isImageDoc(doc);
    final typeLabel = _docTypeLabel(doc);

    IconData docIcon = Icons.description_rounded;
    if (isPdf) docIcon = Icons.picture_as_pdf_rounded;
    if (isImg) docIcon = Icons.image_rounded;

    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gradient icon container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryColor, _accentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(docIcon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (docName.isNotEmpty && docName != typeLabel) ...[
                      const SizedBox(height: 4),
                      Text(
                        docName,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (mime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        mime.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: _accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (expiry.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  'Expires:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                _statusPill(expiry, _accentColor),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading documents…',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red.shade400,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                _buildGradientButton(
                  label: 'Try Again',
                  icon: Icons.refresh_rounded,
                  onTap: _loadDocuments,
                  colors: [Colors.red.shade400, Colors.red.shade600],
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_documents.isEmpty) {
      return _glassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_off_rounded,
                color: Colors.blueGrey.shade300,
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No personal documents available.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Documents will appear here once uploaded.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Document type selector ─────────────────────────────
          _sectionTitle('Document Type', icon: Icons.category_rounded),
          _buildPremiumDropdown<String>(
            value: _selectedType,
            label: 'Select document type',
            icon: Icons.folder_rounded,
            items: _documentTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(
                      _typeLabels[type] ?? _toTitleCase(type),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedType = value;
                final docsForType = _docsForType(value);
                _selectedDoc = docsForType.isNotEmpty
                    ? docsForType.first
                    : null;
                _loadPreviewForDoc(_selectedDoc);
              });
            },
          ),

          // ── Sub-document selector (when multiple names exist) ──
          if (_uniqueDocNameCount(_selectedType) > 1) ...[
            const SizedBox(height: 8),
            _sectionTitle('Document Name', icon: Icons.description_rounded),
            _buildPremiumDropdown<Map<String, dynamic>>(
              value: _selectedDoc,
              label: 'Select document',
              icon: Icons.insert_drive_file_rounded,
              items: _docsForType(_selectedType)
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc,
                      child: Text(
                        (doc['document_name'] ?? '').toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDoc = value;
                  _loadPreviewForDoc(_selectedDoc);
                });
              },
            ),
          ],

          const SizedBox(height: 8),

          // ── Document info card ─────────────────────────────────
          _sectionTitle('Document Info', icon: Icons.info_rounded),
          _buildDocumentInfoCard(),

          const SizedBox(height: 16),

          // ── Action buttons ─────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _buildGradientButton(
                  label: 'Preview',
                  icon: Icons.preview_rounded,
                  onTap: () => _openDocument(isDownload: false),
                  colors: const [Color(0xFF1B64D8), Color(0xFF0097A7)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildGradientButton(
                  label: _isSharing ? 'Sharing…' : 'Share',
                  icon: _isSharing ? null : Icons.share_rounded,
                  isLoading: _isSharing,
                  onTap: _isSharing
                      ? null
                      : () => _openDocument(isDownload: true),
                  colors: const [Color(0xFF00897B), Color(0xFF00BFA6)],
                ),
              ),
            ],
          ),

          // ── Inline preview ─────────────────────────────────────
          if ((_canPreviewInline && _previewController != null) ||
              (kIsWeb && _previewUrl != null && _previewUrl!.isNotEmpty)) ...[
            const SizedBox(height: 20),
            _sectionTitle('Preview', icon: Icons.visibility_rounded),
            _buildPreviewContainer(),
          ],
        ],
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    IconData? icon,
    required VoidCallback? onTap,
    required List<Color> colors,
    bool isLoading = false,
  }) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: disabled
                ? [Colors.grey.shade300, Colors.grey.shade400]
                : colors,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: colors.last.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContainer() {
    if (_canPreviewInline &&
        _previewController != null &&
        _selectedDoc != null &&
        !_isImageDoc(_selectedDoc!)) {
      return Container(
        height: 380,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _primaryColor.withOpacity(0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            WebViewWidget(
              controller: _previewController!,
              gestureRecognizers: _webViewGestureRecognizers,
            ),
            if (_previewProgress < 1)
              LinearProgressIndicator(
                value: _previewProgress,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(_accentColor),
              ),
            if (_previewError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _previewError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    } else if (_selectedDoc != null && _isImageDoc(_selectedDoc!)) {
      return Container(
        height: 360,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _primaryColor.withOpacity(0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Image.network(
          _resolveDocUrl(_selectedDoc!) ?? '',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(child: Icon(Icons.broken_image_outlined));
          },
        ),
      );
    } else {
      return _glassCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.info_rounded,
                color: Colors.blue.shade400,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Preview not available inside the app on this device.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.87,
      minChildSize: 0.6,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _pageBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  // ── Gradient header ───────────────────────────────────
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _gradientStart,
                          _gradientEnd,
                          Color(0xFF0D4F6B),
                        ],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Drag handle
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Title row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
                          child: Row(
                            children: [
                              // Icon badge
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.13),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.folder_special_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Personal Documents',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_documents.length} document${_documents.length == 1 ? '' : 's'} available',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Close button
                              Material(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => Navigator.of(context).pop(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Scrollable content ────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      child: _buildBody(),
                    ),
                  ),
                ],
              ),
              if (_isSharing)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _accentColor,
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Preparing document...',
                                style: TextStyle(
                                  color: Color(0xFF10233D),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Please wait while sharing starts',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF61718A),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
