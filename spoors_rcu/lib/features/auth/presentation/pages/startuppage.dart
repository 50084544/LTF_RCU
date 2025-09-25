import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart';
// import '../../data/datasources/saml_auth_service.dart'; // update path
// import '../pages/welogin.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:hive/hive.dart';

class Startuppage extends StatefulWidget {
  final bool forceReload;
  const Startuppage({this.forceReload = false, super.key});

  @override
  State<Startuppage> createState() => _StartuppageState();
}

class _StartuppageState extends State<Startuppage> {
  late InAppWebViewController _webViewController;
  bool _isRedirecting = false;
  bool _showLoadingScreen = false;
  bool _firstRedirectOccurred = false;
  bool _webViewReady = false;

  // Add a flag to track SAML response detection
  bool _samlResponseDetected = false;

  // Modify this method to show loading screen immediately and handle the delay
  void _showLoadingWithDelay(String emailValue) async {
    // Ensure loading screen is visible immediately
    setState(() => _showLoadingScreen = true);

    // Wait for 3.5 seconds minimum
    await Future.delayed(const Duration(milliseconds: 3500));

    // Check if the widget is still mounted before navigating
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home',
          arguments: {'name': emailValue});
    }
  }

  @override
  void initState() {
    super.initState();
    // Reset authentication status if forceReload is true
    if (widget.forceReload) {
      _resetAuth();
    }
  }

  Future<void> _resetAuth() async {
    try {
      // Make sure we're logged out from ADFS by clearing cookies
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (e) {}
  }

// Add this method to your _StartuppageState class

  // Update onLoadStop method to better handle redirects
  Future<void> handleUrlLoad(String? urlStr) async {
    if (urlStr == null) return;

    if (urlStr.contains("spoorsrcu.com/homepage")) {
      // Check if this URL contains SAML response
      if (urlStr.contains("SAMLResponse=")) {
        if (_samlResponseDetected) return; // Prevent duplicate processing
        _samlResponseDetected = true;

        try {
          final uri = Uri.parse(urlStr);
          final samlResponseEncoded = uri.queryParameters['SAMLResponse'];
          if (samlResponseEncoded != null) {
            final compressedData = base64.decode(samlResponseEncoded);
            final decompressedBytes = Inflate(compressedData).getBytes();
            final xmlString = utf8.decode(decompressedBytes);
            final document = XmlDocument.parse(xmlString);

            final emailAttr = document.findAllElements('Attribute').firstWhere(
                  (attr) =>
                      attr.getAttribute('Name') ==
                      'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
                  orElse: () => XmlElement(XmlName('')),
                );

            final emailValue =
                emailAttr.findElements('AttributeValue').firstOrNull?.text ??
                    'N/A';

            final nameIdElements = document.findAllElements('NameID');
            final nameId = nameIdElements.isNotEmpty
                ? nameIdElements.first.innerText
                : 'N/A';

            final box = await Hive.openBox('auth');
            await box.put(
                'token', DateTime.now().millisecondsSinceEpoch.toString());
            await box.put('IsLoggedIn', true);
            await box.put('username', nameId);
            await box.put('email', emailValue);

            // Show loading screen immediately and handle navigation with delay
            _showLoadingWithDelay(nameId);
          }
        } catch (e) {
          if (mounted) setState(() => _showLoadingScreen = false);
        }
      } else if (!_showLoadingScreen && _firstRedirectOccurred) {
        // Handle redirects that don't contain SAML but are part of the auth flow
      }

      // Track first redirect regardless of SAML
      if (!_firstRedirectOccurred) {
        _firstRedirectOccurred = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Prevent back button navigation after logout
      onWillPop: () async => false,
      child: Scaffold(
        // appBar: AppBar(
        //   automaticallyImplyLeading: false,
        //   toolbarHeight: 220,
        //   title: Image.asset(
        //     //'assets/logos/lnt_finance/LTF_logo.png',
        //     'assets/logos/lnt_finance/Sachet_Logo.jpg',
        //     height: 200,
        //     fit: BoxFit.contain,
        //     width: double.infinity,
        //   ),
        //   centerTitle: true,
        //   //backgroundColor: const Color.fromARGB(255, 243, 219, 33),
        //   backgroundColor: const Color.fromARGB(255, 0, 152, 219),
        // ),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 220,
          // Replace the title with flexibleSpace for better control
          flexibleSpace: Container(
            color: const Color.fromARGB(255, 0, 152, 219),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Image.asset(
                  'assets/logos/lnt_finance/Sachet_Logo.jpg',
                  height: 200, // Slightly smaller to ensure it fits properly
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          backgroundColor: const Color.fromARGB(255, 0, 152, 219),
        ),
        backgroundColor: Colors.white, // Set background color explicitly
        body: Stack(
          children: [
            // Initial loading animation (always below the WebView in the stack)
            Container(
              color: Colors.white,
              width: double.infinity,
              height: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height * 0.1,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: Lottie.asset(
                        'assets/animations/Loading1.json',
                        repeat: true,
                        animate: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _showLoadingScreen ? "Welcome to SACHET!" : "Loading...",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _showLoadingScreen
                          ? "Hang Tight! We're getting things ready for you."
                          : "Setting things up...",
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // WebView (on top of the loading animation but hidden when we want to show the loading screen)
            Visibility(
              visible: _webViewReady && !_showLoadingScreen,
              maintainState: true, // Important to keep WebView state
              child: InAppWebView(
                initialOptions: InAppWebViewGroupOptions(
                  crossPlatform: InAppWebViewOptions(
                    transparentBackground: true,
                    javaScriptEnabled: true,
                    useOnLoadResource: true,
                    useShouldOverrideUrlLoading: true,
                    mediaPlaybackRequiresUserGesture: false,
                  ),
                  android: AndroidInAppWebViewOptions(
                    useHybridComposition: true,
                    mixedContentMode:
                        AndroidMixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  ),
                  ios: IOSInAppWebViewOptions(
                    allowsInlineMediaPlayback: true,
                  ),
                ),
                initialUrlRequest: URLRequest(
                  url: WebUri(
                      'https://cloudadfs.ltfs.com/adfs/ls/idpinitiatedsignon?loginToRp=https://spoorsrcu.com/homepage'),
                ),
                onWebViewCreated: (controller) async {
                  _webViewController = controller;
                  await _webViewController.clearCache();
                },
                onLoadStart: (controller, url) async {
                  final urlStr = url.toString();
                  await handleUrlLoad(urlStr);
                },
                onLoadStop: (controller, url) async {
                  if (!_webViewReady) {
                    setState(() {
                      _webViewReady = true;
                    });
                  }

                  final urlStr = url?.toString() ?? '';
                  await handleUrlLoad(urlStr);
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  // This is crucial for catching redirects
                  final url = navigationAction.request.url?.toString();
                  await handleUrlLoad(url);
                  return NavigationActionPolicy.ALLOW;
                },
                onProgressChanged: (controller, progress) {
                  if (progress == 100 && !_webViewReady) {
                    setState(() {
                      _webViewReady = true;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
