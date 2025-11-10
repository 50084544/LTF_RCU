import 'package:sachet/core/constants/constants.dart';
import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<BottomNavigationBarItem> _navItems = [
    BottomNavigationBarItem(
      icon: Icon(Icons.home),
      label: 'Activity',
    ),
    // BottomNavigationBarItem(
    //   icon: Icon(Icons.dashboard),
    //   label: 'Dashboard',
    // ),
    BottomNavigationBarItem(
      icon: Icon(Icons.sync_rounded),
      label: 'Sync Status',
    ),
  ];

  static const List<String> _navRoutes = [
    '/home',
    // '/activity',
    '/home',
  ];

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      backgroundColor: AppColors.primary,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white,
      items: _navItems,
      onTap: (index) {
        if (index >= 0 && index < _navRoutes.length) {
          Navigator.pushReplacementNamed(context, _navRoutes[index]);
        }
        onTap(index);
      },
    );
  }
}
