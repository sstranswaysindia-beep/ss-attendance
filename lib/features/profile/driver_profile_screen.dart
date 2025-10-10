import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/app_user.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  File? _profilePhoto;
  String? _profilePhotoUrl;
  bool _isUploadingPhoto = false;
  final ProfileRepository _profileRepository = ProfileRepository();

  @override
  void initState() {
    super.initState();
    _profilePhotoUrl = widget.user.profilePhoto;
  }

  Future<void> _captureProfilePhoto() async {
    await _showPhotoSourcePicker();
  }

  Future<void> _showPhotoSourcePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Capture with Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) {
      return;
    }

    final picker = ImagePicker();
    try {
      final xFile = await picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );

      if (xFile == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final savedPath =
          '${directory.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(xFile.path).copy(savedPath);

      setState(() => _profilePhoto = savedFile);
      await _uploadProfilePhoto(savedFile);
      if (!mounted) return;
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to capture profile photo.', isError: true);
    }
  }

  Future<void> _uploadProfilePhoto(File file) async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(
        context,
        'Driver mapping missing. Contact admin.',
        isError: true,
      );
      return;
    }

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await _profileRepository.uploadProfilePhoto(
        driverId: driverId,
        file: file,
      );
      if (!mounted) return;
      setState(() => _profilePhotoUrl = url);
      showAppToast(context, 'Profile photo updated.');
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to upload profile photo.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final plantLabel = user.plantName ?? user.plantId ?? 'Not mapped';

    final keyInfoFields = [
      _ProfileField(
        label: 'Employee ID',
        value: user.employeeId ?? 'Not assigned',
      ),
      _ProfileField(label: 'Plant', value: plantLabel),
      _ProfileField(
        label: 'Vehicle Number',
        value: user.vehicleNumber ?? 'Not assigned',
      ),
      _ProfileField(
        label: 'Father’s Name',
        value: user.fatherName ?? 'Not provided',
      ),
      _ProfileField(label: 'Aadhaar', value: user.aadhaar ?? 'Not provided'),
    ];

    final editableFields = [
      const _ProfileField(label: 'Contact Number', value: '+91 98765 43210'),
      const _ProfileField(label: 'Email', value: 'driver@example.com'),
      _ProfileField(label: 'Address', value: user.address ?? 'Not provided'),
    ];

    final complianceFields = [
      _ProfileField(
        label: 'ESI Number',
        value: user.esiNumber ?? 'Not provided',
      ),
      _ProfileField(
        label: 'UAN Number',
        value: user.uanNumber ?? 'Not provided',
      ),
      _ProfileField(
        label: 'IFSC Code',
        value: user.ifscCode != null
            ? user.ifscVerified == true
                  ? '${user.ifscCode} (Verified)'
                  : '${user.ifscCode} (Pending verification)'
            : 'Not provided',
      ),
      _ProfileField(
        label: 'Bank Account',
        value: user.bankAccount ?? 'Not provided',
      ),
      _ProfileField(
        label: 'Branch Name',
        value: user.branchName ?? 'Not provided',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Profile')),
      body: AppGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundImage: _profilePhoto != null
                              ? FileImage(_profilePhoto!)
                              : _buildNetworkImage(
                                  _profilePhotoUrl ?? user.profilePhoto,
                                ),
                        ),
                        if (_isUploadingPhoto)
                          const CircularProgressIndicator(color: Colors.white),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: _captureProfilePhoto,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Update Profile Photo'),
                    ),
                    const Text(
                      'Capture or upload a profile photo. Changes save instantly.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Employee ID: ${user.employeeId ?? 'Not assigned'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Plant: $plantLabel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Vehicle: ${user.vehicleNumber ?? 'Not assigned'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Key Information',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...keyInfoFields.map(
                (field) => _ProfileFieldTile(field: field, readOnly: true),
              ),
              const SizedBox(height: 16),
              Text(
                'Personal Details',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...editableFields.map((field) => _ProfileFieldTile(field: field)),
              const SizedBox(height: 16),
              Text(
                'Bank & Compliance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...complianceFields.map(
                (field) => _ProfileFieldTile(field: field, readOnly: true),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {},
                child: const Text('Update Personal Info'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileField {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String value;
}

class _ProfileFieldTile extends StatelessWidget {
  const _ProfileFieldTile({required this.field, this.readOnly = false});

  final _ProfileField field;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        initialValue: field.value,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: field.label,
          suffixIcon: readOnly ? const Icon(Icons.lock) : null,
        ),
      ),
    );
  }
}

ImageProvider<Object> _buildNetworkImage(String? path) {
  if (path == null || path.isEmpty) {
    return const NetworkImage('https://placehold.co/200x200');
  }
  if (path.startsWith('http')) {
    return NetworkImage(path);
  }
  return NetworkImage('https://sstranswaysindia.com$path');
}
