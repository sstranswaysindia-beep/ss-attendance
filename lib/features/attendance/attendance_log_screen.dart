import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/models/app_user.dart';

// Global API log manager
class GlobalApiLogManager {
  static final List<AttendanceLogEntry> _logs = [];
  static final List<VoidCallback> _listeners = [];

  static List<AttendanceLogEntry> get logs => List.unmodifiable(_logs);

  static void addLog(AttendanceLogEntry log) {
    _logs.insert(0, log); // Add to beginning for newest first
    if (_logs.length > 100) {
      _logs.removeRange(100, _logs.length); // Keep only last 100 logs
    }
    // Notify listeners
    for (final listener in _listeners) {
      listener();
    }
  }

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void clearLogs() {
    _logs.clear();
    for (final listener in _listeners) {
      listener();
    }
  }
}

class AttendanceLogScreen extends StatefulWidget {
  const AttendanceLogScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<AttendanceLogScreen> createState() => _AttendanceLogScreenState();
}

class _AttendanceLogScreenState extends State<AttendanceLogScreen> {
  final List<AttendanceLogEntry> _testLogs = [];
  bool _isLoading = false;
  String? _error;
  bool _showRealTimeLogs = false;

  @override
  void initState() {
    super.initState();
    _loadAttendanceLogs();
    GlobalApiLogManager.addListener(_onLogUpdate);
  }

  @override
  void dispose() {
    GlobalApiLogManager.removeListener(_onLogUpdate);
    super.dispose();
  }

  void _onLogUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAttendanceLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Test various attendance APIs and capture responses
      final List<AttendanceLogEntry> logs = [];

      // 1. Get Current Attendance Status
      logs.add(
        await _testApi(
          'Get Current Attendance Status',
          'POST',
          'https://sstranswaysindia.com/api/mobile/get_attendance_status.php',
          jsonEncode({'userId': widget.user.id}),
        ),
      );

      // 2. Get Attendance History
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      logs.add(
        await _testApi(
          'Get Attendance History (Last 30 Days)',
          'POST',
          'https://sstranswaysindia.com/api/mobile/get_attendance_history.php',
          jsonEncode({
            'userId': widget.user.id,
            'startDate': thirtyDaysAgo.toIso8601String().split('T')[0],
            'endDate': now.toIso8601String().split('T')[0],
          }),
        ),
      );

      // 3. Check for Open Attendance Records
      logs.add(
        await _testApi(
          'Check Open Attendance Records',
          'POST',
          'https://sstranswaysindia.com/api/mobile/get_open_attendance_status_simple.php',
          jsonEncode({
            'userId': widget.user.id,
            'driverId': widget.user.driverId,
          }),
        ),
      );

      // 4. Test Check-in API (simulation)
      logs.add(
        await _testApi(
          'Test Check-in API (Simulation)',
          'POST',
          'https://sstranswaysindia.com/api/mobile/attendance_submit.php',
          jsonEncode({
            'action': 'check_in',
            'driverId':
                widget.user.driverId ??
                widget.user.id, // Use driverId or userId for supervisors
            'plantId': widget.user.plantId ?? 53,
            'vehicleId': 1,
            // 'assignmentId': 1, // Removed to avoid foreign key constraint
            'notes': 'Debug test check-in',
            'source': 'attendance_log_screen',
            'locationJson': jsonEncode({
              'latitude': 22.7196,
              'longitude': 75.8577,
              'accuracy': 10.0,
              'address': 'Test Location',
            }),
          }),
        ),
      );

      // 5. Test Check-out API (simulation)
      logs.add(
        await _testApi(
          'Test Check-out API (Simulation)',
          'POST',
          'https://sstranswaysindia.com/api/mobile/attendance_submit.php',
          jsonEncode({
            'action': 'check_out',
            'driverId':
                widget.user.driverId ??
                widget.user.id, // Use driverId or userId for supervisors
            'plantId': widget.user.plantId ?? 53,
            'vehicleId': 1,
            // 'assignmentId': 1, // Removed to avoid foreign key constraint
            'notes': 'Debug test check-out',
            'source': 'attendance_log_screen',
            'locationJson': jsonEncode({
              'latitude': 22.7196,
              'longitude': 75.8577,
              'accuracy': 10.0,
              'address': 'Test Location',
            }),
          }),
        ),
      );

