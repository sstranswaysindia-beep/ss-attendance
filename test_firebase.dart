// Test script to verify Firebase setup
// Run this with: flutter run test_firebase.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');

    // Test FCM
    final messaging = FirebaseMessaging.instance;

    // Request permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('✅ Permission status: ${settings.authorizationStatus}');

    // Get token
    String? token = await messaging.getToken();
    print('✅ FCM Token: $token');

    // Listen for messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('✅ Foreground message: ${message.notification?.title}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('✅ Background message tapped: ${message.notification?.title}');
    });

    print('\n🎉 Firebase setup is working correctly!');
    print('📱 Your FCM token is ready for push notifications');
  } catch (e) {
    print('❌ Firebase setup failed: $e');
  }

  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Test',
      home: Scaffold(
        appBar: AppBar(title: const Text('Firebase Test')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 64),
              SizedBox(height: 16),
              Text('Firebase Setup Complete!', style: TextStyle(fontSize: 24)),
              SizedBox(height: 8),
              Text('Check console for FCM token'),
            ],
          ),
        ),
      ),
    );
  }
}
