import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/app_user.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_toast.dart';

// ─── Design tokens ──────────────────────────────────────────────────────────
const Color _navy = Color(0xFF0A1628);
const Color _navyLight = Color(0xFF153753);
const Color _accent = Color(0xFF00BFA6);
const Color _bgPage = Color(0xFFF0F4F8);
const Color _calendarBlue = Color(0xFF0B72B9);
const String _baseUrl =
    'https://sstranswaysindia.com/api/mobile/employee_save_mobile.php';

// ─── Section colors ──────────────────────────────────────────────────────────
const _sectionColors = [
  [Color(0xFF1A237E), Color(0xFF42A5F5)], // 1 Personal
  [Color(0xFF00695C), Color(0xFF4DB6AC)], // 2 Address
  [Color(0xFF4A148C), Color(0xFFAB47BC)], // 3 Employment
  [Color(0xFFB71C1C), Color(0xFFEF5350)], // 4 Licenses
  [Color(0xFF1B5E20), Color(0xFF66BB6A)], // 5 Bank & Nominee
  [Color(0xFF0D47A1), Color(0xFF64B5F6)], // 6 Reference
  [Color(0xFF37474F), Color(0xFF78909C)], // 7 Work Exp
  [Color(0xFF4E342E), Color(0xFFA1887F)], // 8 Uniform
  [Color(0xFF880E4F), Color(0xFFF06292)], // 9 Misc
  [Color(0xFF0B5CAD), Color(0xFF26C6DA)], // 10 Document Upload
];