      // 6. Get Advance Balance
      logs.add(
        await _testApi(
          'Get Advance Balance',
          'POST',
          'https://sstranswaysindia.com/api/mobile/get_advance_balance.php',
          jsonEncode({'driverId': widget.user.driverId ?? widget.user.id}),
        ),
      );

      // 7. Get Advance Transactions
      logs.add(
        await _testApi(
          'Get Advance Transactions',
          'POST',
          'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php',
          jsonEncode({
            'driverId': widget.user.driverId ?? widget.user.id,
            'limit': 10,
          }),
        ),
      );

      // 8. Test Add Advance Transaction (simulation)
      logs.add(
        await _testApi(
          'Test Add Advance Transaction (Simulation)',
          'POST',
          'https://sstranswaysindia.com/api/mobile/add_advance_transaction.php',
          jsonEncode({
            'driverId': widget.user.driverId ?? widget.user.id,
            'type': 'expense',
            'amount': 100.00,
            'description': 'Debug test transaction from API log',
          }),
        ),
      );

      // 9. Test Receipt Upload API (simulation with multipart)
      try {
        logs.add(
          await _testReceiptUploadApi(
            'Test Receipt Upload API (Simulation)',
            '999',
            widget.user.driverId ?? widget.user.id,
          ),
        );
        print('Added Receipt Upload API test');
      } catch (e) {
        print('Error adding Receipt Upload API test: $e');
        logs.add(AttendanceLogEntry(
          name: 'Test Receipt Upload API (Simulation)',
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'https://sstranswaysindia.com/api/mobile/upload_receipt.php',
          requestBody: 'Multipart form data with receipt file',
          success: false,
          error: 'Failed to add test: $e',
        ));
      }

      // 10. Test Fund Transfer API (simulation)
      try {
        logs.add(
          await _testApi(
            'Test Fund Transfer API (Simulation)',
            'POST',
            'https://sstranswaysindia.com/api/mobile/fund_transfer_submit.php',
            jsonEncode({
              'fromDriverId': widget.user.driverId ?? widget.user.id,
              'toDriverId': '999', // Non-existent driver for testing
              'amount': 50.00,
              'description': 'Debug test fund transfer from API log',
            }),
          ),
        );
        print('Added Fund Transfer API test');
      } catch (e) {
        print('Error adding Fund Transfer API test: $e');
        logs.add(AttendanceLogEntry(
          name: 'Test Fund Transfer API (Simulation)',
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'https://sstranswaysindia.com/api/mobile/fund_transfer_submit.php',
          success: false,
          error: 'Failed to add test: $e',
        ));
      }

      // 11. Test Get Drivers API (for fund transfer dropdown)
      try {
        logs.add(
          await _testApi(
            'Test Get Drivers API',
            'POST',
            'https://sstranswaysindia.com/api/mobile/get_drivers.php',
            jsonEncode({'driverId': widget.user.driverId ?? widget.user.id}),
          ),
        );
        print('Added Get Drivers API test');
      } catch (e) {
        print('Error adding Get Drivers API test: $e');
        logs.add(AttendanceLogEntry(
          name: 'Test Get Drivers API',
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'https://sstranswaysindia.com/api/mobile/get_drivers.php',
          success: false,
          error: 'Failed to add test: $e',
        ));
      }

