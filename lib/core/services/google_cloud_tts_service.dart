import 'dart:convert';
import 'package:http/http.dart' as http;

class GoogleCloudTtsService {
  // TODO: Replace with your actual Google Cloud API Key
  // Restrict this key to Android/iOS apps in Google Cloud Console for security.
  static const String _apiKey = 'YOUR_GOOGLE_CLOUD_API_KEY';
  static const String _url = 'https://texttospeech.googleapis.com/v1/text:synthesize';

  /// Converts text to an MP3 audio content (base64 encoded) using Google Cloud TTS.
  /// Returns the base64 audio string, or null if failed.
  static Future<String?> synthesizeText(String text, {String languageCode = 'hi-IN'}) async {
    try {
      final response = await http.post(
        Uri.parse('$_url?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'input': {'text': text},
          'voice': {
            'languageCode': languageCode,
            'ssmlGender': 'NEUTRAL' // or MALE, FEMALE
          },
          'audioConfig': {
            'audioEncoding': 'MP3'
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['audioContent'] as String?;
      } else {
        print('Cloud TTS Error: ${response.statusCode} - ${response.body}');
        return null; // Handle error gracefully
      }
    } catch (e) {
      print('Cloud TTS Exception: $e');
      return null;
    }
  }
}
