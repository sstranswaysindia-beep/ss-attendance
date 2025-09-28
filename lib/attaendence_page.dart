import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _nameController = TextEditingController();
  String _status = "present";
  bool _loading = false;
  String _message = "";

  Future<void> markAttendance() async {
    setState(() {
      _loading = true;
      _message = "";
    });

    final url = Uri.parse(
      "https://sstranswaysindia.com/api/attendance.php?action=mark",
    );

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization":
              "Bearer WJFFNKNGKFNGKFJBHSVHDSV74658458N848CY8RN8VN8", // your token
        },
        body: json.encode({
          "student_name": _nameController.text.trim(),
          "status": _status,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["ok"] == true) {
          setState(() {
            _message =
                "✅ Attendance marked for ${data['student_name']} (${data['status']})";
          });
        } else {
          setState(() {
            _message = "❌ Error: ${data['error']}";
          });
        }
      } else {
        setState(() {
          _message = "❌ Server error: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _message = "❌ Exception: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mark Attendance")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Student Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _status,
              items: const [
                DropdownMenuItem(value: "present", child: Text("Present")),
                DropdownMenuItem(value: "absent", child: Text("Absent")),
                DropdownMenuItem(value: "late", child: Text("Late")),
              ],
              onChanged: (value) {
                setState(() {
                  _status = value ?? "present";
                });
              },
              decoration: const InputDecoration(
                labelText: "Status",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : markAttendance,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Mark Attendance"),
            ),
            const SizedBox(height: 16),
            Text(_message, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
