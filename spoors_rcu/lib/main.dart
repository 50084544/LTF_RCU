//import 'package:BMS/features/activities/presentation/pages/expansion.dart';
import 'dart:async';
// import 'package:BMS/core/common_widgets/notification.dart';
// import 'package:BMS/core/common_widgets/settings.dart';
// import 'package:BMS/core/common_widgets/test.dart';
import 'package:BMS/core/network/api_service.dart';
import 'package:BMS/features/auth/presentation/bloc/session/session_event.dart';
//import 'package:BMS/features/activities/presentation/pages/activity.dart';
import 'package:BMS/features/auth/presentation/pages/splash_screen.dart';
//import 'package:BMS/features/auth/presentation/pages/welogin.dart';
//import 'package:BMS/features/form/presentation/form.dart';
//import 'package:BMS/features/workid_list/presentation/widgets/TabController.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/dashboard/presentation/pages/home_screen_new.dart';
import 'features/auth/presentation/bloc/session/session_bloc.dart';
import 'features/auth/data/datasources/api_service.dart';
import 'core/constants/constants.dart';
import 'features/auth/presentation/pages/startuppage.dart';
import 'package:app_links/app_links.dart';
import 'package:BMS/core/common_widgets/sslpinning.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox('app_state');

  try {
    await CertificateReader.initialize();
  } catch (e) {
    // Handle initialization errors
  }

  // Continue with app initialization...
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              SessionBloc(apiService: ApiService())..add(CheckSession()),
        ),
      ],
      child: MyApp(
        apiService: ApiService(),
        isLoggedIn: false,
        stpService: ApiCall(),
      ),
    ),
  );
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

  @override
  void initState() {
    super.initState();
    initAppLinks();
    // _applinkhandler.init((url) {
    //   if (url.contains('/home')) {
    //     // Handle the URL if it contains '/home'
    //     Navigator.pushNamed(context, '/home');
    //   } else {
    //     // Handle other URLs or show an error
    //   }
    // });
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
        //initialRoute: widget.isLoggedIn ? '/home' : '/splash',
        initialRoute: '/home',
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
