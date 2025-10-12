import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePhotoWidget extends StatelessWidget {
  const ProfilePhotoWidget({
    required this.user,
    this.radius = 24,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
    super.key,
  });

  final dynamic user; // AppUser or any object with displayName and profilePhoto
  final double radius;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = this.borderColor ?? theme.colorScheme.primary;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
      child: _buildProfileImage(theme),
    );

    if (showBorder) {
      avatar = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: avatar,
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }

    return avatar;
  }

  Widget _buildProfileImage(ThemeData theme) {
    final profilePhoto = user.profilePhoto;
    print(
      'ProfilePhotoWidget: Building image with profilePhoto: $profilePhoto',
    );

    if (profilePhoto == null || profilePhoto.isEmpty) {
      print('ProfilePhotoWidget: No profile photo, showing initials');
      return Text(
        _getInitials(),
        style: TextStyle(
          fontSize: radius * 0.6,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: _buildImageUrl(profilePhoto),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: theme.colorScheme.primary.withOpacity(0.1),
          child: Center(
            child: SizedBox(
              width: radius * 0.5,
              height: radius * 0.5,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Text(
          _getInitials(),
          style: TextStyle(
            fontSize: radius * 0.6,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  String _getInitials() {
    final displayName = user.displayName ?? '';
    if (displayName.isEmpty) return '?';

    final words = displayName.trim().split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }

    return '${words[0][0]}${words[words.length - 1][0]}'.toUpperCase();
  }

  String _buildImageUrl(String? path) {
    if (path == null || path.isEmpty) {
      print('ProfilePhotoWidget: No path provided, using placeholder');
      return 'https://placehold.co/200x200';
    }

    if (path.startsWith('http')) {
      print('ProfilePhotoWidget: Using full URL: $path');
      return path;
    }

    final fullUrl = 'https://sstranswaysindia.com$path';
    print('ProfilePhotoWidget: Built full URL: $fullUrl');
    return fullUrl;
  }
}

class ProfilePhotoWithUpload extends StatefulWidget {
  const ProfilePhotoWithUpload({
    required this.user,
    required this.onPhotoSelected,
    this.radius = 24,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
    this.isUploading = false,
    super.key,
  });

  final dynamic user;
  final Function(File) onPhotoSelected;
  final double radius;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  final bool isUploading;

  @override
  State<ProfilePhotoWithUpload> createState() => _ProfilePhotoWithUploadState();
}

class _ProfilePhotoWithUploadState extends State<ProfilePhotoWithUpload> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ProfilePhotoWidget(
          user: widget.user,
          radius: widget.radius,
          onTap: widget.isUploading ? null : _showPhotoSourcePicker,
          showBorder: widget.showBorder,
          borderColor: widget.borderColor,
          borderWidth: widget.borderWidth,
        ),
        if (widget.isUploading)
          Container(
            width: widget.radius * 2,
            height: widget.radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.5),
            ),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        if (!widget.isUploading)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.camera_alt,
                size: widget.radius * 0.4,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
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

    if (source == null) return;

    final picker = ImagePicker();
    try {
      final xFile = await picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );

      if (xFile != null) {
        final file = File(xFile.path);
        widget.onPhotoSelected(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to capture photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
