import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/models/app_user.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _debugData;
  String _debugText = '';

  @override
  void initState() {
    super.initState();
    _generateDebugData();
  }

  Future<void> _generateDebugData() async {
    setState(() => _isLoading = true);

    try {
      // 1. User Data
      final userData = {
        'id': widget.user.id,
        'displayName': widget.user.displayName,
        'role': widget.user.role.name,
        'driverId': widget.user.driverId,
        'plantId': widget.user.plantId,
        'plantName': widget.user.plantName,
        'profilePhoto': widget.user.profilePhoto,
      };

      // 2. API Test - Get User Profile
      String apiResponse = 'Not tested';
      String apiError = '';
      try {
        final response = await http.post(
          Uri.parse(
            'https://sstranswaysindia.com/api/mobile/get_user_profile.php',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': widget.user.id}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          apiResponse = JsonEncoder.withIndent('  ').convert(data);
        } else {
          apiError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        apiError = e.toString();
      }

      // 3. Server Debug Test
      String serverDebug = 'Not tested';
      String serverError = '';
      try {
        final response = await http.get(
          Uri.parse(
            'https://sstranswaysindia.com/api/mobile/debug_profile_photo.php?userId=${widget.user.id}',
          ),
        );

        if (response.statusCode == 200) {
          serverDebug = response.body;
        } else {
          serverError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        serverError = e.toString();
      }

      // 4. Profile Photo URL Test
      String photoTest = 'Not tested';
      String photoError = '';
      if (widget.user.profilePhoto != null &&
          widget.user.profilePhoto!.isNotEmpty) {
        try {
          final response = await http.head(
            Uri.parse(widget.user.profilePhoto!),
          );
          photoTest =
              'HTTP ${response.statusCode} - ${response.headers['content-type'] ?? 'unknown'}';
        } catch (e) {
          photoError = e.toString();
        }
      } else {
        photoError = 'No profile photo URL available';
      }

      // 5. Attendance Debug - Check for Open Attendance Records
      Map<String, dynamic> attendanceDebug = {};

      // Check for open attendance records that might cause the error
      try {
        // Direct database query simulation to check for open records
        final openAttendanceResponse = await http.post(
          Uri.parse(
            'https://sstranswaysindia.com/api/mobile/debug_open_attendance.php',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': widget.user.id,
            'driverId': widget.user.driverId,
          }),
        );

        if (openAttendanceResponse.statusCode == 200) {
          attendanceDebug['open_attendance_check'] = {
            'success': true,
            'response': openAttendanceResponse.body,
            'error': null,
          };
        } else {
          attendanceDebug['open_attendance_check'] = {
            'success': false,
            'response': null,
            'error':
                'HTTP ${openAttendanceResponse.statusCode}: ${openAttendanceResponse.body}',
          };
        }
      } catch (e) {
        attendanceDebug['open_attendance_check'] = {
          'success': false,
          'response': null,
          'error': e.toString(),
        };
      }

      // 6. PHP API Debug Log - Test All Relevant APIs
      Map<String, dynamic> apiDebugResults = {};

      // Test APIs based on user role and driver_id status
      final apisToTest = <String, Map<String, dynamic>>{
        'get_user_profile.php': {
          'method': 'POST',
          'url': 'https://sstranswaysindia.com/api/mobile/get_user_profile.php',
          'body': jsonEncode({'userId': widget.user.id}),
          'headers': {'Content-Type': 'application/json'},
        },
        'debug_profile_photo.php': {
          'method': 'GET',
          'url':
              'https://sstranswaysindia.com/api/mobile/debug_profile_photo.php?userId=${widget.user.id}',
          'body': null,
          'headers': {},
        },
        'debug_profile_upload.php': {
          'method': 'GET',
          'url':
              'https://sstranswaysindia.com/api/mobile/debug_profile_upload.php',
          'body': null,
          'headers': {},
        },

        // Attendance APIs
        'get_attendance_status.php': {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/get_attendance_status.php',
          'body': jsonEncode({'userId': widget.user.id}),
          'headers': {'Content-Type': 'application/json'},
        },
        'get_current_attendance.php': {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/get_current_attendance.php',
          'body': jsonEncode({
            'userId': widget.user.id,
            'driverId': widget.user.driverId,
          }),
          'headers': {'Content-Type': 'application/json'},
        },
        'get_attendance_history.php': {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/get_attendance_history.php',
          'body': jsonEncode({
            'userId': widget.user.id,
            'startDate': DateTime.now()
                .subtract(const Duration(days: 30))
                .toIso8601String()
                .split('T')[0],
            'endDate': DateTime.now().toIso8601String().split('T')[0],
          }),
          'headers': {'Content-Type': 'application/json'},
        },
        'attendance_approval_workflow.php': {
          'method': 'GET',
          'url':
              'https://sstranswaysindia.com/api/mobile/attendance_approval_workflow.php',
          'body': null,
          'headers': {},
        },

        // Common APIs
        'get_plants.php': {
          'method': 'GET',
          'url': 'https://sstranswaysindia.com/api/mobile/get_plants.php',
          'body': null,
          'headers': {},
        },
        'get_vehicles.php': {
          'method': 'GET',
          'url': 'https://sstranswaysindia.com/api/mobile/get_vehicles.php',
          'body': null,
          'headers': {},
        },
      };

      // Add driver-specific APIs if user has driver_id
      if (widget.user.driverId != null && widget.user.driverId!.isNotEmpty) {
        apisToTest['get_driver_profile.php'] = {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/get_driver_profile.php',
          'body': jsonEncode({'driverId': widget.user.driverId}),
          'headers': {'Content-Type': 'application/json'},
        };
      }

      // Add supervisor-specific APIs
      if (widget.user.role.name == 'supervisor') {
        apisToTest['get_supervisor_profile.php'] = {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/get_supervisor_profile.php',
          'body': jsonEncode({'userId': widget.user.id}),
          'headers': {'Content-Type': 'application/json'},
        };

        apisToTest['get_supervisor_plants.php'] = {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/get_supervisor_plants.php',
          'body': jsonEncode({'userId': widget.user.id}),
          'headers': {'Content-Type': 'application/json'},
        };

        // Test attendance with driver_id for supervisors with driver_id
        if (widget.user.driverId != null && widget.user.driverId!.isNotEmpty) {
          apisToTest['get_driver_attendance_status.php'] = {
            'method': 'POST',
            'url':
                'https://sstranswaysindia.com/api/mobile/get_attendance_status.php',
            'body': jsonEncode({'driverId': widget.user.driverId}),
            'headers': {'Content-Type': 'application/json'},
          };
        }

        // Test attendance submission API (simulation)
        apisToTest['test_attendance_submit.php'] = {
          'method': 'GET',
          'url':
              'https://sstranswaysindia.com/api/mobile/test_supervisor_attendance_fixed.php',
          'body': null,
          'headers': {},
        };

        // Test attendance check-in/check-out APIs
        apisToTest['test_attendance_checkin.php'] = {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/attendance_submit.php',
          'body': jsonEncode({
            'action': 'check_in',
            'userId': widget.user.id,
            'plantId': widget.user.plantId ?? 53,
            'vehicleId': 1,
            'assignmentId': 1,
            'notes': 'Debug test check-in',
            'source': 'debug_screen',
            'location': {
              'latitude': 22.7196,
              'longitude': 75.8577,
              'accuracy': 10.0,
              'address': 'Test Location',
            },
          }),
          'headers': {'Content-Type': 'application/json'},
        };

        apisToTest['test_attendance_checkout.php'] = {
          'method': 'POST',
          'url':
              'https://sstranswaysindia.com/api/mobile/attendance_submit.php',
          'body': jsonEncode({
            'action': 'check_out',
            'userId': widget.user.id,
            'plantId': widget.user.plantId ?? 53,
            'vehicleId': 1,
            'assignmentId': 1,
            'notes': 'Debug test check-out',
            'source': 'debug_screen',
            'location': {
              'latitude': 22.7196,
              'longitude': 75.8577,
              'accuracy': 10.0,
              'address': 'Test Location',
            },
          }),
          'headers': {'Content-Type': 'application/json'},
        };
      }

      // Test each API
      for (final entry in apisToTest.entries) {
        final apiName = entry.key;
        final apiConfig = entry.value;

        try {
          final uri = Uri.parse(apiConfig['url']);
          final headers = Map<String, String>.from(apiConfig['headers']);

          http.Response response;
          if (apiConfig['method'] == 'POST') {
            response = await http.post(
              uri,
              headers: headers,
              body: apiConfig['body'],
            );
          } else {
            response = await http.get(uri, headers: headers);
          }

          apiDebugResults[apiName] = {
            'success': true,
            'statusCode': response.statusCode,
            'headers': response.headers,
            'body': response.body,
            'error': null,
          };
        } catch (e) {
          apiDebugResults[apiName] = {
            'success': false,
            'statusCode': null,
            'headers': null,
            'body': null,
            'error': e.toString(),
          };
        }
      }

      _debugData = {
        'timestamp': DateTime.now().toIso8601String(),
        'userData': userData,
        'apiTest': {
          'success': apiError.isEmpty,
          'response': apiResponse,
          'error': apiError,
        },
        'serverDebug': {
          'success': serverError.isEmpty,
          'response': serverDebug,
          'error': serverError,
        },
        'photoTest': {
          'success': photoError.isEmpty,
          'result': photoTest,
          'error': photoError,
        },
        'attendanceDebug': attendanceDebug,
        'apiDebugResults': apiDebugResults,
      };

      _debugText = _formatDebugText(_debugData!);
    } catch (e) {
      _debugData = {
        'timestamp': DateTime.now().toIso8601String(),
        'error': e.toString(),
      };
      _debugText = 'Error generating debug data: $e';
    }

    setState(() => _isLoading = false);
  }

  String _formatDebugText(Map<String, dynamic> data) {
    final buffer = StringBuffer();

    buffer.writeln('=== PROFILE PHOTO DEBUG REPORT ===');
    buffer.writeln('Timestamp: ${data['timestamp']}');
    buffer.writeln();

    // User Data
    buffer.writeln('=== USER DATA ===');
    final userData = data['userData'] as Map<String, dynamic>? ?? {};
    userData.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    buffer.writeln();

    // API Test
    buffer.writeln('=== API TEST (get_user_profile.php) ===');
    final apiTest = data['apiTest'] as Map<String, dynamic>? ?? {};
    buffer.writeln('Success: ${apiTest['success']}');
    if (apiTest['error']?.isNotEmpty == true) {
      buffer.writeln('Error: ${apiTest['error']}');
    }
    if (apiTest['response']?.isNotEmpty == true) {
      buffer.writeln('Response:');
      buffer.writeln(apiTest['response']);
    }
    buffer.writeln();

    // Server Debug
    buffer.writeln('=== SERVER DEBUG ===');
    final serverDebug = data['serverDebug'] as Map<String, dynamic>? ?? {};
    buffer.writeln('Success: ${serverDebug['success']}');
    if (serverDebug['error']?.isNotEmpty == true) {
      buffer.writeln('Error: ${serverDebug['error']}');
    }
    if (serverDebug['response']?.isNotEmpty == true) {
      buffer.writeln('Response:');
      buffer.writeln(serverDebug['response']);
    }
    buffer.writeln();

    // Photo Test
    buffer.writeln('=== PROFILE PHOTO URL TEST ===');
    final photoTest = data['photoTest'] as Map<String, dynamic>? ?? {};
    buffer.writeln('Success: ${photoTest['success']}');
    if (photoTest['error']?.isNotEmpty == true) {
      buffer.writeln('Error: ${photoTest['error']}');
    }
    if (photoTest['result']?.isNotEmpty == true) {
      buffer.writeln('Result: ${photoTest['result']}');
    }
    buffer.writeln();

    // Attendance Debug
    buffer.writeln('=== ATTENDANCE DEBUG ===');
    final attendanceDebug =
        data['attendanceDebug'] as Map<String, dynamic>? ?? {};

    if (attendanceDebug.isEmpty) {
      buffer.writeln('No attendance debug data available');
    } else {
      for (final entry in attendanceDebug.entries) {
        final debugName = entry.key;
        final debugResult = entry.value as Map<String, dynamic>;

        buffer.writeln('--- $debugName ---');
        buffer.writeln('Success: ${debugResult['success']}');

        if (debugResult['error']?.isNotEmpty == true) {
          buffer.writeln('Error: ${debugResult['error']}');
        } else {
          final response = debugResult['response']?.toString() ?? '';
          if (response.isNotEmpty) {
            buffer.writeln('Response:');
            if (response.length > 1000) {
              buffer.writeln(response.substring(0, 1000) + '... [TRUNCATED]');
            } else {
              buffer.writeln(response);
            }
          }
        }
        buffer.writeln();
      }
    }

    // API Debug Results
    buffer.writeln('=== PHP API DEBUG LOG ===');
    final apiDebugResults =
        data['apiDebugResults'] as Map<String, dynamic>? ?? {};

    if (apiDebugResults.isEmpty) {
      buffer.writeln('No APIs tested');
    } else {
      // Group APIs by category
      final profileApis = <String>[];
      final attendanceApis = <String>[];
      final commonApis = <String>[];
      final otherApis = <String>[];

      for (final apiName in apiDebugResults.keys) {
        if (apiName.contains('profile') || apiName.contains('debug_profile')) {
          profileApis.add(apiName);
        } else if (apiName.contains('attendance')) {
          attendanceApis.add(apiName);
        } else if (apiName.contains('plant') || apiName.contains('vehicle')) {
          commonApis.add(apiName);
        } else {
          otherApis.add(apiName);
        }
      }

      // Profile APIs
      if (profileApis.isNotEmpty) {
        buffer.writeln('--- PROFILE APIs ---');
        for (final apiName in profileApis) {
          _writeApiResult(
            buffer,
            apiName,
            apiDebugResults[apiName] as Map<String, dynamic>,
          );
        }
      }

      // Attendance APIs
      if (attendanceApis.isNotEmpty) {
        buffer.writeln('--- ATTENDANCE APIs ---');
        for (final apiName in attendanceApis) {
          _writeApiResult(
            buffer,
            apiName,
            apiDebugResults[apiName] as Map<String, dynamic>,
          );
        }
      }

      // Common APIs
      if (commonApis.isNotEmpty) {
        buffer.writeln('--- COMMON APIs ---');
        for (final apiName in commonApis) {
          _writeApiResult(
            buffer,
            apiName,
            apiDebugResults[apiName] as Map<String, dynamic>,
          );
        }
      }

      // Other APIs
      if (otherApis.isNotEmpty) {
        buffer.writeln('--- OTHER APIs ---');
        for (final apiName in otherApis) {
          _writeApiResult(
            buffer,
            apiName,
            apiDebugResults[apiName] as Map<String, dynamic>,
          );
        }
      }
    }

    buffer.writeln('=== END DEBUG REPORT ===');

    return buffer.toString();
  }

  void _writeApiResult(
    StringBuffer buffer,
    String apiName,
    Map<String, dynamic> apiResult,
  ) {
    buffer.writeln('--- $apiName ---');
    buffer.writeln('Success: ${apiResult['success']}');

    if (apiResult['error']?.isNotEmpty == true) {
      buffer.writeln('Error: ${apiResult['error']}');
    } else {
      buffer.writeln('Status Code: ${apiResult['statusCode']}');

      final headers = apiResult['headers'] as Map<String, dynamic>? ?? {};
      if (headers.isNotEmpty) {
        buffer.writeln('Headers:');
        headers.forEach((key, value) {
          buffer.writeln('  $key: $value');
        });
      }

      final body = apiResult['body']?.toString() ?? '';
      if (body.isNotEmpty) {
        buffer.writeln('Response Body:');
        // Truncate very long responses
        if (body.length > 1000) {
          buffer.writeln(body.substring(0, 1000) + '... [TRUNCATED]');
        } else {
          buffer.writeln(body);
        }
      }
    }
    buffer.writeln();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _debugText));
    showAppToast(context, 'Debug data copied to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Attendance Debug'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _generateDebugData,
          ),
          if (_debugText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyToClipboard,
            ),
        ],
      ),
      body: AppGradientBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _debugText.isEmpty
            ? const Center(child: Text('No debug data available'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.bug_report,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Debug Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'This debug report contains comprehensive information about profile photos, attendance, and all API responses. Copy this data and share it for troubleshooting.',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _copyToClipboard,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy Debug Data'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _generateDebugData,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Debug Output:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: SelectableText(
                                _debugText,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
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