      // 12. Test Delete Transaction API (simulation)
      try {
        logs.add(
          await _testApi(
            'Test Delete Transaction API (Simulation)',
            'POST',
            'https://sstranswaysindia.com/api/mobile/delete_transaction.php',
            jsonEncode({
              'transactionId': '999', // Non-existent transaction for testing
            }),
          ),
        );
        print('Added Delete Transaction API test');
      } catch (e) {
        print('Error adding Delete Transaction API test: $e');
        logs.add(AttendanceLogEntry(
          name: 'Test Delete Transaction API (Simulation)',
          timestamp: DateTime.now(),
          method: 'POST',
          url: 'https://sstranswaysindia.com/api/mobile/delete_transaction.php',
          success: false,
          error: 'Failed to add test: $e',
        ));
      }

      setState(() {
        _testLogs.clear();
        _testLogs.addAll(logs);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<AttendanceLogEntry> _testApi(
    String name,
    String method,
    String url,
    String? body,
  ) async {
    final timestamp = DateTime.now();
    final headers = <String, String>{'Content-Type': 'application/json'};

    try {
      print('Testing API: $name - $url');
      final response = method.toUpperCase() == 'POST'
          ? await http.post(Uri.parse(url), headers: headers, body: body)
          : await http.get(Uri.parse(url), headers: headers);

      print(
        'API Response for $name: ${response.statusCode} - ${response.body}',
      );

      return AttendanceLogEntry(
        name: name,
        timestamp: timestamp,
        method: method,
        url: url,
        requestBody: body,
        statusCode: response.statusCode,
        responseHeaders: response.headers,
        responseBody: response.body,
        success: response.statusCode >= 200 && response.statusCode < 300,
        error: null,
      );
    } catch (e) {
      print('API Error for $name: $e');
      return AttendanceLogEntry(
        name: name,
        timestamp: timestamp,
        method: method,
        url: url,
        requestBody: body,
        statusCode: null,
        responseHeaders: null,
        responseBody: null,
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<AttendanceLogEntry> _testReceiptUploadApi(
    String name,
    String transactionId,
    String driverId,
  ) async {
    final timestamp = DateTime.now();
    final url = 'https://sstranswaysindia.com/api/mobile/upload_receipt.php';

    try {
      // Create a multipart request
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Add fields
      request.fields['transactionId'] = transactionId;
      request.fields['driverId'] = driverId;

      // Create a dummy file content for testing
      final dummyImageData = List.generate(1000, (index) => index % 256);
      final multipartFile = http.MultipartFile.fromBytes(
        'receipt',
        dummyImageData,
        filename: 'test_receipt.jpg',
      );
      request.files.add(multipartFile);

      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return AttendanceLogEntry(
        name: name,
        timestamp: timestamp,
        method: 'POST',
        url: url,
        requestBody: 'Multipart form data with receipt file',
        statusCode: response.statusCode,
        responseHeaders: response.headers,
        responseBody: response.body,
        success: response.statusCode >= 200 && response.statusCode < 300,
        error: null,
      );
    } catch (e) {
      return AttendanceLogEntry(
        name: name,
        timestamp: timestamp,
        method: 'POST',
        url: url,
        requestBody: 'Multipart form data with receipt file',
        statusCode: null,
        responseHeaders: null,
        responseBody: null,
        success: false,
        error: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Log'),
        actions: [
          IconButton(
            icon: Icon(_showRealTimeLogs ? Icons.stop : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _showRealTimeLogs = !_showRealTimeLogs;
              });
            },
            tooltip: _showRealTimeLogs
                ? 'Stop Real-time Logging'
                : 'Start Real-time Logging',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAttendanceLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading logs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadAttendanceLogs,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_showRealTimeLogs)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Colors.blue.shade50,
                    child: Row(
                      children: [
                        Icon(
                          Icons.radio_button_checked,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Real-time API logging is active. Try using the app features to see live API calls.',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _showRealTimeLogs
                        ? GlobalApiLogManager.logs.length
                        : _testLogs.length,
                    itemBuilder: (context, index) {
                      final log = _showRealTimeLogs
                          ? GlobalApiLogManager.logs[index]
                          : _testLogs[index];
                      return _buildLogCard(log);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLogCard(AttendanceLogEntry log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: log.success ? Colors.green.shade200 : Colors.red.shade200,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            // Header with status and copy button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: log.success ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    log.success ? Icons.check_circle : Icons.error,
                    color: log.success
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: log.success
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                        Text(
                          '${log.method} • ${log.timestamp.toString().substring(11, 19)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyLogToClipboard(log),
                    tooltip: 'Copy API details',
                    color: log.success
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ],
              ),
            ),

            // API Details in a single box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompactLogSection('URL', log.url),
                  _buildCompactLogSection('Method', log.method),
                  if (log.requestBody != null)
                    _buildCompactLogSection('Request Body', log.requestBody!),
                  if (log.statusCode != null)
                    _buildCompactLogSection(
                      'Status Code',
                      log.statusCode.toString(),
                    ),
                  if (log.error != null)
                    _buildCompactLogSection('Error', log.error!, isError: true),
                  if (log.responseBody != null)
                    _buildCompactLogSection(
                      'Response Body',
                      _formatResponseBody(log.responseBody!),
                    ),
                  if (log.responseHeaders != null)
                    _buildCompactLogSection(
                      'Response Headers',
                      _formatHeaders(log.responseHeaders!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLogSection(
    String title,
    String content, {
    bool isError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getIconForTitle(title),
                size: 16,
                color: isError ? Colors.red.shade600 : Colors.blue.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isError ? Colors.red.shade700 : Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isError ? Colors.red.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isError ? Colors.red.shade200 : Colors.grey.shade300,
              ),
            ),
            child: SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isError ? Colors.red.shade700 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForTitle(String title) {
    switch (title.toLowerCase()) {
      case 'url':
        return Icons.link;
      case 'method':
        return Icons.http;
      case 'request body':
        return Icons.send;
      case 'status code':
        return Icons.code;
      case 'error':
        return Icons.error;
      case 'response body':
        return Icons.receipt;
      case 'response headers':
        return Icons.list;
      default:
        return Icons.info;
    }
  }

  void _copyLogToClipboard(AttendanceLogEntry log) {
    final buffer = StringBuffer();
    buffer.writeln('=== ${log.name} ===');
    buffer.writeln('Time: ${log.timestamp}');
    buffer.writeln('Method: ${log.method}');
    buffer.writeln('URL: ${log.url}');

    if (log.requestBody != null) {
      buffer.writeln('Request Body:');
      buffer.writeln(log.requestBody!);
    }

    if (log.statusCode != null) {
      buffer.writeln('Status Code: ${log.statusCode}');
    }

    if (log.error != null) {
      buffer.writeln('Error: ${log.error!}');
    }

    if (log.responseBody != null) {
      buffer.writeln('Response Body:');
      buffer.writeln(_formatResponseBody(log.responseBody!));
    }

    if (log.responseHeaders != null) {
      buffer.writeln('Response Headers:');
      buffer.writeln(_formatHeaders(log.responseHeaders!));
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${log.name} details to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green.shade600,
      ),
    );
  }

  Widget _buildLogSection(
    String title,
    String content, {
    bool isError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isError ? Colors.red : null,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isError ? Colors.red.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isError ? Colors.red.shade200 : Colors.grey.shade300,
              ),
            ),
            child: SelectableText(
              content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: isError ? Colors.red.shade700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatResponseBody(String body) {
    try {
      // Try to format as JSON
      final json = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (e) {
      // If not JSON, return as is
      return body;
    }
  }

  String _formatHeaders(Map<String, String> headers) {
    final buffer = StringBuffer();
    headers.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }
}

class AttendanceLogEntry {
  final String name;
  final DateTime timestamp;
  final String method;
  final String url;
  final String? requestBody;
  final int? statusCode;
  final Map<String, String>? responseHeaders;
  final String? responseBody;
  final bool success;
  final String? error;

  AttendanceLogEntry({
    required this.name,
    required this.timestamp,
    required this.method,
    required this.url,
    this.requestBody,
    this.statusCode,
    this.responseHeaders,
    this.responseBody,
    required this.success,
    this.error,
  });
}
