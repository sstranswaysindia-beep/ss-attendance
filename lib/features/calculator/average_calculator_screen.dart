import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AverageCalculatorScreen extends StatefulWidget {
  const AverageCalculatorScreen({super.key});

  @override
  State<AverageCalculatorScreen> createState() =>
      _AverageCalculatorScreenState();
}

class _AverageCalculatorScreenState extends State<AverageCalculatorScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // On web, open in new tab and close this screen
      _openInNewTab();
    } else {
      // On mobile, use WebView
      _initializeWebView();
    }
  }

  void _openInNewTab() async {
    final url = Uri.parse('https://sstranswaysindia.com/AverageCalculator/index.php');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        // Close this screen after opening external link
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      print('Error opening Average Calculator: $e');
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://sstranswaysindia.com/AverageCalculator/index.php'),
      );
  }

  @override
  Widget build(BuildContext context) {
    // On web, show a loading screen since we're opening external link
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 48,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Opening Average Calculator...'),
            ],
          ),
        ),
      );
    }

    // On mobile, show WebView
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48, // Reduced from default 56
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          padding: EdgeInsets.zero,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
