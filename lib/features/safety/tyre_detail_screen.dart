import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
    String? apiPosition,
    required this.instructions,
    this.initialState,
    super.key,
  }) : apiPosition = apiPosition ?? position;

  final SafetyRepository repository;
  final int inspectionId;
  final String position;
  final String apiPosition;
  final TyreInstructions instructions;
  final TyreChecklistTyreState? initialState;

  @override
  State<TyreDetailScreen> createState() => _TyreDetailScreenState();
}

class _TyreDetailScreenState extends State<TyreDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  late final String _apiPosition;
  late final TextEditingController _psiController;
  late final List<TextEditingController> _remarkControllers;
  late final List<TyreCheckpointResult?> _selectedResults;
  XFile? _photoFile;
  Uint8List? _photoBytes;
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
    _apiPosition = widget.apiPosition;
    _psiController = TextEditingController();
    final checkpoints = widget.instructions.checkpoints;
    _selectedResults = List<TyreCheckpointResult?>.filled(
      checkpoints.length,
      null,
    );
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
        positionCode: _apiPosition,
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
      final match = state.answers.where(
        (entry) => entry.checkpointNo == cp.number,
      );
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
      final boxBottom = math
          .min(stamped.height - 1, boxTop + boxHeight)
          .toInt();

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
      final target = stamped ?? file;
      final bytes = await target.readAsBytes();
      setState(() {
        _photoFile = target;
        _photoBytes = bytes;
      });
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
      showAppToast(
        context,
        'Enter PSI value for ${widget.position}',
        isError: true,
      );
      return;
    }

    final hasPhoto =
        _photoFile != null || ((_existingPhotoUrl ?? '').isNotEmpty);
    if (!hasPhoto) {
      showAppToast(
        context,
        'Photo is required for ${widget.position}',
        isError: true,
      );
      return;
    }

    setState(
      () => _showPsiWarning =
          psiValue < widget.instructions.psiMin ||
          psiValue > widget.instructions.psiMax,
    );

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
      final bytes = _photoBytes ?? await _photoFile!.readAsBytes();
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
        positionCode: _apiPosition,
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
    // Clamp textScaler to prevent scaling from both font size and display size settings
    final checkpoints = widget.instructions.checkpoints;

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: _buildContent(context, theme, checkpoints),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    List checkpoints,
  ) {
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
                  const Icon(
                    Icons.warning_amber,
                    size: 48,
                    color: Colors.orange,
                  ),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
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
          backgroundColor: const Color(
            0xFF12355B,
          ), // Dark blue (same as training/spot audit)
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: true,
          leading: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            color: Colors.white,
          ),
          title: Text(
            'Tyre ${widget.position}',
            style: GoogleFonts.josefinSans(
              textStyle: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
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
                        showLegend: index == 0,
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
                          (_existingPhotoUrl != null &&
                              _existingPhotoUrl!.isNotEmpty) &&
                          _photoFile == null;
                      return _PhotoPickerCard(
                        onPickPhoto: _pickPhoto,
                        photoFile: _photoFile,
                        photoBytes: _photoBytes,
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
                      answersProvided: _selectedResults
                          .where((result) => result != null)
                          .length,
                      totalCheckpoints: widget.instructions.checkpoints.length,
                      hasPhoto:
                          _photoFile != null ||
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
                      backgroundColor: const Color(0xFF00D100),
                      disabledBackgroundColor: const Color(0xFF9BE79B),
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
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
    this.showLegend = false,
  });

  final TyreCheckpoint checkpoint;
  final TyreCheckpointResult? result;
  final TextEditingController remarkController;
  final ValueChanged<TyreCheckpointResult?> onChanged;
  final bool showLegend;

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

    return Column(
      children: [
        if (showLegend) ...[
          const _SelectionLegend(),
          const SizedBox(height: 8),
        ],
        Container(
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
              Row(
                children: [
                  _SelectionButton(
                    icon: Icons.check_circle,
                    label: 'स्वीकार्य\nAcceptable',
                    color: Colors.green.shade700,
                    selected: result == TyreCheckpointResult.acceptable,
                    onTap: () => onChanged(TyreCheckpointResult.acceptable),
                  ),
                  _SelectionButton(
                    icon: Icons.warning_amber_rounded,
                    label: 'सावधान\nCaution',
                    color: Colors.orange.shade700,
                    selected: result == TyreCheckpointResult.caution,
                    onTap: () => onChanged(TyreCheckpointResult.caution),
                  ),
                  _SelectionButton(
                    icon: Icons.close_rounded,
                    label: 'अस्वीकार्य\nNot OK',
                    color: Colors.red.shade700,
                    selected: result == TyreCheckpointResult.nonAcceptable,
                    onTap: () => onChanged(TyreCheckpointResult.nonAcceptable),
                  ),
                ],
              ),
              if (showRemark) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: remarkController,
                  decoration: InputDecoration(
                    hintText: 'Please describe the issue',
                    prefixIcon: const Icon(Icons.note_alt_outlined),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red.shade400),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectionLegend extends StatelessWidget {
  const _SelectionLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFDDEAFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: const [
          _LegendItem(
            icon: Icons.check_circle,
            color: Color(0xFF15803D),
            label: '✔ Acceptable',
          ),
          _LegendItem(
            icon: Icons.warning_amber_rounded,
            color: Color(0xFFB45309),
            label: '⚠ Caution',
          ),
          _LegendItem(
            icon: Icons.close_rounded,
            color: Color(0xFFB91C1C),
            label: '✖ Not OK',
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SelectionButton extends StatelessWidget {
  const _SelectionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? color.withOpacity(0.12)
                  : const Color(0xFFF5F7FB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color : color.withOpacity(0.35),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: selected ? color : color.withOpacity(0.8)),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? color
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    this.photoBytes,
  });

  final VoidCallback onPickPhoto;
  final XFile? photoFile;
  final bool hasExistingPhoto;
  final String? existingPhotoUrl;
  final Uint8List? photoBytes;

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
            'Photo (required)',
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: photoBytes != null
                      ? Image.memory(
                          photoBytes!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF16A34A),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        photoFile!.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
          ] else
            Text(
              'Attach photo before saving. This helps supervisors validate inspections.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.redAccent,
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
          _DebugRow(
            label: 'PSI Range',
            value:
                '${psiMin.toStringAsFixed(0)} – ${psiMax.toStringAsFixed(0)}',
          ),
          _DebugRow(
            label: 'Current PSI',
            value: currentPsi != null
                ? currentPsi!.toStringAsFixed(1)
                : 'Not entered',
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
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
