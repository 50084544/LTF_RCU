//import 'package:BMS/core/common_widgets/toast.dart';
import 'package:BMS/core/constants/constants.dart';
import 'package:BMS/features/auth/presentation/pages/startuppage.dart';
//import 'package:BMS/features/auth/data/datasources/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
// import '../../features/auth/presentation/bloc/session/session_bloc.dart';
// import '../../features/auth/presentation/bloc/session/session_event.dart';
// Ensure that SessionLogoutEvent is defined in session_event.dart

class CustomDrawer extends StatefulWidget {
  // Add a parameter to indicate if user is on dashboard
  final bool isOnDashboard;

  const CustomDrawer({
    super.key,
    this.isOnDashboard = false, // Default to false
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String username = 'User';
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _sessionInfo;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    try {
      final box = await Hive.openBox('auth');
      final storedUsername = box.get('username', defaultValue: 'User');

      if (storedUsername != null) {
        setState(() {
          // Capitalize the first letter for better display
          if (storedUsername.toString().isNotEmpty) {
            username = storedUsername.toString()[0].toUpperCase() +
                storedUsername.toString().substring(1);
          } else {
            username = 'User';
          }
        });
      }
    } catch (e) {
      // Keep default username
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Clear auth token from Hive
      await clearAuthToken();

      // Optionally, clear session info
      _sessionInfo = null;

      // Navigate to login page
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      _errorMessage = 'Failed to log out. Please try again.';
    }
    setState(() {
      _sessionInfo = null;
      _isLoading = false;
    });

    // showToast(
    //     context: context,
    //     type: ToastType.success,
    //     message: "User logged out successfully");
  }

  // Add this to your logout handler (in the file where your logout button is defined)
  void _handleLogout() async {
    try {
      // 1. Clear authentication data
      final authBox = await Hive.openBox('auth');
      await authBox.clear(); // Clear all auth data

      // Also clear any other stored session data in other boxes if needed
      final tokenBox = await Hive.openBox('token_data');
      await tokenBox.clear();

      // 2. Navigate to a completely fresh StartupPage
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const Startuppage(forceReload: true),
        ),
        (route) => false, // Remove all routes from the stack
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error logging out: ${e.toString()}')),
      );
    }
  }

  Future<void> clearAuthToken() async {
    try {
      final box = await Hive.openBox('auth');
      await box.delete('token');
      await box.put('IsLoggedIn', false);

      // Update flag in memory
      //_hasAuthToken = false;
    } catch (e) {
      throw Exception('Failed to clear authentication token: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Custom drawer header instead of UserAccountsDrawerHeader
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Centered avatar
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 1.0,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.account_circle,
                        size: 64,
                        color: const Color(0xFF0F2B5B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Username
                Text(
                  'Employee ID: $username',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.fontcolor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // Role
                const Text(
                  'Role: Employee',
                  style: TextStyle(
                    color: AppColors.fontcolor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.dashboard,
              color: widget.isOnDashboard ? Colors.grey : null,
            ),
            title: Text(
              'Dashboard',
              style: TextStyle(
                color: widget.isOnDashboard ? Colors.grey : null,
              ),
            ),
            onTap: widget.isOnDashboard
                ? () {
                    // Just close drawer if already on dashboard
                    Navigator.pop(context);
                  }
                : () {
                    Navigator.pop(context);

                    // Check if we can pop to root instead of creating a new screen
                    // This preserves the state of the dashboard
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
          ),
          // ListTile(
          //   leading: const Icon(Icons.checklist),
          //   title: const Text('Activities'),
          //   onTap: () {
          //     Navigator.of(context).pushReplacementNamed('/expansion');
          //   },
          // ),
          // ListTile(
          //   leading: const Icon(Icons.report),
          //   title: const Text('Reports'),
          //   onTap: () {
          //     Navigator.of(context).pushReplacementNamed('/activity');
          //   },
          // ),
          // ListTile(
          //   leading: const Icon(Icons.restart_alt_rounded),
          //   title: const Text('Sync Status'),
          //   onTap: () {},
          // ),
          // ListTile(
          //   leading: const Icon(Icons.settings),
          //   title: const Text('Settings'),
          //   onTap: () {
          //     Navigator.of(context).pushReplacementNamed('/settings');
          //   },
          // ),
          // ListTile(
          //   leading: const Icon(Icons.question_mark_rounded),
          //   title: const Text('Support'),
          //   onTap: () {
          //     Navigator.pop(context);
          //   },
          // ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context);
              // Use BLoC to handle logout
              _handleLogout();
              //Navigator.of(context).pushReplacementNamed('/logout');
            },
          ),
        ],
      ),
    );
  }
}
