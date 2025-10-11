import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class AverageCalculatorScreen extends StatefulWidget {
  const AverageCalculatorScreen({super.key});

  @override
  State<AverageCalculatorScreen> createState() =>
      _AverageCalculatorScreenState();
}

class _AverageCalculatorScreenState extends State<AverageCalculatorScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _loadingTimeout;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // On web, open in new tab and close this screen
      _openInNewTab();
    } else {
      // On mobile, use WebView
      _initializeWebView();
      // Set a timeout for slow loading
      _loadingTimeout = Timer(const Duration(seconds: 10), () {
        if (mounted && _isLoading) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    super.dispose();
  }

  void _openInNewTab() async {
    // The Average Calculator requires authentication, so we need to open it in a new tab
    // where the user can login with their web credentials
    final url = Uri.parse(
      'https://sstranswaysindia.com/AverageCalculator/index.php',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
        // Close this screen after opening external link
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        // Fallback: show manual link option
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      }
    } catch (e) {
      print('Error opening Average Calculator: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _initializeWebView() {
    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('Average Calculator: Page started loading: $url');
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            print('Average Calculator: Page finished loading: $url');
            _loadingTimeout?.cancel(); // Cancel timeout when page loads
            setState(() {
              _isLoading = false;
            });
            
            // Don't treat login page as an error - allow user to login in WebView
            // The login flow should work directly in the WebView
          },
          onWebResourceError: (WebResourceError error) {
            print('Average Calculator: WebView error: ${error.description}');
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://sstranswaysindia.com/AverageCalculator/index.php'),
      );

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    // On web, just open external link
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Average Calculator'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Opening Average Calculator in your browser...'),
            ],
          ),
        ),
      );
    }

    // On mobile, simple WebView with AppBar
    return Scaffold(
      appBar: AppBar(
        title: const Text('Average Calculator'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () {
              launchUrl(
                Uri.parse('https://sstranswaysindia.com/AverageCalculator/index.php'),
                mode: LaunchMode.externalApplication,
              );
            },
            tooltip: 'Open in Browser',
          ),
        ],
      ),
      body: _hasError
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to Load Calculator',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Please try opening in your browser or check your connection.'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      launchUrl(
                        Uri.parse('https://sstranswaysindia.com/AverageCalculator/index.php'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Open in Browser'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _isLoading = true;
                      });
                      _initializeWebView();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading Calculator...'),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
