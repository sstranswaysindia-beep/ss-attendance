import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/models/app_user.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';

class SupervisorProfileScreen extends StatefulWidget {
  const SupervisorProfileScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<SupervisorProfileScreen> createState() =>
      _SupervisorProfileScreenState();
}

class _SupervisorProfileScreenState extends State<SupervisorProfileScreen> {
  bool _isUploadingPhoto = false;
  bool _isLoadingProfile = true;
  final ProfileRepository _profileRepository = ProfileRepository();
  late AppUser _user;

  // User profile data from users table
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_user_profile.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _user.id}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok') {
          setState(() {
            _userProfile = data['profile'] as Map<String, dynamic>;
            // Update user's profile photo from API response
            final profilePhoto = _userProfile?['profile_photo']?.toString();
            print(
              'SupervisorProfileScreen: Profile photo from API: $profilePhoto',
            );
            if (profilePhoto != null && profilePhoto.isNotEmpty) {
              _user.profilePhoto = profilePhoto;
              print(
                'SupervisorProfileScreen: Set user profile photo to: ${_user.profilePhoto}',
              );
            } else {
              print(
                'SupervisorProfileScreen: No profile photo found in API response',
              );
            }
            _isLoadingProfile = false;
          });
        } else {
          throw Exception(data['error'] ?? 'Failed to fetch profile');
        }
      } else {
        throw Exception('Failed to fetch profile: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
      });
      if (mounted) {
        showAppToast(context, 'Failed to load profile data', isError: true);
      }
    }
  }

  Future<void> _handlePhotoSelected(File file) async {
    // For supervisors without driver_id, we'll need to handle photo upload differently
    // For now, we'll use the user ID directly
    await _uploadProfilePhoto(file);
  }

  Future<void> _uploadProfilePhoto(File file) async {
    // For supervisors without driver_id, use user ID instead of driver ID
    final userId = _user.id;

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await _profileRepository.uploadUserProfilePhoto(
        userId: userId,
        file: file,
      );

      if (!mounted) return;

      // Update the user's profile photo URL
      setState(() {
        _user.profilePhoto = url;
      });

      showAppToast(context, 'Profile photo updated successfully!');

      // Refresh profile data to ensure consistency
      await _fetchUserProfile();
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (error) {
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
    if (_isLoadingProfile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Supervisor Profile'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Get supervised plants information
    final supervisedPlants =
        _userProfile?['supervised_plants'] as List<dynamic>? ?? [];
    final supervisedPlantsText = supervisedPlants.isNotEmpty
        ? supervisedPlants
              .map((plant) => plant['plant_name'] as String)
              .join(', ')
        : 'No plants assigned';

    // Format dates
    String formatDate(String? dateString) {
      if (dateString == null || dateString.isEmpty) return 'Not available';
      try {
        final date = DateTime.parse(dateString);
        return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
      } catch (e) {
        return 'Invalid date';
      }
    }

    final keyInfoFields = [
      _ProfileField(
        label: 'User ID',
        value: _userProfile?['id']?.toString() ?? _user.id,
      ),
      _ProfileField(
        label: 'Username',
        value: _userProfile?['username']?.toString() ?? 'Not available',
      ),
      _ProfileField(
        label: 'Role',
        value: (_userProfile?['role']?.toString() ?? _user.role.name)
            .toUpperCase(),
      ),
      _ProfileField(label: 'Supervised Plants', value: supervisedPlantsText),
    ];

    // Fields from users table that supervisors without driver_id should have
    final personalFields = [
      _ProfileField(
        label: 'Full Name',
        value: _userProfile?['full_name']?.toString() ?? 'Not provided',
      ),
      _ProfileField(
        label: 'Email',
        value: _userProfile?['email']?.toString() ?? 'Not provided',
      ),
      _ProfileField(
        label: 'Phone',
        value: _userProfile?['phone']?.toString() ?? 'Not provided',
      ),
    ];

    final systemFields = [
      _ProfileField(
        label: 'Account Created',
        value: formatDate(_userProfile?['created_at']?.toString()),
      ),
      _ProfileField(
        label: 'Last Login',
        value: formatDate(_userProfile?['last_login_at']?.toString()),
      ),
      _ProfileField(
        label: 'Password Status',
        value: (_userProfile?['must_change_password'] == true)
            ? 'Must Change'
            : 'Active',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
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
                'Supervisor ID: ${_user.id}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Plants: $supervisedPlantsText',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Account Information',
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
              ...personalFields.map(
                (field) => _ProfileFieldTile(field: field, readOnly: true),
              ),
              const SizedBox(height: 16),
              Text(
                'System Information',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...systemFields.map(
                (field) => _ProfileFieldTile(field: field, readOnly: true),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Supervisor Account',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This is a supervisor account without driver mapping. Profile information is managed through the users table. Contact your administrator for profile updates.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
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
