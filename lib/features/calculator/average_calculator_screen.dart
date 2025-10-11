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
    // On web, show a loading screen since we're opening external link
    if (kIsWeb) {
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              if (_hasError)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Unable to Open Average Calculator',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'There was an error opening the calculator.\nPlease click below to open manually.',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          launchUrl(
                            Uri.parse(
                              'https://sstranswaysindia.com/AverageCalculator/index.php',
                            ),
                            mode: LaunchMode.platformDefault,
                          );
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open Average Calculator'),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              else
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Opening Average Calculator...'),
                    ],
                  ),
                ),
              // Overlay buttons positioned below status bar
              Positioned(
                top: 50,
                left: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.black,
                      size: 18,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ),
              Positioned(
                top: 50,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.black,
                      size: 18,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // On mobile, show WebView with overlay buttons positioned below status bar
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_hasError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to Load Average Calculator',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'There was an error loading the calculator.\nPlease try opening in your browser or retry.',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(
                                'https://sstranswaysindia.com/AverageCalculator/index.php',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('Open in Browser'),
                        ),
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
                  ],
                ),
              )
            else
              WebViewWidget(controller: _controller),
            if (_isLoading && !_hasError)
              const Center(child: CircularProgressIndicator()),
            // Overlay buttons positioned below status bar
            Positioned(
              top: 50,
              left: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.black,
                    size: 18,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
            Positioned(
              top: 50,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
