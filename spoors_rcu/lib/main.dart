//import 'package:BMS/features/activities/presentation/pages/expansion.dart';
import 'dart:async';
import 'package:BMS/core/network/api_service.dart';
import 'package:BMS/features/auth/presentation/pages/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/dashboard/presentation/pages/home_screen_new.dart';
import 'features/auth/presentation/bloc/session/session_bloc.dart';
import 'features/auth/presentation/bloc/session/session_event.dart';
import 'package:BMS/features/auth/data/datasources/api_service.dart';
import 'core/constants/constants.dart';
import 'features/auth/presentation/pages/startuppage.dart';
import 'package:app_links/app_links.dart';
import 'package:BMS/core/common_widgets/sslpinning.dart';
import 'dart:io';
import 'package:BMS/core/security/security_service.dart';
import 'package:flutter_logs/flutter_logs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox('app_state');

  await FlutterLogs.initLogs(
    logLevelsEnabled: [
      LogLevel.ERROR,
      LogLevel.INFO,
      LogLevel.WARNING
    ], // what levels to store
    timeStampFormat: TimeStampFormat.TIME_FORMAT_READABLE,
    directoryStructure:
        DirectoryStructure.FOR_DATE, // keeps logs separated per day
    logTypesEnabled: ["API", "DEVICE", "ERROR"],
    logFileExtension: LogFileExtension.LOG, // categories
  );

  try {
    await CertificateReader.initialize();
  } catch (e) {
    // Handle initialization errors
  }

  // Initialize the security service
  final securityService = SecurityService();
  await securityService.initialize();

  // Run comprehensive security checks
  final isSecure = await securityService.runSecurityChecks(exitOnFailure: true);

  // If not secure, the app will exit before reaching here
  if (!isSecure) {
    // Show security alert and exit app
    runApp(EmulatorBlockerApp());
    return;
  }

  // Continue with app initialization...
  final apiService = ApiService();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              SessionBloc(apiService: apiService)..add(const CheckSession()),
        ),
      ],
      child: MyApp(
        apiService: apiService,
        isLoggedIn: false,
        stpService: ApiCall(),
      ),
    ),
  );
}

// Security checks are now handled by SecurityService

// Add a simple app that shows emulator blocking message
class EmulatorBlockerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red[100],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.security,
                size: 80,
                color: Colors.red[800],
              ),
              SizedBox(height: 24),
              Text(
                'Security Alert',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[800],
                ),
              ),
              SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  'This application cannot run on emulators or virtual devices for security reasons.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.red[800]),
                ),
              ),
              SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[800],
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  exit(0); // Force close the app
                },
                child: Text('Exit Application'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  final ApiService apiService;
  final bool isLoggedIn;
  final ApiCall stpService;

  const MyApp({
    super.key,
    required this.apiService,
    required this.isLoggedIn,
    required this.stpService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //bool _openHomeDirectly = false;
  //final _applinkhandler = AppLinksService();
  final _appLinks = AppLinks();
  final _securityService = SecurityService();
  Timer? _securityCheckTimer;

  @override
  void initState() {
    super.initState();
    initAppLinks();
    setupPeriodicSecurityChecks();
    // _applinkhandler.init((url) {
    //   if (url.contains('/home')) {
    //     // Handle the URL if it contains '/home'
    //     Navigator.pushNamed(context, '/home');
    //   } else {
    //     // Handle other URLs or show an error
    //   }
    // });
  }

  @override
  void dispose() {
    _securityCheckTimer?.cancel();
    super.dispose();
  }

  /// Setup periodic security checks to detect runtime attacks
  void setupPeriodicSecurityChecks() {
    // Run security checks every 5 seconds while the app is running
    // This helps detect dynamic injection of Frida, Objection etc.
    _securityCheckTimer = Timer.periodic(Duration(seconds: 5), (_) async {
      final isSecure = await _securityService.runSecurityChecks();
      if (!isSecure && mounted) {
        // If security issue detected at runtime, show alert and exit
        _securityService.showSecurityAlert(context);
      }
    });
  }

  Future<void> initAppLinks() async {
    // Handle app start from URL (cold start)
    final appLink = await _appLinks.getInitialAppLink();
    if (appLink != null) {
      handleIncomingUrl(appLink);
    }

    // Handle links when app is already running
    _appLinks.uriLinkStream.listen((Uri uri) {
      handleIncomingUrl(uri);
    });
  }

  void handleIncomingUrl(Uri uri) {
    // Extract just the path component, ignoring query parameters like SAMLResponse
    final String path = uri.path;

    // Now route based on the path, regardless of query parameters
    if (path == '/home') {
      // Navigate to home screen using your navigation system
      // For example with Navigator:
      Navigator.of(context).pushReplacementNamed('/home');

      // Or if using GetX:
      // Get.offAllNamed('/home');

      // Or if using GoRouter:
      // GoRouter.of(context).go('/home');
    }
    // Add other path handlers as needed
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SessionBloc>(
          create: (context) => SessionBloc(apiService: widget.apiService),
        ),
      ],
      child: MaterialApp(
        // title: 'SPOORS RCU',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: Font.poppins,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.seedColor,
            primary: AppColors.primary,
            secondary: AppColors.secondary,
            tertiary: AppColors.tertiary,
            background: AppColors.background,
            surface: AppColors.surface,
          ),
          // appBarTheme: const AppBarTheme(
          //   backgroundColor: Color(0xFF0F2B5B),
          //   foregroundColor: Colors.white,
          //   elevation: 2,
          // ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide:
                  const BorderSide(color: AppColors.secondary, width: 2.0),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
          ),
        ),
        initialRoute: widget.isLoggedIn ? '/home' : '/splash',
        //initialRoute: '/home',
        //initialRoute: '/splash',
        routes: {
          //'/login': (context) => const Login(),
          '/home': (context) => const HomeScreenNew(),
          //'/activity': (context) => const Activity(),
          //'/workid-list': (context) => const TabView(),
          //'/expansion': (context) => const Activity(),
          // '/worklist': (context) => const Workid(),
          //'/notifications': (context) => const NotificationScreen(),
          //'/form': (context) => const FormpagState(),
          // '/settings': (context) => const Settings(),
          // '/test-stp': (context) => const TestSTP(),
          '/startuppage': (context) => const Startuppage(),
          // '/web-login': (context) => const WebLoginPage(),
          //'/logout': (context) => const LogoutPage(),
          '/splash': (context) => const SplashScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
