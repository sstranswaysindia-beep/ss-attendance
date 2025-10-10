import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageUtils {
  static Future<Uint8List?> compressImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Resize image to max 800x800 while maintaining aspect ratio
      final resizedImage = img.copyResize(
        image,
        width: image.width > image.height ? 800 : null,
        height: image.height > image.width ? 800 : null,
        maintainAspect: true,
      );

      // Compress as JPEG with 85% quality
      final compressedBytes = img.encodeJpg(resizedImage, quality: 85);
      return Uint8List.fromList(compressedBytes);
    } catch (e) {
      print('Error compressing image: $e');
      return null;
    }
  }

  static Future<File?> saveCompressedImage(
    String originalPath,
    String outputPath,
  ) async {
    try {
      final compressedBytes = await compressImage(originalPath);
      if (compressedBytes == null) return null;

      final file = File(outputPath);
      await file.writeAsBytes(compressedBytes);
      return file;
    } catch (e) {
      print('Error saving compressed image: $e');
      return null;
    }
  }

  static Future<int> getImageFileSize(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (e) {
      print('Error getting file size: $e');
      return 0;
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}



