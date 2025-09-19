import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
//import '../../data/datasources/saml_auth_service.dart'; // update path
//import '../pages/welogin.dart';

class LogoutPage extends StatefulWidget {
  const LogoutPage({super.key});

  @override
  State<LogoutPage> createState() => _LogoutPageState();
}

class _LogoutPageState extends State<LogoutPage> {
  //final _appLinkHandler = AppLinkHandler();
  late InAppWebViewController _webViewController;

  // @override
  // void initState() {
  //   super.initState();

  //   _appLinkHandler.init((url) {
  //     // Example: https://spoorsrcu.com/home?SAMLResponse=...
  //     if (url.contains("/home")) {
  //       Navigator.pushNamed(
  //           context, '/home'); // route must exist in MaterialApp
  //     }
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          toolbarHeight: 220,
          title: Image.asset(
            'assets/logos/lnt_finance/LTF_logo.png',
            height: 200,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 243, 219, 33),
        ),
        body: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(
              'https://cloudadfs.ltfs.com/adfs/ls/?wa=wsignout1.0',
            ),
          ),
          // initialSettings: InAppWebViewSettings(
          //   javaScriptEnabled: true,
          //   useShouldOverrideUrlLoading: true,
          // ),
          onWebViewCreated: (controller) async {
            _webViewController = controller;
            await _webViewController.clearCache();
          },
          onLoadStart: (controller, url) {
            //print("Loading started: $url");
            Navigator.pushReplacementNamed(context, '/startuppage');
            // if (url.toString().contains("wsignout")) {
            //   Navigator.pushReplacementNamed(context, '/login');
            // }
          },
        ));
  }
}
