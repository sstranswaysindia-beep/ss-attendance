import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/models/safety_models.dart';
import '../../core/services/safety_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class TyreDetailScreen extends StatefulWidget {
  const TyreDetailScreen({
    required this.repository,
    required this.inspectionId,
    required this.position,
    required this.instructions,
    this.initialState,
    super.key,
  });

  final SafetyRepository repository;
  final int inspectionId;
  final String position;
  final TyreInstructions instructions;
  final TyreChecklistTyreState? initialState;

  @override
  State<TyreDetailScreen> createState() => _TyreDetailScreenState();
}

class _TyreDetailScreenState extends State<TyreDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _psiController;
  late final List<TextEditingController> _remarkControllers;
  late final List<TyreCheckpointResult?> _selectedResults;
  XFile? _photoFile;
  bool _isSaving = false;
  bool _showPsiWarning = false;
  final DateFormat _timestampFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  bool _isLoadingExisting = true;
  String? _loadError;
  String? _existingPhotoUrl;
  List<String> _currentWarnings = const <String>[];

  @override
  void initState() {
    super.initState();
    _psiController = TextEditingController();
    final checkpoints = widget.instructions.checkpoints;
    _selectedResults = List<TyreCheckpointResult?>.filled(checkpoints.length, null);
    _remarkControllers = List.generate(
      checkpoints.length,
      (_) => TextEditingController(),
    );

    final initial = widget.initialState;
    if (initial != null) {
      _applyState(initial);
    }

    _existingPhotoUrl = initial?.photoUrl;
    _currentWarnings = initial?.warnings ?? const <String>[];

    _loadExistingState();
  }

  @override
  void dispose() {
    _psiController.dispose();
    for (final controller in _remarkControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingState() async {
    try {
      debugPrint(
        'TyreDetailScreen.loadExistingState -> inspection ${widget.inspectionId}, '
        'position ${widget.position}',
      );
      final state = await widget.repository.fetchTyreState(
        inspectionId: widget.inspectionId,
        positionCode: widget.position,
        expectedCheckpoints: widget.instructions.checkpoints.length,
      );
      if (!mounted) return;
      if (state != null) {
        setState(() {
          _applyState(state);
          _existingPhotoUrl = state.photoUrl ?? _existingPhotoUrl;
        });
      }
      setState(() {
        _isLoadingExisting = false;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('TyreDetail load error: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoadingExisting = false;
        _loadError = error.toString();
      });
    }
  }

  void _applyState(TyreChecklistTyreState state) {
    final checkpoints = widget.instructions.checkpoints;
    for (var i = 0; i < checkpoints.length; i++) {
      final cp = checkpoints[i];
      final match = state.answers.where((entry) => entry.checkpointNo == cp.number);
      if (match.isNotEmpty) {
        final answer = match.first;
        _selectedResults[i] = answer.result;
        _remarkControllers[i].text = answer.remark ?? '';
      } else {
        _selectedResults[i] = null;
        _remarkControllers[i].text = '';
      }
    }
    _psiController.text = state.psi.toStringAsFixed(1);
    _currentWarnings = state.warnings;
  }

  Future<XFile?> _stampPhoto(XFile file) async {
    if (kIsWeb) return file;

    try {
      final originalBytes = await file.readAsBytes();
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return file;

      final stamped = img.Image.from(decoded);
      final text = _timestampFormat.format(DateTime.now());
      final font = img.arial24;
      final margin = (stamped.height * 0.02).clamp(12, 48).toInt();
      const horizontalPadding = 18;
      const verticalPadding = 12;
      final textWidth = _measureTextWidth(font, text);
      final textHeight = font.lineHeight;
      final boxWidth = textWidth + horizontalPadding * 2;
      final boxHeight = textHeight + verticalPadding * 2;
      final boxLeft = math.max(0, stamped.width - boxWidth - margin).toInt();
      final boxTop = math.max(0, stamped.height - boxHeight - margin).toInt();
      final boxRight = math.min(stamped.width - 1, boxLeft + boxWidth).toInt();
      final boxBottom = math.min(stamped.height - 1, boxTop + boxHeight).toInt();

      final backgroundColor = img.ColorUint8.rgba(0, 0, 0, 180);
      img.fillRect(
        stamped,
        x1: boxLeft,
        y1: boxTop,
        x2: boxRight,
        y2: boxBottom,
        color: backgroundColor,
        radius: 10,
      );
      img.drawString(
        stamped,
        text,
        font: font,
        x: boxLeft + horizontalPadding,
        y: boxTop + verticalPadding,
        color: img.ColorUint8.rgba(255, 255, 255, 255),
      );

      final jpgBytes = img.encodeJpg(stamped, quality: 90);
      final stampedName = file.name.isEmpty
          ? 'tyre_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : file.name;
      return XFile.fromData(
        jpgBytes,
        mimeType: 'image/jpeg',
        name: stampedName,
      );
    } catch (error, stackTrace) {
      debugPrint('TyreDetail photo stamp failed: $error\n$stackTrace');
      return file;
    }
  }

  int _measureTextWidth(img.BitmapFont font, String text) {
    var width = 0;
    for (final codeUnit in text.codeUnits) {
      width += font.characterXAdvance(String.fromCharCode(codeUnit));
    }
    return width;
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => _PhotoSourceSheet(),
    );
    if (source == null) return;

    final file = await _picker.pickImage(source: source, imageQuality: 70);
    if (file != null) {
      final stamped = await _stampPhoto(file);
      setState(() => _photoFile = stamped);
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    final checkpoints = widget.instructions.checkpoints;

    bool hasEmpty = false;
    for (var i = 0; i < _selectedResults.length; i++) {
      if (_selectedResults[i] == null) {
        hasEmpty = true;
        break;
      }
    }
    if (hasEmpty) {
      showAppToast(context, 'Please answer all checkpoints', isError: true);
      return;
    }

    final psiValue = double.tryParse(_psiController.text.trim());
    if (psiValue == null) {
      showAppToast(context, 'Enter PSI value for ${widget.position}', isError: true);
      return;
    }

    setState(() => _showPsiWarning = psiValue < widget.instructions.psiMin || psiValue > widget.instructions.psiMax);

    final answers = <TyreAnswer>[];
    for (var i = 0; i < checkpoints.length; i++) {
      answers.add(
        TyreAnswer(
          checkpointNo: checkpoints[i].number,
          result: _selectedResults[i]!,
          remark: _remarkControllers[i].text.trim().isEmpty
              ? null
              : _remarkControllers[i].text.trim(),
        ),
      );
    }

    String? photoBase64;
    if (_photoFile != null) {
      final bytes = await _photoFile!.readAsBytes();
      photoBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    setState(() => _isSaving = true);
    try {
      debugPrint(
        'TyreDetailScreen.save -> inspection=${widget.inspectionId}, '
        'position=${widget.position}, psi=$psiValue, '
        'answers=${answers.map((e) => "${e.checkpointNo}:${e.result.apiValue}").join(',')}',
      );
      final response = await widget.repository.saveTyre(
        inspectionId: widget.inspectionId,
        positionCode: widget.position,
        psi: psiValue,
        answers: answers,
        photoBase64: photoBase64,
      );
      debugPrint(
        'TyreDetailScreen.save success '
        'inspection=${widget.inspectionId}, position=${widget.position}, '
        'answers=${answers.length}, warnings=${response.warnings.length}, '
        'photoUrl=${response.photoUrl}',
      );

      if (response.warnings.isNotEmpty && mounted) {
        for (final warning in response.warnings) {
          showAppToast(context, warning, isError: true);
        }
      }

      final updatedState = TyreChecklistTyreState(
        position: widget.position,
        answers: answers,
        psi: psiValue,
        photoPath: _photoFile?.path,
        photoUrl: response.photoUrl ?? widget.initialState?.photoUrl,
        warnings: response.warnings,
        expectedCheckpoints: checkpoints.length,
      );

      _currentWarnings = response.warnings;
      if (response.photoUrl != null && response.photoUrl!.isNotEmpty) {
        _existingPhotoUrl = response.photoUrl;
      }

      if (mounted) {
        Navigator.of(context).pop(updatedState);
      }
    } catch (error, stackTrace) {
      debugPrint('TyreDetail save error: $error\n$stackTrace');
      if (mounted) {
        showAppToast(context, 'Failed to save tyre: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkpoints = widget.instructions.checkpoints;

    if (_isLoadingExisting) {
      return const AppGradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_loadError != null) {
      return AppGradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load saved data for ${widget.position}.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _isLoadingExisting = true;
                        _loadError = null;
                      });
                      _loadExistingState();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          leading: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            color: theme.colorScheme.onSurface,
          ),
          title: Text(
            'Tyre ${widget.position}',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: checkpoints.length + 3,
                  itemBuilder: (context, index) {
                    if (index < checkpoints.length) {
                      final checkpoint = checkpoints[index];
                      return _CheckpointRow(
                        checkpoint: checkpoint,
                        result: _selectedResults[index],
                        remarkController: _remarkControllers[index],
                        onChanged: (result) {
                          setState(() => _selectedResults[index] = result);
                        },
                      );
                    }

                    if (index == checkpoints.length) {
                      return _PsiInputCard(
                        controller: _psiController,
                        min: widget.instructions.psiMin,
                        max: widget.instructions.psiMax,
                        showWarning: _showPsiWarning,
                      );
                    }

                    if (index == checkpoints.length + 1) {
                      final hasExistingPhoto =
                          (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) &&
                          _photoFile == null;
                      return _PhotoPickerCard(
                        onPickPhoto: _pickPhoto,
                        photoFile: _photoFile,
                        hasExistingPhoto: hasExistingPhoto,
                        existingPhotoUrl: _existingPhotoUrl,
                      );
                    }

                    return _DiagnosticsPanel(
                      inspectionId: widget.inspectionId,
                      position: widget.position,
                      psiMin: widget.instructions.psiMin,
                      psiMax: widget.instructions.psiMax,
                      currentPsi: double.tryParse(_psiController.text.trim()),
                      answersProvided:
                          _selectedResults.where((result) => result != null).length,
                      totalCheckpoints: widget.instructions.checkpoints.length,
                      hasPhoto: _photoFile != null ||
                          ((_existingPhotoUrl ?? '').isNotEmpty),
                      photoPath: _photoFile?.path ?? _existingPhotoUrl,
                      warnings: _currentWarnings,
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: FilledButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Save',
                            style: GoogleFonts.josefinSans(
                              textStyle: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.checkpoint,
    required this.result,
    required this.remarkController,
    required this.onChanged,
  });

  final TyreCheckpoint checkpoint;
  final TyreCheckpointResult? result;
  final TextEditingController remarkController;
  final ValueChanged<TyreCheckpointResult?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showRemark = result == TyreCheckpointResult.nonAcceptable;
    final accentColor = switch (result) {
      TyreCheckpointResult.acceptable => Colors.green.shade700,
      TyreCheckpointResult.caution => Colors.orange.shade700,
      TyreCheckpointResult.nonAcceptable => Colors.red.shade700,
      _ => theme.colorScheme.primary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withOpacity(0.25),
          width: result == null ? 1 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${checkpoint.number}. ${checkpoint.textHi}',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            checkpoint.textEn,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TyreCheckpointResult>(
            key: ValueKey('checkpoint_${checkpoint.number}_${result?.apiValue ?? 'empty'}'),
            value: result,
            items: [
              DropdownMenuItem(
                value: TyreCheckpointResult.acceptable,
                child: _DropdownLabel(
                  label: 'वीकाय / Acceptable - ✔',
                  color: Colors.green.shade700,
                ),
              ),
              DropdownMenuItem(
                value: TyreCheckpointResult.caution,
                child: _DropdownLabel(
                  label: 'खबरदार / Caution - C',
                  color: Colors.orange.shade700,
                ),
              ),
              DropdownMenuItem(
                value: TyreCheckpointResult.nonAcceptable,
                child: _DropdownLabel(
                  label: 'अवीकरणीय / Not Acceptable - ✖',
                  color: Colors.red.shade700,
                ),
              ),
            ],
            onChanged: onChanged,
            dropdownColor: Colors.white,
            iconEnabledColor: accentColor,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: 'Select result',
              labelStyle: theme.textTheme.bodySmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: accentColor.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: accentColor.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(14),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: accentColor, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (showRemark) ...[
            const SizedBox(height: 12),
            TextField(
              controller: remarkController,
              decoration: InputDecoration(
                hintText: 'Add remark (optional)',
                prefixIcon: const Icon(Icons.note_alt_outlined),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: accentColor),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

class _PsiInputCard extends StatelessWidget {
  const _PsiInputCard({
    required this.controller,
    required this.min,
    required this.max,
    required this.showWarning,
  });

  final TextEditingController controller;
  final double min;
  final double max;
  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PSI',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Recommended $min–$max PSI',
              suffixText: 'PSI',
              border: const OutlineInputBorder(),
            ),
          ),
          if (showWarning) ...[
            const SizedBox(height: 8),
            Text(
              'PSI outside recommended range ($min–$max PSI)',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoPickerCard extends StatelessWidget {
  const _PhotoPickerCard({
    required this.onPickPhoto,
    required this.photoFile,
    required this.hasExistingPhoto,
    this.existingPhotoUrl,
  });

  final VoidCallback onPickPhoto;
  final XFile? photoFile;
  final bool hasExistingPhoto;
  final String? existingPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photo (optional)',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Captured photos include date & time watermark automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onPickPhoto,
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Add Photo'),
          ),
          const SizedBox(height: 8),
          if (photoFile != null)
            Text(
              photoFile!.name,
              style: theme.textTheme.bodySmall,
            )
          else if (hasExistingPhoto) ...[
            Text(
              'Existing photo already uploaded',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if ((existingPhotoUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(
                existingPhotoUrl!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ]
          else
            Text(
              'Attach photo when an issue is found for better traceability.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Camera'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.inspectionId,
    required this.position,
    required this.psiMin,
    required this.psiMax,
    required this.currentPsi,
    required this.answersProvided,
    required this.totalCheckpoints,
    required this.hasPhoto,
    required this.photoPath,
    required this.warnings,
  });

  final int inspectionId;
  final String position;
  final double psiMin;
  final double psiMax;
  final double? currentPsi;
  final int answersProvided;
  final int totalCheckpoints;
  final bool hasPhoto;
  final String? photoPath;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          'Diagnostics',
          style: GoogleFonts.josefinSans(
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        subtitle: Text(
          'Inspection $inspectionId · $position',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          _DebugRow(label: 'PSI Range', value: '${psiMin.toStringAsFixed(0)} – ${psiMax.toStringAsFixed(0)}'),
          _DebugRow(
            label: 'Current PSI',
            value: currentPsi != null ? currentPsi!.toStringAsFixed(1) : 'Not entered',
          ),
          _DebugRow(
            label: 'Checkpoint Coverage',
            value: '$answersProvided / $totalCheckpoints',
          ),
          _DebugRow(label: 'Photo Attached', value: hasPhoto ? 'Yes' : 'No'),
          if (hasPhoto && photoPath != null)
            _DebugRow(label: 'Photo Path/URL', value: photoPath!),
          if (warnings.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Warnings',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                ...warnings.map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $warning',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DebugRow extends StatelessWidget {
  const _DebugRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DropdownLabel extends StatelessWidget {
  const _DropdownLabel({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
