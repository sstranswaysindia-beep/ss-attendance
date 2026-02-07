import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
    final isHelper = (_user.driverRole?.toLowerCase().trim() ?? '') == 'helper';
    final theme = Theme.of(context);
    final contactNumber = _user.contactNumber?.trim();

    String formatDate(String? raw) {
      if (raw == null || raw.trim().isEmpty) {
        return 'Not provided';
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) {
        return raw;
      }
      return '${parsed.day.toString().padLeft(2, '0')} '
          '${_monthLabel(parsed.month)} ${parsed.year}';
    }

    String licenseStatusLabel(String? validityRaw) {
      if (validityRaw == null || validityRaw.trim().isEmpty) {
        return 'Validity not set';
      }
      final parsed = DateTime.tryParse(validityRaw);
      if (parsed == null) {
        return 'Validity not set';
      }
      final today = DateTime.now();
      final normalizedToday = DateTime(today.year, today.month, today.day);
      if (parsed.isBefore(normalizedToday)) {
        return 'Expired';
      }
      return 'Valid';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isHelper ? 'Helper Profile' : 'Driver Profile'),
      ),
      body: AppGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileHeaderCard(
                user: _user,
                isUploading: _isUploadingPhoto,
                onPhotoSelected: _handlePhotoSelected,
              ),
              const SizedBox(height: 16),
              _ProfileSectionCard(
                title: 'Key Information',
                icon: Icons.badge_outlined,
                child: Column(
                  children: [
                    _ProfileInfoRow(
                      label: 'Employee ID',
                      value: _user.employeeId ?? 'Not assigned',
                    ),
                    _ProfileInfoRow(label: 'Plant', value: plantLabel),
                    _ProfileInfoRow(
                      label: 'Vehicle Number',
                      value: _user.vehicleNumber ?? 'Not assigned',
                    ),
                    _ProfileInfoRow(
                      label: 'Father\'s Name',
                      value: _user.fatherName ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Aadhaar',
                      value: _user.aadhaar ?? 'Not provided',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ProfileSectionCard(
                title: 'Contact & Address',
                icon: Icons.contact_phone_outlined,
                child: Column(
                  children: [
                    _ProfileInfoRow(
                      label: 'Contact Number',
                      value: contactNumber?.isNotEmpty == true
                          ? contactNumber!
                          : 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Address',
                      value: _user.address ?? 'Not provided',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ProfileSectionCard(
                title: 'License Details',
                icon: Icons.credit_card_outlined,
                child: Column(
                  children: [
                    _ProfileInfoRow(
                      label: 'DL Number',
                      value: _user.dlNumber ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Issue Date',
                      value: formatDate(_user.dlIssueDate),
                    ),
                    _ProfileInfoRow(
                      label: 'Validity',
                      value: formatDate(_user.dlValidity),
                      valueColor:
                          licenseStatusLabel(_user.dlValidity) == 'Expired'
                              ? theme.colorScheme.error
                              : Colors.green.shade700,
                      trailing: Text(
                        licenseStatusLabel(_user.dlValidity),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              licenseStatusLabel(_user.dlValidity) == 'Expired'
                              ? theme.colorScheme.error
                              : Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ProfileSectionCard(
                title: 'Nominee Details',
                icon: Icons.group_outlined,
                child: Column(
                  children: [
                    _ProfileInfoRow(
                      label: 'Nominee Name',
                      value: _user.nomineeName ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Relation',
                      value: _user.nomineeRelation ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Nominee Contact',
                      value: _user.nomineeContact ?? 'Not provided',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ProfileSectionCard(
                title: 'Bank & Compliance',
                icon: Icons.account_balance_outlined,
                child: Column(
                  children: [
                    _ProfileInfoRow(
                      label: 'ESI Number',
                      value: _user.esiNumber ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'UAN Number',
                      value: _user.uanNumber ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'IFSC Code',
                      value: _user.ifscCode != null
                          ? _user.ifscVerified == true
                                ? '${_user.ifscCode} (Verified)'
                                : '${_user.ifscCode} (Pending verification)'
                          : 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Bank Account',
                      value: _user.bankAccount ?? 'Not provided',
                    ),
                    _ProfileInfoRow(
                      label: 'Branch Name',
                      value: _user.branchName ?? 'Not provided',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _monthLabel(int month) {
  const labels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final index = (month - 1).clamp(0, 11).toInt();
  return labels[index];
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.user,
    required this.isUploading,
    required this.onPhotoSelected,
  });

  final AppUser user;
  final bool isUploading;
  final Future<void> Function(File file) onPhotoSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plantLabel = user.plantName ?? user.plantId ?? 'Not mapped';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.12),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          ProfilePhotoWithUpload(
            user: user,
            radius: 52,
            onPhotoSelected: onPhotoSelected,
            isUploading: isUploading,
            showBorder: true,
            borderColor: theme.colorScheme.primary,
            borderWidth: 3,
          ),
          const SizedBox(height: 12),
          Text(
            user.displayName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Employee ID: ${user.employeeId ?? 'Not assigned'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Plant: $plantLabel',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Vehicle: ${user.vehicleNumber ?? 'Not assigned'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the camera icon to update your profile photo',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
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
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor ?? Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
