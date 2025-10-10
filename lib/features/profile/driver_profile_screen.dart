import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/app_user.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool _isUploadingPhoto = false;
  final ProfileRepository _profileRepository = ProfileRepository();
  late AppUser _user;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  Future<void> _handlePhotoSelected(File file) async {
    await _uploadProfilePhoto(file);
  }

  Future<void> _uploadProfilePhoto(File file) async {
    final driverId = _user.driverId;
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

      setState(() {
        _user.profilePhoto = url;
      });
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
    final plantLabel = _user.plantName ?? _user.plantId ?? 'Not mapped';

    final keyInfoFields = [
      _ProfileField(
        label: 'Employee ID',
        value: _user.employeeId ?? 'Not assigned',
      ),
      _ProfileField(label: 'Plant', value: plantLabel),
      _ProfileField(
        label: 'Vehicle Number',
        value: _user.vehicleNumber ?? 'Not assigned',
      ),
      _ProfileField(
        label: 'Father\'s Name',
        value: _user.fatherName ?? 'Not provided',
      ),
      _ProfileField(label: 'Aadhaar', value: _user.aadhaar ?? 'Not provided'),
    ];

    final editableFields = [
      const _ProfileField(label: 'Contact Number', value: '+91 98765 43210'),
      const _ProfileField(label: 'Email', value: 'driver@example.com'),
      _ProfileField(label: 'Address', value: _user.address ?? 'Not provided'),
    ];

    final complianceFields = [
      _ProfileField(
        label: 'ESI Number',
        value: _user.esiNumber ?? 'Not provided',
      ),
      _ProfileField(
        label: 'UAN Number',
        value: _user.uanNumber ?? 'Not provided',
      ),
      _ProfileField(
        label: 'IFSC Code',
        value: _user.ifscCode != null
            ? _user.ifscVerified == true
                  ? '${_user.ifscCode} (Verified)'
                  : '${_user.ifscCode} (Pending verification)'
            : 'Not provided',
      ),
      _ProfileField(
        label: 'Bank Account',
        value: _user.bankAccount ?? 'Not provided',
      ),
      _ProfileField(
        label: 'Branch Name',
        value: _user.branchName ?? 'Not provided',
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
                    ProfilePhotoWithUpload(
                      user: _user,
                      radius: 56,
                      onPhotoSelected: _handlePhotoSelected,
                      isUploading: _isUploadingPhoto,
                      showBorder: true,
                      borderColor: Theme.of(context).colorScheme.primary,
                      borderWidth: 3,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap the camera icon to update your profile photo',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _user.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Employee ID: ${_user.employeeId ?? 'Not assigned'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Plant: $plantLabel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Vehicle: ${_user.vehicleNumber ?? 'Not assigned'}',
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