class _JoiningUploadFile {
  const _JoiningUploadFile({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  static _JoiningUploadFile? fromBytes({
    required Uint8List bytes,
    required String filename,
  }) {
    if (bytes.isEmpty) return null;
    final safeName = filename.trim().isEmpty ? 'upload.jpg' : filename.trim();
    return _JoiningUploadFile(filename: safeName, bytes: bytes);
  }
}

class NewJoiningScreen extends StatefulWidget {
  const NewJoiningScreen({super.key, required this.user});
  final AppUser user;
  @override
  State<NewJoiningScreen> createState() => _NewJoiningScreenState();
}

class _NewJoiningScreenState extends State<NewJoiningScreen>
    with TickerProviderStateMixin {
  // ─── Draft persistence ───────────────────────────────────────────────────
  static const String _draftKey = 'nj_draft_v1';
  Timer? _saveDebounce;
  bool _hasDraft = false;
  bool _bellHideRequested = false;

  // ─── Section expand tracking ─────────────────────────────────────────────
  final List<bool> _expanded = List.filled(10, false);

  // ─── Loading / saving ────────────────────────────────────────────────────
  bool _loadingFormData = true;
  bool _saving = false;
  String? _loadError;

  // ─── Form key ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  // ─── Dropdown data ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> _plants = const [];
  List<Map<String, dynamic>> _addresses = const [];
  List<String> _banks = const [];

  // ─── Controllers – Section 1: Personal ──────────────────────────────────
  final _empIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _fatherCtrl = TextEditingController();
  String _gender = 'Male';
  DateTime? _dob;
  final _ageCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _aadhaarCtrl = TextEditingController();
  final _panCtrl = TextEditingController();

  // ─── Controllers – Section 2: Address ───────────────────────────────────
  Map<String, dynamic>? _selectedAddress;
  final _permAddrCtrl = TextEditingController();
  final _statePCtrl = TextEditingController();
  final _pincodePCtrl = TextEditingController();
  String _maritalStatus = '';

  // ─── Controllers – Section 3: Employment ────────────────────────────────
  String _empStatus = 'Active';
  String _role = '';
  DateTime? _joinDate;
  final _salaryCtrl = TextEditingController();
  Map<String, dynamic>? _selectedPlant;

  // ─── Controllers – Section 4: Licenses ──────────────────────────────────
  final _dlNoCtrl = TextEditingController();
  final _dlAddrCtrl = TextEditingController();
  DateTime? _dlIssueDate;
  DateTime? _dlExpiry;
  final _dlExpCtrl = TextEditingController();
  final _irteCtrl = TextEditingController();
  DateTime? _irteExpiry;
  final _hazardCtrl = TextEditingController();
  DateTime? _hazardExpiry;
  DateTime? _medicalExpiry;
  _JoiningUploadFile? _aadhaarFrontFile;
  _JoiningUploadFile? _aadhaarBackFile;
  _JoiningUploadFile? _dlFrontFile;
  _JoiningUploadFile? _dlBackFile;
  _JoiningUploadFile? _profilePhotoFile;

  // ─── Controllers – Section 5: Bank, Nominee, Statutory ──────────────────
  final _nomineeCtrl = TextEditingController();
  String _nomineeRelation = '';
  final _nomineePhCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  String _selectedBank = '';
  final _esiCtrl = TextEditingController();
  final _uanCtrl = TextEditingController();

  // ─── Controllers – Section 6: Reference ─────────────────────────────────
  final _fatherFirstCtrl = TextEditingController();
  final _fatherLastCtrl = TextEditingController();
  final _refNameCtrl = TextEditingController();
  String _refRelation = '';
  final _refContactCtrl = TextEditingController();

  // ─── Controllers – Section 7: Experience ────────────────────────────────
  final _exp1CompCtrl = TextEditingController();
  DateTime? _exp1Start, _exp1End;
  final _exp2CompCtrl = TextEditingController();
  DateTime? _exp2Start, _exp2End;
  final _exp3CompCtrl = TextEditingController();
  DateTime? _exp3Start, _exp3End;

  // ─── Controllers – Section 8: Uniform ───────────────────────────────────
  final _pantSzCtrl = TextEditingController();
  final _shirtSzCtrl = TextEditingController();
  final _shoesSzCtrl = TextEditingController();
  DateTime? _pantDate, _shirtDate, _shoesDate;

  // ─── Controllers – Section 9: Misc ──────────────────────────────────────
  final _bulkPgpCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  late final List<AnimationController> _anims;
  final _picker = ImagePicker();

  String _aadhaarDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  String _formatAadhaar(String value) {
    final digits = _aadhaarDigits(value);
    if (digits.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String _formatPan(String value) {
    final cleaned = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length > 10 ? cleaned.substring(0, 10) : cleaned;
  }

  bool _isValidPan(String value) {
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(_formatPan(value));
  }

  String _toCamelCase(String value) {
    final words = value.toLowerCase().split(' ');
    for (var i = 0; i < words.length; i++) {
      if (words[i].isNotEmpty) {
        words[i] = words[i][0].toUpperCase() + words[i].substring(1);
      }
    }
    return words.join(' ');
  }

  String _toUpperCaseValue(String value) => value.toUpperCase();

  void _prefillFatherSplitNames() {
    final full = _fatherCtrl.text.trim();
    if (full.isEmpty) return;

    final parts = full.split(RegExp(r'\s+'));
    if (_fatherFirstCtrl.text.trim().isEmpty) {
      _fatherFirstCtrl.text = _toCamelCase(parts.first);
    }
    if (_fatherLastCtrl.text.trim().isEmpty && parts.length > 1) {
      _fatherLastCtrl.text = _toCamelCase(parts.sublist(1).join(' '));
    }
  }

  List<Map<String, dynamic>> get _filteredAddresses {
    final plantId = _selectedPlant?['id']?.toString();
    if (plantId == null || plantId.isEmpty) return const [];

    return _addresses
        .where((address) => address['plant_id']?.toString() == plantId)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    NotificationService().requestBellHide();
    _bellHideRequested = true;
    _expanded[0] = true;
    _anims = List.generate(
      10,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
        value: i == 0 ? 1.0 : 0.0,
      ),
    );
    _joinDate = DateTime.now();
    _loadFormData();
    // Wire up every text controller to auto-save on change
    for (final c in _allControllers()) {
      c.addListener(_scheduleAutoSave);
    }
    _fatherCtrl.addListener(_prefillFatherSplitNames);
  }

  List<TextEditingController> _allControllers() => [
    _empIdCtrl,
    _nameCtrl,
    _fatherCtrl,
    _ageCtrl,
    _mobileCtrl,
    _aadhaarCtrl,
    _panCtrl,
    _permAddrCtrl,
    _statePCtrl,
    _pincodePCtrl,
    _salaryCtrl,
    _dlNoCtrl,
    _dlAddrCtrl,
    _dlExpCtrl,
    _irteCtrl,
    _hazardCtrl,
    _nomineeCtrl,
    _nomineePhCtrl,
    _ifscCtrl,
    _accountCtrl,
    _esiCtrl,
    _uanCtrl,
    _fatherFirstCtrl,
    _fatherLastCtrl,
    _refNameCtrl,
    _refContactCtrl,
    _exp1CompCtrl,
    _exp2CompCtrl,
    _exp3CompCtrl,
    _pantSzCtrl,
    _shirtSzCtrl,
    _shoesSzCtrl,
    _bulkPgpCtrl,
    _companyCtrl,
    _locationCtrl,
  ];

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final a in _anims) a.dispose();
    _fatherCtrl.removeListener(_prefillFatherSplitNames);
    for (final c in _allControllers()) {
      c.removeListener(_scheduleAutoSave);
      c.dispose();
    }
    if (_bellHideRequested) {
      NotificationService().releaseBellHide();
      _bellHideRequested = false;
    }
    super.dispose();
  }

  // ─── Draft: debounced auto-save ───────────────────────────────────────────
  void _scheduleAutoSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? fmt(DateTime? d) =>
          d == null ? null : DateFormat('yyyy-MM-dd').format(d);
      final data = jsonEncode({
        'name': _nameCtrl.text,
        'father': _fatherCtrl.text,
        'gender': _gender,
        'dob': fmt(_dob),
        'mobile': _mobileCtrl.text,
        'aadhaar': _formatAadhaar(_aadhaarCtrl.text),
        'pan': _formatPan(_panCtrl.text),
        'addr_id': _selectedAddress?['id']?.toString(),
        'perm_addr': _permAddrCtrl.text,
        'state_p': _statePCtrl.text,
        'pincode_p': _pincodePCtrl.text,
        'marital': _maritalStatus,
        'emp_status': _empStatus,
        'role': _role,
        'join_date': fmt(_joinDate),
        'salary': _salaryCtrl.text,
        'plant_id': _selectedPlant?['id']?.toString(),
        'dl_no': _dlNoCtrl.text,
        'dl_addr': _dlAddrCtrl.text,
        'dl_issue': fmt(_dlIssueDate),
        'dl_expiry': fmt(_dlExpiry),
        'dl_exp': _dlExpCtrl.text,
        'irte': _irteCtrl.text,
        'irte_exp': fmt(_irteExpiry),
        'hazard': _hazardCtrl.text,
        'hazard_exp': fmt(_hazardExpiry),
        'medical_exp': fmt(_medicalExpiry),
        'nominee': _nomineeCtrl.text,
        'nom_rel': _nomineeRelation,
        'nom_ph': _nomineePhCtrl.text,
        'ifsc': _ifscCtrl.text,
        'account': _accountCtrl.text,
        'bank': _selectedBank,
        'esi': _esiCtrl.text,
        'uan': _uanCtrl.text,
        'father_first': _fatherFirstCtrl.text,
        'father_last': _fatherLastCtrl.text,
        'ref_name': _refNameCtrl.text,
        'ref_rel': _refRelation,
        'ref_contact': _refContactCtrl.text,
        'exp1_comp': _exp1CompCtrl.text,
        'exp1_start': fmt(_exp1Start),
        'exp1_end': fmt(_exp1End),
        'exp2_comp': _exp2CompCtrl.text,
        'exp2_start': fmt(_exp2Start),
        'exp2_end': fmt(_exp2End),
        'exp3_comp': _exp3CompCtrl.text,
        'exp3_start': fmt(_exp3Start),
        'exp3_end': fmt(_exp3End),
        'pant_sz': _pantSzCtrl.text,
        'shirt_sz': _shirtSzCtrl.text,
        'shoes_sz': _shoesSzCtrl.text,
        'pant_dt': fmt(_pantDate),
        'shirt_dt': fmt(_shirtDate),
        'shoes_dt': fmt(_shoesDate),
        'bulk_pgp': _bulkPgpCtrl.text,
        'company': _companyCtrl.text,
        'location': _locationCtrl.text,
      });
      await prefs.setString(_draftKey, data);
      if (mounted && !_hasDraft) setState(() => _hasDraft = true);
    } catch (_) {}
  }

  Future<void> _loadDraft({
    required List<Map<String, dynamic>> plants,
    required List<Map<String, dynamic>> addresses,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      DateTime? parseDate(String? s) =>
          (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
      void setCtrl(TextEditingController c, String? v) {
        if (v != null && v.isNotEmpty) c.text = v;
      }

      setState(() {
        setCtrl(_nameCtrl, _toCamelCase((m['name'] as String?) ?? ''));
        setCtrl(_fatherCtrl, _toCamelCase((m['father'] as String?) ?? ''));
        _gender = (m['gender'] as String?) ?? 'Male';
        _dob = parseDate(m['dob'] as String?);
        if (_dob != null) _autoAgeFromDob();
        setCtrl(_mobileCtrl, m['mobile'] as String?);
        setCtrl(_aadhaarCtrl, _formatAadhaar((m['aadhaar'] as String?) ?? ''));
        setCtrl(_panCtrl, _formatPan((m['pan'] as String?) ?? ''));
        final addrId = (m['addr_id'] as String?) ?? '';
        if (addrId.isNotEmpty) {
          _selectedAddress = addresses.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a?['id']?.toString() == addrId,
            orElse: () => null,
          );
        }
        setCtrl(_permAddrCtrl, _toCamelCase((m['perm_addr'] as String?) ?? ''));
        setCtrl(_statePCtrl, m['state_p'] as String?);
        setCtrl(_pincodePCtrl, m['pincode_p'] as String?);
        if (_selectedAddress != null) {
          _applyOfficeAddressToPermanent(_selectedAddress);
        }
        _maritalStatus = (m['marital'] as String?) ?? '';
        _empStatus = (m['emp_status'] as String?) ?? 'Active';
        _role = (m['role'] as String?) ?? '';
        _joinDate = parseDate(m['join_date'] as String?) ?? _joinDate;
        setCtrl(_salaryCtrl, m['salary'] as String?);
        final plantId = (m['plant_id'] as String?) ?? '';
        if (plantId.isNotEmpty) {
          _selectedPlant = plants.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p?['id']?.toString() == plantId,
            orElse: () => null,
          );
          if (_selectedPlant != null) {
            _autoBulkPgpFromPlant(_selectedPlant);
            _syncAddressSelectionForPlant();
          }
        }
        setCtrl(_dlNoCtrl, _toUpperCaseValue((m['dl_no'] as String?) ?? ''));
        setCtrl(_dlAddrCtrl, _toCamelCase((m['dl_addr'] as String?) ?? ''));
        _dlIssueDate = parseDate(m['dl_issue'] as String?);
        _dlExpiry = parseDate(m['dl_expiry'] as String?);
        _updateDlExperienceFromIssueDate();
        setCtrl(_irteCtrl, m['irte'] as String?);
        _irteExpiry = parseDate(m['irte_exp'] as String?);
        setCtrl(_hazardCtrl, m['hazard'] as String?);
        _hazardExpiry = parseDate(m['hazard_exp'] as String?);
        _medicalExpiry = parseDate(m['medical_exp'] as String?);
        setCtrl(_nomineeCtrl, _toCamelCase((m['nominee'] as String?) ?? ''));
        _nomineeRelation = (m['nom_rel'] as String?) ?? '';
        setCtrl(_nomineePhCtrl, m['nom_ph'] as String?);
        setCtrl(_ifscCtrl, _toUpperCaseValue((m['ifsc'] as String?) ?? ''));
        setCtrl(_accountCtrl, m['account'] as String?);
        _selectedBank = (m['bank'] as String?) ?? '';
        setCtrl(_esiCtrl, m['esi'] as String?);
        setCtrl(_uanCtrl, m['uan'] as String?);
        setCtrl(
          _fatherFirstCtrl,
          _toCamelCase((m['father_first'] as String?) ?? ''),
        );
        setCtrl(
          _fatherLastCtrl,
          _toCamelCase((m['father_last'] as String?) ?? ''),
        );
        _prefillFatherSplitNames();
        setCtrl(_refNameCtrl, _toCamelCase((m['ref_name'] as String?) ?? ''));
        _refRelation = (m['ref_rel'] as String?) ?? '';
        setCtrl(_refContactCtrl, m['ref_contact'] as String?);
        setCtrl(_exp1CompCtrl, _toCamelCase((m['exp1_comp'] as String?) ?? ''));
        _exp1Start = parseDate(m['exp1_start'] as String?);
        _exp1End = parseDate(m['exp1_end'] as String?);
        setCtrl(_exp2CompCtrl, _toCamelCase((m['exp2_comp'] as String?) ?? ''));
        _exp2Start = parseDate(m['exp2_start'] as String?);
        _exp2End = parseDate(m['exp2_end'] as String?);
        setCtrl(_exp3CompCtrl, _toCamelCase((m['exp3_comp'] as String?) ?? ''));
        _exp3Start = parseDate(m['exp3_start'] as String?);
        _exp3End = parseDate(m['exp3_end'] as String?);
        setCtrl(_pantSzCtrl, m['pant_sz'] as String?);
        setCtrl(_shirtSzCtrl, m['shirt_sz'] as String?);
        setCtrl(_shoesSzCtrl, m['shoes_sz'] as String?);
        _pantDate = parseDate(m['pant_dt'] as String?);
        _shirtDate = parseDate(m['shirt_dt'] as String?);
        _shoesDate = parseDate(m['shoes_dt'] as String?);
        setCtrl(_bulkPgpCtrl, m['bulk_pgp'] as String?);
        setCtrl(_companyCtrl, _toCamelCase((m['company'] as String?) ?? ''));
        setCtrl(_locationCtrl, m['location'] as String?);
        _hasDraft = true;
      });
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      if (mounted) setState(() => _hasDraft = false);
    } catch (_) {}
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.restart_alt_rounded,
                color: Color(0xFFD32F2F),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Reset Form?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'This will clear all entered fields and delete the saved draft. This action cannot be undone.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF4B5563),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _resetForm();
  }

  void _resetForm() {
    setState(() {
      for (final c in _allControllers()) c.clear();
      _gender = 'Male';
      _dob = null;
      _selectedAddress = null;
      _maritalStatus = '';
      _empStatus = 'Active';
      _role = '';
      _joinDate = DateTime.now();
      _selectedPlant = null;
      _dlIssueDate = null;
      _dlExpiry = null;
      _irteExpiry = null;
      _hazardExpiry = null;
      _medicalExpiry = null;
      _nomineeRelation = '';
      _selectedBank = '';
      _refRelation = '';
      _exp1Start = null;
      _exp1End = null;
      _exp2Start = null;
      _exp2End = null;
      _exp3Start = null;
      _exp3End = null;
      _pantDate = null;
      _shirtDate = null;
      _shoesDate = null;
      _hasDraft = false;
    });
    _clearDraft();
    showAppToast(context, 'Form cleared.');
  }

  // ─── Load form data ──────────────────────────────────────────────────────
  Future<void> _loadFormData() async {
    setState(() {
      _loadingFormData = true;
      _loadError = null;
    });
    try {
      final res = await http.get(Uri.parse('$_baseUrl?action=form_data'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['status'] == 'ok') {
          final plants = List<Map<String, dynamic>>.from(body['plants'] ?? []);
          final addresses = List<Map<String, dynamic>>.from(
            body['addresses'] ?? [],
          );
          final banks = List<String>.from(body['banks'] ?? []);
          final nextEmpId = (body['next_emp_id'] as String?) ?? '';
          setState(() {
            _plants = plants;
            _addresses = addresses;
            _banks = banks;
            _empIdCtrl.text = nextEmpId;
            _loadingFormData = false;
          });
          // Load saved draft AFTER dropdowns are available
          await _loadDraft(plants: plants, addresses: addresses);
          return;
        }
      }
      setState(() {
        _loadingFormData = false;
        _loadError = 'Failed to load form data.';
      });
    } catch (e) {
      setState(() {
        _loadingFormData = false;
        _loadError = 'Network error: $e';
      });
    }
  }

  // ─── Toggle section ──────────────────────────────────────────────────────
  void _toggle(int index) {
    final shouldOpen = !_expanded[index];

    setState(() {
      for (var i = 0; i < _expanded.length; i++) {
        _expanded[i] = shouldOpen && i == index;
      }
    });

    for (var i = 0; i < _anims.length; i++) {
      if (_expanded[i]) {
        _anims[i].forward();
      } else {
        _anims[i].reverse();
      }
    }
  }

  void _openOnlySection(int index) {
    setState(() {
      for (var i = 0; i < _expanded.length; i++) {
        _expanded[i] = i == index;
      }
    });

    for (var i = 0; i < _anims.length; i++) {
      if (_expanded[i]) {
        _anims[i].forward();
      } else {
        _anims[i].reverse();
      }
    }
  }

  // ─── Date pickers ────────────────────────────────────────────────────────
  Future<DateTime?> _pickDate({
    DateTime? initial,
    String? help,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final minDate = firstDate ?? DateTime(1950, 1, 1);
    final maxDate = lastDate ?? DateTime(2050, 12, 31);
    final initialDate = initial ?? now;

    return showDialog<DateTime>(
      context: context,
      builder: (_) => _CalendarPickerDialog(
        title: help,
        initialDate: initialDate.isBefore(minDate)
            ? minDate
            : initialDate.isAfter(maxDate)
            ? maxDate
            : initialDate,
        firstDay: minDate,
        lastDay: maxDate,
      ),
    );
  }

  Future<DateTime?> _pickDobDate({DateTime? initial}) async {
    final now = DateTime.now();
    return _pickDate(
      initial: initial ?? DateTime(now.year - 25, now.month, now.day),
      help: 'Date of Birth',
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
  }

  void _autoAgeFromDob() {
    if (_dob == null) return;
    final age = DateTime.now().year - _dob!.year;
    _ageCtrl.text = age.toString();
  }

  void _autoBulkPgpFromPlant(Map<String, dynamic>? plant) {
    if (plant == null) {
      _bulkPgpCtrl.text = '';
      return;
    }
    final cat = (plant['category'] as String?) ?? '';
    _bulkPgpCtrl.text = cat;
  }

  void _applyOfficeAddressToPermanent(Map<String, dynamic>? address) {
    if (address == null) return;

    final state = (address['state']?.toString() ?? '').trim();
    final pincode = (address['pincode']?.toString() ?? '').trim();

    if (state.isNotEmpty) _statePCtrl.text = state;
    if (pincode.isNotEmpty) _pincodePCtrl.text = pincode;
  }

  void _syncAddressSelectionForPlant() {
    final plantId = _selectedPlant?['id']?.toString();
    if (plantId == null || plantId.isEmpty) {
      _selectedAddress = null;
      _statePCtrl.clear();
      _pincodePCtrl.clear();
      return;
    }

    final filtered = _filteredAddresses;
    if (_selectedAddress != null &&
        _selectedAddress?['plant_id']?.toString() != plantId) {
      _selectedAddress = null;
      _statePCtrl.clear();
      _pincodePCtrl.clear();
    }

    if (_selectedAddress == null && filtered.length == 1) {
      _selectedAddress = filtered.first;
    }

    if (_selectedAddress != null) {
      _applyOfficeAddressToPermanent(_selectedAddress);
    }
  }

  void _handlePlantChanged(Map<String, dynamic>? plant) {
    setState(() {
      _selectedPlant = plant;
      _autoBulkPgpFromPlant(plant);
      _syncAddressSelectionForPlant();
    });
    _scheduleAutoSave();
  }

  void _updateDlExperienceFromIssueDate() {
    if (_dlIssueDate == null) {
      _dlExpCtrl.clear();
      return;
    }

    final start = DateUtils.dateOnly(_dlIssueDate!);
    final now = DateUtils.dateOnly(DateTime.now());

    if (start.isAfter(now)) {
      _dlExpCtrl.text = '0 years 0 months';
      return;
    }

    var years = now.year - start.year;
    var months = now.month - start.month;

    if (now.day < start.day) {
      months--;
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    years = years < 0 ? 0 : years;
    months = months < 0 ? 0 : months;
    _dlExpCtrl.text =
        '$years year${years == 1 ? '' : 's'} $months month${months == 1 ? '' : 's'}';
  }

  _JoiningUploadFile? _fileForSlot(String slot) {
    switch (slot) {
      case 'aadhaar_front':
        return _aadhaarFrontFile;
      case 'aadhaar_back':
        return _aadhaarBackFile;
      case 'dl_front':
        return _dlFrontFile;
      case 'dl_back':
        return _dlBackFile;
      case 'profile_photo':
        return _profilePhotoFile;
    }
    return null;
  }

  void _setFileForSlot(String slot, _JoiningUploadFile? file) {
    setState(() {
      switch (slot) {
        case 'aadhaar_front':
          _aadhaarFrontFile = file;
          break;
        case 'aadhaar_back':
          _aadhaarBackFile = file;
          break;
        case 'dl_front':
          _dlFrontFile = file;
          break;
        case 'dl_back':
          _dlBackFile = file;
          break;
        case 'profile_photo':
          _profilePhotoFile = file;
          break;
      }
    });
  }

  String _slotTitle(String slot) {
    switch (slot) {
      case 'aadhaar_front':
        return 'Aadhaar Front';
      case 'aadhaar_back':
        return 'Aadhaar Back';
      case 'dl_front':
        return 'Driving Licence Front';
      case 'dl_back':
        return 'Driving Licence Back';
      case 'profile_photo':
        return 'Profile Photo';
    }
    return 'Document';
  }

  String _slotFallbackFileName(String slot) {
    switch (slot) {
      case 'aadhaar_front':
        return 'aadhaar_front.jpg';
      case 'aadhaar_back':
        return 'aadhaar_back.jpg';
      case 'dl_front':
        return 'driving_licence_front.jpg';
      case 'dl_back':
        return 'driving_licence_back.jpg';
      case 'profile_photo':
        return 'profile_photo.jpg';
    }
    return 'document.jpg';
  }

  bool get _hasAnyDocumentUpload =>
      _aadhaarFrontFile != null ||
      _aadhaarBackFile != null ||
      _dlFrontFile != null ||
      _dlBackFile != null ||
      _profilePhotoFile != null;

  Future<void> _pickDocument({
    required String slot,
    required ImageSource source,
  }) async {
    if (kIsWeb && source == ImageSource.gallery) {
      await _pickWebDocument(slot: slot);
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final file = _JoiningUploadFile.fromBytes(
        bytes: bytes,
        filename: picked.name.isNotEmpty
            ? picked.name
            : _slotFallbackFileName(slot),
      );
      if (file == null) {
        if (!mounted) return;
        showAppToast(context, 'Selected file is empty.', isError: true);
        return;
      }

      if (!mounted) return;
      _setFileForSlot(slot, file);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to select image.', isError: true);
    }
  }

  Future<void> _pickWebDocument({required String slot}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        showAppToast(context, 'Selected file is empty.', isError: true);
        return;
      }

      final file = _JoiningUploadFile.fromBytes(
        bytes: bytes,
        filename: picked.name.isNotEmpty
            ? picked.name
            : _slotFallbackFileName(slot),
      );
      if (file == null) {
        if (!mounted) return;
        showAppToast(context, 'Selected file is empty.', isError: true);
        return;
      }

      if (!mounted) return;
      _setFileForSlot(slot, file);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to select image.', isError: true);
    }
  }

  void _showDocumentPickOptions(String slot) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _slotTitle(slot),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Portrait and landscape photos are both supported.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSourceTile(
                  icon: Icons.camera_alt_rounded,
                  title: 'Camera',
                  subtitle: kIsWeb
                      ? 'Open camera capture'
                      : 'Take a fresh photo',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickDocument(slot: slot, source: ImageSource.camera);
                  },
                ),
                const SizedBox(height: 10),
                _buildSourceTile(
                  icon: Icons.photo_library_rounded,
                  title: kIsWeb ? 'Choose File' : 'Gallery',
                  subtitle: 'Select from your device',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickDocument(slot: slot, source: ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _uploadDocuments({required String empId}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl?action=upload_documents'),
    );

    request.fields['empid'] = empId;
    request.fields['user_id'] = widget.user.id.toString();

    if (_aadhaarFrontFile != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'aadhar_front',
          _aadhaarFrontFile!.bytes,
          filename: _aadhaarFrontFile!.filename,
        ),
      );
    }

    if (_aadhaarBackFile != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'aadhar_back',
          _aadhaarBackFile!.bytes,
          filename: _aadhaarBackFile!.filename,
        ),
      );
    }

    if (_dlFrontFile != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'dl_front',
          _dlFrontFile!.bytes,
          filename: _dlFrontFile!.filename,
        ),
      );
    }

    if (_dlBackFile != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'dl_back',
          _dlBackFile!.bytes,
          filename: _dlBackFile!.filename,
        ),
      );
    }

    if (_profilePhotoFile != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'profile_photo',
          _profilePhotoFile!.bytes,
          filename: _profilePhotoFile!.filename,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ─── Submit ──────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      showAppToast(
        context,
        'Please fix the highlighted fields.',
        isError: true,
      );
      return;
    }
    if (_dob == null) {
      _openOnlySection(0);
      showAppToast(context, 'Date of Birth is required.', isError: true);
      return;
    }
    if (_role.toLowerCase() != 'helper') {
      if (_dlNoCtrl.text.trim().isEmpty) {
        _openOnlySection(3);
        showAppToast(context, 'DL Number is required.', isError: true);
        return;
      }
      if (_dlIssueDate == null) {
        _openOnlySection(3);
        showAppToast(context, 'DL Issue Date is required.', isError: true);
        return;
      }
      if (_dlExpiry == null) {
        _openOnlySection(3);
        showAppToast(context, 'DL Expiry Date is required.', isError: true);
        return;
      }
      if (_dlAddrCtrl.text.trim().isEmpty) {
        _openOnlySection(3);
        showAppToast(context, 'DL Address is required.', isError: true);
        return;
      }
    }
    if (_profilePhotoFile == null) {
      _openOnlySection(9);
      showAppToast(context, 'Profile photo is required.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = {
        'user_id': widget.user.id,
        'username': widget.user.displayName,
        'empid': _empIdCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'father_name': _fatherCtrl.text.trim(),
        'gender': _gender,
        'dob': _dob == null ? '' : DateFormat('yyyy-MM-dd').format(_dob!),
        'age': _ageCtrl.text.trim(),
        'contact': _mobileCtrl.text.trim(),
        'aadhaar_number': _formatAadhaar(_aadhaarCtrl.text.trim()),
        'pan_card': _formatPan(_panCtrl.text.trim()),
        'address_local_id': _selectedAddress?['id']?.toString() ?? '',
        'address_permanent': _permAddrCtrl.text.trim(),
        'state_permanent': _statePCtrl.text.trim(),
        'pincode_permanent': _pincodePCtrl.text.trim(),
        'marital_status': _maritalStatus,
        'status': _empStatus,
        'role': _role,
        'joining_date': _joinDate == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_joinDate!),
        'salary': _salaryCtrl.text.trim(),
        'plant_id': _selectedPlant?['id']?.toString() ?? '',
        'dl_number': _dlNoCtrl.text.trim(),
        'dl_address': _dlAddrCtrl.text.trim(),
        'dl_issue_date': _dlIssueDate == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_dlIssueDate!),
        'license_expiry_date': _dlExpiry == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_dlExpiry!),
        'dl_experience': _dlExpCtrl.text.trim(),
        'irte': _irteCtrl.text.trim(),
        'irte_license_validity': _irteExpiry == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_irteExpiry!),
        'hazards': _hazardCtrl.text.trim(),
        'hazard_license_validity': _hazardExpiry == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_hazardExpiry!),
        'medical': _medicalExpiry == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_medicalExpiry!),
        'nominee_name': _nomineeCtrl.text.trim(),
        'relation_nominee': _nomineeRelation,
        'nominee_contact': _nomineePhCtrl.text.trim(),
        'ifsc_code': _ifscCtrl.text.trim(),
        'bank_account_number': _accountCtrl.text.trim(),
        'branch_name': _selectedBank,
        'esi_number': _esiCtrl.text.trim(),
        'uan_number': _uanCtrl.text.trim(),
        'father_first_name': _fatherFirstCtrl.text.trim(),
        'father_last_name': _fatherLastCtrl.text.trim(),
        'ref_name': _refNameCtrl.text.trim(),
        'ref_relation': _refRelation,
        'ref_contact': _refContactCtrl.text.trim(),
        'exp_company_1': _exp1CompCtrl.text.trim(),
        'exp_start_date_1': _exp1Start == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_exp1Start!),
        'exp_end_date_1': _exp1End == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_exp1End!),
        'exp_company_2': _exp2CompCtrl.text.trim(),
        'exp_start_date_2': _exp2Start == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_exp2Start!),
        'exp_end_date_2': _exp2End == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_exp2End!),
        'exp_company_3': _exp3CompCtrl.text.trim(),
        'exp_start_date_3': _exp3Start == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_exp3Start!),
        'exp_end_date_3': _exp3End == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_exp3End!),
        'paint': _pantSzCtrl.text.trim(),
        'shirt': _shirtSzCtrl.text.trim(),
        'shoes': _shoesSzCtrl.text.trim(),
        'pant_issue_date': _pantDate == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_pantDate!),
        'shirt_issue_date': _shirtDate == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_shirtDate!),
        'shoes_issue_date': _shoesDate == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_shoesDate!),
        'bulk_pgp': _bulkPgpCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
      };

      final res = await http.post(
        Uri.parse('$_baseUrl?action=save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        final empId = body['empid']?.toString() ?? '';
        if (empId.isNotEmpty) {
          _empIdCtrl.text = empId;
        }

        if (_hasAnyDocumentUpload && empId.isNotEmpty) {
          final uploadBody = await _uploadDocuments(empId: empId);
          if (!mounted) return;
          if (uploadBody['success'] != true) {
            showAppToast(
              context,
              uploadBody['message']?.toString() ??
                  'Employee saved, but document upload failed.',
              isError: true,
            );
            return;
          }
        }

        await _clearDraft();
        if (!mounted) return;
        showAppToast(
          context,
          _hasAnyDocumentUpload
              ? 'Employee added and documents uploaded! EmpID: $empId'
              : 'Employee added! EmpID: $empId',
        );
        Navigator.of(context).pop();
      } else {
        showAppToast(
          context,
          body['message']?.toString() ?? 'Save failed.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'Network error: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPage,
      body: Column(
        children: [
          _buildAppBar(),
          if (_loadingFormData)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: _accent)),
            )
          else if (_loadError != null)
            Expanded(child: _buildErrorState())
          else
            Expanded(child: _buildForm()),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navyLight],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 2),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Joining',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (_hasDraft)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Draft saved',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: _accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Employee Registration',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              // EmpID pill
              if (_empIdCtrl.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent.withOpacity(0.5)),
                  ),
                  child: Text(
                    _empIdCtrl.text,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // Reset button
              Tooltip(
                message: 'Reset form & clear draft',
                child: IconButton(
                  icon: const Icon(
                    Icons.restart_alt_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _loadingFormData ? null : _confirmReset,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _loadError!,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadFormData,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          _sectionCard(
            0,
            Icons.person_rounded,
            '1. Personal Information',
            _buildSection1(),
          ),
          _sectionCard(
            1,
            Icons.location_on_rounded,
            '2. Contact & Address',
            _buildSection2(),
          ),
          _sectionCard(
            2,
            Icons.work_rounded,
            '3. Employment',
            _buildSection3(),
          ),
          _sectionCard(
            3,
            Icons.badge_rounded,
            '4. Licenses & Certificates',
            _buildSection4(),
          ),
          _sectionCard(
            4,
            Icons.account_balance_rounded,
            '5. Bank, Nominee & Statutory',
            _buildSection5(),
          ),
          _sectionCard(
            5,
            Icons.people_rounded,
            '6. Reference / Relative',
            _buildSection6(),
          ),
          _sectionCard(
            6,
            Icons.work_history_rounded,
            '7. Work Experience',
            _buildSection7(),
          ),
          _sectionCard(
            7,
            Icons.checkroom_rounded,
            '8. Uniform Sizes',
            _buildSection8(),
          ),
          _sectionCard(
            8,
            Icons.info_outline_rounded,
            '9. Miscellaneous',
            _buildSection9(),
          ),
          _sectionCard(
            9,
            Icons.upload_file_rounded,
            '10. Document Upload',
            _buildSection10(),
          ),
          const SizedBox(height: 16),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  // ─── Section Card wrapper ─────────────────────────────────────────────────
  bool _isSectionComplete(int index) {
    switch (index) {
      case 0: // Personal — key personal fields required
        return _nameCtrl.text.trim().isNotEmpty &&
            _fatherCtrl.text.trim().isNotEmpty &&
            _dob != null &&
            _mobileCtrl.text.trim().length == 10 &&
            _aadhaarDigits(_aadhaarCtrl.text.trim()).length == 12;
      case 1: // Address — office addr + permanent + state + pincode + marital
        return _selectedPlant != null &&
            _selectedAddress != null &&
            _permAddrCtrl.text.trim().isNotEmpty &&
            _statePCtrl.text.trim().isNotEmpty &&
            _pincodePCtrl.text.trim().isNotEmpty &&
            _maritalStatus.isNotEmpty;
      case 2: // Employment — role + salary
        return _role.isNotEmpty && _salaryCtrl.text.trim().isNotEmpty;
      case 3: // Licenses — mandatory for all non-helper roles
        if (_role.toLowerCase() == 'helper') return true;
        return _dlNoCtrl.text.trim().isNotEmpty &&
            _dlIssueDate != null &&
            _dlExpiry != null &&
            _dlAddrCtrl.text.trim().isNotEmpty;
      case 4: // Bank & Nominee — nominee + ifsc + account + bank
        return _nomineeCtrl.text.trim().isNotEmpty &&
            _nomineeRelation.isNotEmpty &&
            _ifscCtrl.text.trim().isNotEmpty &&
            _accountCtrl.text.trim().isNotEmpty &&
            _selectedBank.isNotEmpty;
      case 5: // Reference — father split names required
        return _fatherFirstCtrl.text.trim().isNotEmpty &&
            _fatherLastCtrl.text.trim().isNotEmpty;
      case 6: // Work Experience — optional; complete if at least 1 company
        return _exp1CompCtrl.text.trim().isNotEmpty;
      case 7: // Uniform — optional; complete if at least 1 size
        return _pantSzCtrl.text.trim().isNotEmpty ||
            _shirtSzCtrl.text.trim().isNotEmpty ||
            _shoesSzCtrl.text.trim().isNotEmpty;
      case 8: // Misc — optional; complete if location or company
        return _locationCtrl.text.trim().isNotEmpty ||
            _companyCtrl.text.trim().isNotEmpty;
      case 9: // Document Upload
        return _profilePhotoFile != null;
      default:
        return false;
    }
  }

  Widget _sectionStatusAsset(bool isComplete, bool isOpen) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isOpen ? Colors.white.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(1),
      child: Image.asset(
        isComplete
            ? 'downloads/check_mark_status.gif'
            : 'downloads/warning_status.gif',
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _sectionCard(int index, IconData icon, String title, Widget content) {
    final grad = _sectionColors[index];
    final isOpen = _expanded[index];
    final isComplete = _isSectionComplete(index);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Header
            InkWell(
              onTap: () => _toggle(index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: isOpen
                      ? LinearGradient(colors: [grad[0], grad[1]])
                      : null,
                  color: isOpen ? null : Colors.white,
                  border: isOpen
                      ? null
                      : Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? Colors.white.withOpacity(0.2)
                            : grad[0].withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: isOpen ? Colors.white : grad[0],
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isOpen ? Colors.white : _navy,
                        ),
                      ),
                    ),
                    _sectionStatusAsset(isComplete, isOpen),
                  ],
                ),
              ),
            ),
            // Animated content
            SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: _anims[index],
                curve: Curves.easeInOut,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Field helpers ────────────────────────────────────────────────────────
  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? hint,
    bool readOnly = false,
    int maxLines = 1,
    String? Function(String?)? validator,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF4B5563),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboard,
          inputFormatters: formatters,
          readOnly: readOnly || onTap != null,
          maxLines: maxLines,
          onTap: onTap,
          validator: validator,
          style: GoogleFonts.poppins(fontSize: 13, color: _navy),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _accent, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red, width: 1.2),
            ),
            filled: true,
            fillColor: readOnly ? const Color(0xFFF3F4F6) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged, {
    bool required = false,
  }) {
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        canvasColor: Colors.white,
        splashColor: Colors.transparent,
        highlightColor: Colors.white,
        hoverColor: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF4B5563),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            validator: required ? (v) => v == null ? 'Required' : null : null,
            dropdownColor: Colors.white,
            style: GoogleFonts.poppins(fontSize: 13, color: _navy),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.5),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _datePickerField(String label, DateTime? value, VoidCallback onTap) {
    final text = value == null ? '' : DateFormat('dd MMM yyyy').format(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF4B5563),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text.isEmpty ? 'Select date' : text,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: text.isEmpty ? Colors.grey.shade400 : _navy,
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row2(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 10),
      Expanded(child: b),
    ],
  );

  Widget _gap() => const SizedBox(height: 12);

  Widget _buildSourceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required _JoiningUploadFile? file,
    required VoidCallback onPick,
    required VoidCallback onRemove,
    required Color accentColor,
    required Color surfaceColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (file != null) ...[
            Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withOpacity(0.16)),
              ),
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(file.bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              file.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: accentColor.withOpacity(0.22),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 22,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Portrait and landscape photos supported',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPick,
                  icon: Icon(
                    file == null ? Icons.upload_rounded : Icons.refresh_rounded,
                    size: 16,
                  ),
                  label: Text(
                    file == null ? 'Upload' : 'Change',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (file != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onRemove,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    side: BorderSide(color: accentColor.withOpacity(0.22)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Remove',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentGroup({
    required String title,
    required String subtitle,
    required String frontSlot,
    required String backSlot,
    required Color accentColor,
    required Color surfaceColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          _row2(
            _buildUploadCard(
              title: 'Front Photo',
              subtitle: 'Upload front side',
              icon: Icons.crop_portrait_rounded,
              file: _fileForSlot(frontSlot),
              onPick: () => _showDocumentPickOptions(frontSlot),
              onRemove: () => _setFileForSlot(frontSlot, null),
              accentColor: accentColor,
              surfaceColor: Colors.white.withOpacity(0.7),
            ),
            _buildUploadCard(
              title: 'Back Photo',
              subtitle: 'Upload back side',
              icon: Icons.flip_to_back_rounded,
              file: _fileForSlot(backSlot),
              onPick: () => _showDocumentPickOptions(backSlot),
              onRemove: () => _setFileForSlot(backSlot, null),
              accentColor: accentColor,
              surfaceColor: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentUploadSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _calendarBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.upload_file_rounded,
                  color: _calendarBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document Upload',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                    ),
                    Text(
                      'After account creation, front and back image links upload automatically into the raw document columns.',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDocumentGroup(
            title: 'Aadhaar',
            subtitle: 'Supports portrait and landscape images',
            frontSlot: 'aadhaar_front',
            backSlot: 'aadhaar_back',
            accentColor: const Color(0xFFE08A00),
            surfaceColor: const Color(0xFFFFF7E8),
          ),
          const SizedBox(height: 10),
          _buildDocumentGroup(
            title: 'Driving Licence',
            subtitle: 'Front and back photos are stored together',
            frontSlot: 'dl_front',
            backSlot: 'dl_back',
            accentColor: const Color(0xFF2F80ED),
            surfaceColor: const Color(0xFFEFF6FF),
          ),
          const SizedBox(height: 10),
          _buildUploadCard(
            title: 'Photo Upload *',
            subtitle: 'Single driver profile photo required',
            icon: Icons.account_circle_rounded,
            file: _fileForSlot('profile_photo'),
            onPick: () => _showDocumentPickOptions('profile_photo'),
            onRemove: () => _setFileForSlot('profile_photo', null),
            accentColor: const Color(0xFF0AA37F),
            surfaceColor: const Color(0xFFEAFBF6),
          ),
        ],
      ),
    );
  }

  // ─── SECTION 1: Personal ─────────────────────────────────────────────────
  Widget _buildSection1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row2(
          _field('EMP ID (Auto)', _empIdCtrl, readOnly: true),
          _dropdown<String>(
            'Gender',
            _gender,
            [
              DropdownMenuItem(
                value: 'Male',
                child: Text('Male', style: GoogleFonts.poppins(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: 'Female',
                child: Text('Female', style: GoogleFonts.poppins(fontSize: 13)),
              ),
            ],
            (v) {
              setState(() => _gender = v ?? 'Male');
              _scheduleAutoSave();
            },
          ),
        ),
        _gap(),
        _field(
          'Full Name *',
          _nameCtrl,
          formatters: [CamelCaseInputFormatter()],
          hint: 'Driver / Helper Name',
          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
        ),
        _gap(),
        _field(
          'Father Name *',
          _fatherCtrl,
          formatters: [CamelCaseInputFormatter()],
          hint: 'Father\'s full name',
          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
        ),
        _gap(),
        _row2(
          _datePickerField('Date of Birth *', _dob, () async {
            final d = await _pickDobDate(initial: _dob);
            if (d != null) {
              setState(() {
                _dob = d;
                _autoAgeFromDob();
              });
              _scheduleAutoSave();
            }
          }),
          _field(
            'Age',
            _ageCtrl,
            keyboard: TextInputType.number,
            readOnly: true,
            hint: 'Auto from DOB',
          ),
        ),
        _gap(),
        _row2(
          _field(
            'Mobile *',
            _mobileCtrl,
            keyboard: TextInputType.phone,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            hint: '10-digit mobile',
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return 'Required';
              if (s.length != 10) return 'Enter 10 digits';
              return null;
            },
          ),
          _field(
            'Aadhaar *',
            _aadhaarCtrl,
            keyboard: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
              LengthLimitingTextInputFormatter(14),
              AadhaarInputFormatter(),
            ],
            hint: 'XXXX XXXX XXXX',
            validator: (v) {
              final digits = _aadhaarDigits(v?.trim() ?? '');
              if (digits.isEmpty) return 'Required';
              if (digits.length != 12) return 'Enter 12 digits';
              return null;
            },
          ),
        ),
        _gap(),
        _row2(
          _field(
            'PAN Card',
            _panCtrl,
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              LengthLimitingTextInputFormatter(10),
              PanInputFormatter(),
            ],
            hint: 'ABCDE1234F',
            validator: (v) {
              final pan = _formatPan(v?.trim() ?? '');
              if (pan.isEmpty) return null;
              if (!_isValidPan(pan)) return 'Use format AAAAA9999A';
              return null;
            },
          ),
          const SizedBox(),
        ),
      ],
    );
  }

  // ─── SECTION 2: Address ──────────────────────────────────────────────────
  Widget _buildSection2() {
    final filteredAddresses = _filteredAddresses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dropdown<Map<String, dynamic>>(
          'Plant *',
          _selectedPlant,
          _plants
              .map(
                (p) => DropdownMenuItem(
                  value: p,
                  child: Text(
                    '${p['name']} (${p['location'] ?? ''})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          _handlePlantChanged,
          required: true,
        ),
        _gap(),
        _dropdown<Map<String, dynamic>>(
          'Local / Office Address *',
          _selectedAddress,
          filteredAddresses
              .map(
                (a) => DropdownMenuItem(
                  value: a,
                  child: Text(
                    a['label']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          (v) {
            setState(() => _selectedAddress = v);
            _applyOfficeAddressToPermanent(v);
            _scheduleAutoSave();
          },
          required: true,
        ),
        if (_selectedPlant == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Select Plant first to load Local Address.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
        _gap(),
        _field(
          'Permanent Address *',
          _permAddrCtrl,
          formatters: [CamelCaseInputFormatter()],
          hint: 'Flat / Street / Village / City',
          maxLines: 2,
          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
        ),
        _gap(),
        _row2(
          _field(
            'State *',
            _statePCtrl,
            hint: 'e.g., Haryana',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          _field(
            'Pincode *',
            _pincodePCtrl,
            keyboard: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            hint: '6-digit PIN',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
        ),
        _gap(),
        _dropdown<String>(
          'Marital Status *',
          _maritalStatus.isEmpty ? null : _maritalStatus,
          ['Married', 'Single']
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, style: GoogleFonts.poppins(fontSize: 13)),
                ),
              )
              .toList(),
          (v) {
            setState(() => _maritalStatus = v ?? '');
            _scheduleAutoSave();
          },
          required: true,
        ),
      ],
    );
  }

  // ─── SECTION 3: Employment ───────────────────────────────────────────────
  Widget _buildSection3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row2(
          _dropdown<String>(
            'Status',
            _empStatus,
            ['Active', 'In-Active']
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                )
                .toList(),
            (v) {
              setState(() => _empStatus = v ?? 'Active');
              _scheduleAutoSave();
            },
          ),
          _dropdown<String>(
            'Role *',
            _role.isEmpty ? null : _role,
            ['driver', 'helper', 'supervisor']
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(
                      r[0].toUpperCase() + r.substring(1),
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            (v) {
              setState(() => _role = v ?? '');
              _scheduleAutoSave();
            },
            required: true,
          ),
        ),
        _gap(),
        _row2(
          _datePickerField('Date of Joining *', _joinDate, () async {
            final d = await _pickDate(initial: _joinDate, help: 'Joining Date');
            if (d != null) {
              setState(() => _joinDate = d);
              _scheduleAutoSave();
            }
          }),
          _field(
            'Salary *',
            _salaryCtrl,
            keyboard: TextInputType.number,
            hint: 'e.g. 12000',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
        ),
      ],
    );
  }

  // ─── SECTION 4: Licenses ──────────────────────────────────────────────────
  Widget _buildSection4() {
    final isHelper = _role.toLowerCase() == 'helper';
    final children = <Widget>[];
    if (isHelper) {
      children.add(
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Licenses & Certificates are Not Applicable for Helpers.',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      children.add(_gap());
    } else {
      children.addAll([
        _row2(
          _field(
            'DL Number${_role.toLowerCase() != 'helper' ? ' *' : ''}',
            _dlNoCtrl,
            formatters: [UpperCaseInputFormatter()],
            hint: 'License number',
            validator: _role.toLowerCase() != 'helper'
                ? (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null
                : null,
          ),
          _datePickerField(
            'DL Issue Date${_role.toLowerCase() != 'helper' ? ' *' : ''}',
            _dlIssueDate,
            () async {
              final d = await _pickDate(initial: _dlIssueDate);
              if (d != null) {
                setState(() {
                  _dlIssueDate = d;
                  _updateDlExperienceFromIssueDate();
                });
                _scheduleAutoSave();
              }
            },
          ),
        ),
        _gap(),
        _row2(
          _datePickerField(
            'DL Expiry Date${_role.toLowerCase() != 'helper' ? ' *' : ''}',
            _dlExpiry,
            () async {
              final d = await _pickDate(initial: _dlExpiry);
              if (d != null) setState(() => _dlExpiry = d);
            },
          ),
          _field(
            'DL Experience',
            _dlExpCtrl,
            readOnly: true,
            hint: 'Auto from issue date',
          ),
        ),
        _gap(),
        _field(
          'DL Address${_role.toLowerCase() != 'helper' ? ' *' : ''}',
          _dlAddrCtrl,
          formatters: [CamelCaseInputFormatter()],
          hint: 'Address as per DL',
          maxLines: 2,
          validator: _role.toLowerCase() != 'helper'
              ? (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null
              : null,
        ),
        _gap(),
        _row2(
          _field('IRTE Cert No.', _irteCtrl, hint: 'IRTE certificate'),
          _datePickerField('IRTE Expiry', _irteExpiry, () async {
            final d = await _pickDate(initial: _irteExpiry);
            if (d != null) setState(() => _irteExpiry = d);
          }),
        ),
        _gap(),
        _row2(
          _field('Hazard License No.', _hazardCtrl, hint: 'Hazard certificate'),
          _datePickerField('Hazard Expiry', _hazardExpiry, () async {
            final d = await _pickDate(initial: _hazardExpiry);
            if (d != null) setState(() => _hazardExpiry = d);
          }),
        ),
        _gap(),
        _datePickerField('Medical Expiry', _medicalExpiry, () async {
          final d = await _pickDate(initial: _medicalExpiry);
          if (d != null) setState(() => _medicalExpiry = d);
        }),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildSection10() {
    return _buildDocumentUploadSection();
  }

  // ─── SECTION 5: Bank, Nominee, Statutory ─────────────────────────────────
  Widget _buildSection5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          'Nominee Name *',
          _nomineeCtrl,
          formatters: [CamelCaseInputFormatter()],
          hint: 'Defaults to Father Name',
          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
        ),
        _gap(),
        _row2(
          _dropdown<String>(
            'Relation (Nominee) *',
            _nomineeRelation.isEmpty ? null : _nomineeRelation,
            [
                  'Father',
                  'Mother',
                  'Spouse',
                  'Son',
                  'Daughter',
                  'Brother',
                  'Sister',
                  'Other',
                ]
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(r, style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                )
                .toList(),
            (v) => setState(() => _nomineeRelation = v ?? ''),
            required: true,
          ),
          _field(
            'Nominee Contact',
            _nomineePhCtrl,
            keyboard: TextInputType.phone,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            hint: '10-digit mobile',
            validator: (v) {
              final digits = (v ?? '').trim();
              if (digits.isEmpty) return null;
              if (digits.length != 10) return 'Enter 10 digits';
              return null;
            },
          ),
        ),
        _gap(),
        _row2(
          _field(
            'IFSC Code *',
            _ifscCtrl,
            formatters: [UpperCaseInputFormatter()],
            hint: 'e.g., SBIN0001234',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          _field(
            'Account No. *',
            _accountCtrl,
            keyboard: TextInputType.number,
            hint: 'Bank account number',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
        ),
        _gap(),
        _dropdown<String>(
          'Bank Branch *',
          _selectedBank.isEmpty ? null : _selectedBank,
          _banks
              .map(
                (b) => DropdownMenuItem(
                  value: b,
                  child: Text(b, style: GoogleFonts.poppins(fontSize: 12)),
                ),
              )
              .toList(),
          (v) => setState(() => _selectedBank = v ?? ''),
          required: true,
        ),
        _gap(),
        _row2(
          _field('ESI Number', _esiCtrl, hint: 'ESI number'),
          _field('UAN Number', _uanCtrl, hint: 'UAN number'),
        ),
      ],
    );
  }

  // ─── SECTION 6: Reference ─────────────────────────────────────────────────
  Widget _buildSection6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row2(
          _field(
            'Father First Name *',
            _fatherFirstCtrl,
            formatters: [CamelCaseInputFormatter()],
            hint: 'Father first name',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          _field(
            'Father Last Name *',
            _fatherLastCtrl,
            formatters: [CamelCaseInputFormatter()],
            hint: 'Father last name',
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
        ),
        _gap(),
        _field(
          'Reference Name',
          _refNameCtrl,
          formatters: [CamelCaseInputFormatter()],
          hint: 'Additional contact person',
        ),
        _gap(),
        _row2(
          _dropdown<String>(
            'Relation',
            _refRelation.isEmpty ? null : _refRelation,
            [
                  'Father',
                  'Mother',
                  'Spouse',
                  'Son',
                  'Daughter',
                  'Brother',
                  'Sister',
                  'Other',
                  'Friend',
                  'Colleague',
                ]
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(r, style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                )
                .toList(),
            (v) => setState(() => _refRelation = v ?? ''),
          ),
          _field(
            'Contact',
            _refContactCtrl,
            keyboard: TextInputType.phone,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            hint: '10-digit mobile',
            validator: (v) {
              final digits = (v ?? '').trim();
              if (digits.isEmpty) return null;
              if (digits.length != 10) return 'Enter 10 digits';
              return null;
            },
          ),
        ),
      ],
    );
  }

  // ─── SECTION 7: Work Experience ───────────────────────────────────────────
  Widget _buildSection7() {
    Widget expEntry(
      String label,
      TextEditingController ctrl,
      DateTime? start,
      DateTime? end,
      VoidCallback onStart,
      VoidCallback onEnd,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _navyLight,
            ),
          ),
          const SizedBox(height: 6),
          _field(
            'Company',
            ctrl,
            formatters: [CamelCaseInputFormatter()],
            hint: 'Company name',
          ),
          const SizedBox(height: 8),
          _row2(
            _datePickerField('Start Date', start, onStart),
            _datePickerField('End Date', end, onEnd),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        expEntry(
          'Experience 1',
          _exp1CompCtrl,
          _exp1Start,
          _exp1End,
          () async {
            final d = await _pickDate(initial: _exp1Start);
            if (d != null) setState(() => _exp1Start = d);
          },
          () async {
            final d = await _pickDate(initial: _exp1End);
            if (d != null) setState(() => _exp1End = d);
          },
        ),
        _gap(),
        const Divider(),
        _gap(),
        expEntry(
          'Experience 2',
          _exp2CompCtrl,
          _exp2Start,
          _exp2End,
          () async {
            final d = await _pickDate(initial: _exp2Start);
            if (d != null) setState(() => _exp2Start = d);
          },
          () async {
            final d = await _pickDate(initial: _exp2End);
            if (d != null) setState(() => _exp2End = d);
          },
        ),
        _gap(),
        const Divider(),
        _gap(),
        expEntry(
          'Experience 3',
          _exp3CompCtrl,
          _exp3Start,
          _exp3End,
          () async {
            final d = await _pickDate(initial: _exp3Start);
            if (d != null) setState(() => _exp3Start = d);
          },
          () async {
            final d = await _pickDate(initial: _exp3End);
            if (d != null) setState(() => _exp3End = d);
          },
        ),
      ],
    );
  }

  // ─── SECTION 8: Uniform ───────────────────────────────────────────────────
  Widget _buildSection8() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row2(
          _field(
            'Pant Size',
            _pantSzCtrl,
            keyboard: TextInputType.number,
            hint: 'e.g. 32',
          ),
          _datePickerField('Pant Issue Date', _pantDate, () async {
            final d = await _pickDate(initial: _pantDate);
            if (d != null) setState(() => _pantDate = d);
          }),
        ),
        _gap(),
        _row2(
          _field(
            'Shirt Size',
            _shirtSzCtrl,
            keyboard: TextInputType.number,
            hint: 'e.g. 38',
          ),
          _datePickerField('Shirt Issue Date', _shirtDate, () async {
            final d = await _pickDate(initial: _shirtDate);
            if (d != null) setState(() => _shirtDate = d);
          }),
        ),
        _gap(),
        _row2(
          _field(
            'Shoe Size',
            _shoesSzCtrl,
            keyboard: TextInputType.number,
            hint: 'e.g. 8',
          ),
          _datePickerField('Shoes Issue Date', _shoesDate, () async {
            final d = await _pickDate(initial: _shoesDate);
            if (d != null) setState(() => _shoesDate = d);
          }),
        ),
      ],
    );
  }

  // ─── SECTION 9: Miscellaneous ─────────────────────────────────────────────
  Widget _buildSection9() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          'Bulk / PGP (auto from Plant)',
          _bulkPgpCtrl,
          readOnly: true,
          hint: 'Auto from plant',
        ),
        _gap(),
        _row2(
          _field(
            'Company',
            _companyCtrl,
            formatters: [CamelCaseInputFormatter()],
            hint: 'Company name',
          ),
          _field('Location', _locationCtrl, hint: 'Job location'),
        ),
      ],
    );
  }

  // ─── Submit Button ────────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _saving ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _saving
                ? [Colors.grey.shade400, Colors.grey.shade500]
                : [const Color(0xFF1A237E), _accent],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _saving
              ? []
              : [
                  BoxShadow(
                    color: _accent.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_saving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(
                Icons.how_to_reg_rounded,
                color: Colors.white,
                size: 22,
              ),
            const SizedBox(width: 10),
            Text(
              _saving ? 'Creating...' : 'Create Account',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarPickerDialog extends StatefulWidget {
  const _CalendarPickerDialog({
    this.title,
    required this.initialDate,
    required this.firstDay,
    required this.lastDay,
  });

  final String? title;
  final DateTime initialDate;
  final DateTime firstDay;
  final DateTime lastDay;

  @override
  State<_CalendarPickerDialog> createState() => _CalendarPickerDialogState();
}

class _CalendarPickerDialogState extends State<_CalendarPickerDialog> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  List<int> get _years => [
    for (var year = widget.firstDay.year; year <= widget.lastDay.year; year++)
      year,
  ];

  List<int> get _months {
    final startMonth = _focusedDay.year == widget.firstDay.year
        ? widget.firstDay.month
        : 1;
    final endMonth = _focusedDay.year == widget.lastDay.year
        ? widget.lastDay.month
        : 12;
    return [for (var month = startMonth; month <= endMonth; month++) month];
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = DateUtils.dateOnly(widget.initialDate);
    _focusedDay = _selectedDay;
  }

  DateTime _clampToRange(DateTime value) {
    final day = DateUtils.dateOnly(value);
    if (day.isBefore(widget.firstDay)) return widget.firstDay;
    if (day.isAfter(widget.lastDay)) return widget.lastDay;
    return day;
  }

  DateTime _safeDate(int year, int month, int day) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final safeDay = day.clamp(1, lastDayOfMonth).toInt();
    return _clampToRange(DateTime(year, month, safeDay));
  }

  bool _isWithinRange(DateTime value) {
    final day = DateUtils.dateOnly(value);
    return !day.isBefore(widget.firstDay) && !day.isAfter(widget.lastDay);
  }

  List<DateTime?> get _calendarCells {
    final firstOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final leadingBlanks = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      0,
    ).day;

    final cells = <DateTime?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var day = 1; day <= daysInMonth; day++)
        DateTime(_focusedDay.year, _focusedDay.month, day),
    ];

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return cells;
  }

  void _changeMonth(int offset) {
    final updated = _safeDate(
      _focusedDay.year,
      _focusedDay.month + offset,
      _selectedDay.day,
    );
    setState(() => _focusedDay = updated);
  }

  Widget _pickerChip({
    required int value,
    required List<int> values,
    required ValueChanged<int?> onChanged,
    required String Function(int value) labelBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          icon: const Icon(Icons.unfold_more_rounded, color: _navy, size: 18),
          borderRadius: BorderRadius.circular(16),
          dropdownColor: Colors.white,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
          onChanged: onChanged,
          items: values
              .map(
                (item) => DropdownMenuItem<int>(
                  value: item,
                  child: Text(labelBuilder(item)),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        width: screenWidth > 420 ? 390 : double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _navy.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((widget.title ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title!.trim(),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                ),
              ),
            Container(
              margin: EdgeInsets.fromLTRB(
                0,
                (widget.title ?? '').trim().isNotEmpty ? 12 : 0,
                0,
                0,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: const BoxDecoration(
                color: _calendarBlue,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  _CalendarArrowButton(
                    icon: Icons.chevron_left_rounded,
                    onTap:
                        _focusedDay.year == widget.firstDay.year &&
                            _focusedDay.month == widget.firstDay.month
                        ? null
                        : () => _changeMonth(-1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _pickerChip(
                            value: _focusedDay.month,
                            values: _months,
                            onChanged: (month) {
                              if (month == null) return;
                              setState(() {
                                _focusedDay = _safeDate(
                                  _focusedDay.year,
                                  month,
                                  _selectedDay.day,
                                );
                              });
                            },
                            labelBuilder: (month) =>
                                DateFormat.MMM().format(DateTime(2000, month)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickerChip(
                            value: _focusedDay.year,
                            values: _years,
                            onChanged: (year) {
                              if (year == null) return;
                              setState(() {
                                _focusedDay = _safeDate(
                                  year,
                                  _focusedDay.month,
                                  _selectedDay.day,
                                );
                              });
                            },
                            labelBuilder: (year) => year.toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CalendarArrowButton(
                    icon: Icons.chevron_right_rounded,
                    onTap:
                        _focusedDay.year == widget.lastDay.year &&
                            _focusedDay.month == widget.lastDay.month
                        ? null
                        : () => _changeMonth(1),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Expanded(child: _CalendarWeekday(label: 'Su')),
                      Expanded(child: _CalendarWeekday(label: 'Mo')),
                      Expanded(child: _CalendarWeekday(label: 'Tu')),
                      Expanded(child: _CalendarWeekday(label: 'We')),
                      Expanded(child: _CalendarWeekday(label: 'Th')),
                      Expanded(child: _CalendarWeekday(label: 'Fr')),
                      Expanded(child: _CalendarWeekday(label: 'Sa')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _calendarCells.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1.08,
                        ),
                    itemBuilder: (context, index) {
                      final date = _calendarCells[index];
                      if (date == null) return const SizedBox.shrink();

                      final normalizedDate = DateUtils.dateOnly(date);
                      final isSelected = normalizedDate == _selectedDay;
                      final isToday =
                          normalizedDate == DateUtils.dateOnly(DateTime.now());
                      final isEnabled = _isWithinRange(normalizedDate);

                      return _CalendarDayCell(
                        day: normalizedDate.day,
                        isSelected: isSelected,
                        isToday: isToday,
                        isEnabled: isEnabled,
                        onTap: !isEnabled
                            ? null
                            : () {
                                setState(() {
                                  _selectedDay = normalizedDate;
                                  _focusedDay = normalizedDate;
                                });
                              },
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_selectedDay),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _calendarBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(_selectedDay),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarWeekday extends StatelessWidget {
  const _CalendarWeekday({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isEnabled,
    required this.onTap,
  });

  final int day;
  final bool isSelected;
  final bool isToday;
  final bool isEnabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? _calendarBlue
        : isToday
        ? _calendarBlue
        : _calendarBlue.withOpacity(0.75);
    final textColor = !isEnabled
        ? Colors.grey.shade300
        : isSelected
        ? Colors.white
        : const Color(0xFF4B5563);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? _calendarBlue
              : (isToday ? _calendarBlue.withOpacity(0.08) : Colors.white),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor,
            width: isToday && !isSelected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          day.toString(),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: isSelected || isToday
                ? FontWeight.w700
                : FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _CalendarArrowButton extends StatelessWidget {
  const _CalendarArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _calendarBlue, size: 22),
        ),
      ),
    );
  }
}

class CamelCaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final words = newValue.text.toLowerCase().split(' ');
    for (var i = 0; i < words.length; i++) {
      if (words[i].isNotEmpty) {
        words[i] = words[i][0].toUpperCase() + words[i].substring(1);
      }
    }
    final formatted = words.join(' ');

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class UpperCaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = newValue.text.toUpperCase();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AadhaarInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final trimmed = digits.length > 12 ? digits.substring(0, 12) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(trimmed[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PanInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = newValue.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final trimmed = formatted.length > 10
        ? formatted.substring(0, 10)
        : formatted;

    return TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }
}
