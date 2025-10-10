import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SafeProfileImageWidget extends StatelessWidget {
  const SafeProfileImageWidget({
    super.key,
    required this.profilePhotoUrl,
    required this.radius,
    this.backgroundColor,
    this.child,
  });

  final String? profilePhotoUrl;
  final double radius;
  final Color? backgroundColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey.shade300,
      child: child ?? _buildProfileImage(),
    );
  }

  Widget _buildProfileImage() {
    if (profilePhotoUrl == null || profilePhotoUrl!.isEmpty) {
      return Icon(Icons.person, size: radius, color: Colors.grey.shade600);
    }

    // Check if it's a local file path
    if (profilePhotoUrl!.startsWith('/') ||
        profilePhotoUrl!.startsWith('file://')) {
      return ClipOval(
        child: Image.file(
          File(profilePhotoUrl!.replaceFirst('file://', '')),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.person,
              size: radius,
              color: Colors.grey.shade600,
            );
          },
        ),
      );
    }

    // Network image
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: profilePhotoUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: radius * 2,
          height: radius * 2,
          color: Colors.grey.shade300,
          child: Icon(Icons.person, size: radius, color: Colors.grey.shade600),
        ),
        errorWidget: (context, url, error) =>
            Icon(Icons.person, size: radius, color: Colors.grey.shade600),
      ),
    );
  }
}



