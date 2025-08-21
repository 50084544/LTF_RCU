import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _initialController;
  late AnimationController _expandController;
  late AnimationController _loaderController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _expandAnimation;

  // Animation states
  bool _showFullText = false;

  @override
  void initState() {
    super.initState();

    // First animation: R appears
    _initialController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    // Second animation: Text expands
    _expandController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));

    // Infinite loader animation
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _initialController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _initialController, curve: Curves.easeOutBack),
    );

    _expandAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _expandController, curve: Curves.easeOutQuad),
    );

    // Sequence the animations
    _initialController.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        setState(() {
          _showFullText = true;
        });
        _expandController.forward();
        _loadInitialData();
      });
    });
  }

  Future<void> _loadInitialData() async {
    // Simulate API call or any async logic here
    await Future.delayed(const Duration(seconds: 3)); // Replace with real logic
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/startuppage');
    }
  }

  @override
  void dispose() {
    _initialController.dispose();
    _expandController.dispose();
    _loaderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3db21), // Use your brand color
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // This ensures we always have at least one child
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ensure this Row also has at least one child
                    if (_showFullText)
                      AnimatedBuilder(
                        animation: _expandAnimation,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _expandAnimation.value,
                            child: const Text(
                              "LTF ",
                              style: TextStyle(
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'PlayfairDisplay',
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      const SizedBox.shrink(), // Empty widget as fallback

                    // Always include the R
                    const Text(
                      "R",
                      style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                        color: Colors.white,
                      ),
                    ),

                    if (_showFullText)
                      AnimatedBuilder(
                        animation: _expandAnimation,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _expandAnimation.value,
                            child: const Text(
                              "CU",
                              style: TextStyle(
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'PlayfairDisplay',
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      const SizedBox.shrink(), // Empty widget as fallback
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Progress indicator (always included)
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: Colors.blue[100],
                color: Colors.blue[800],
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialR() {
    return Text(
      'R',
      style: TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontWeight: FontWeight.bold,
        fontSize: 80,
        color: Colors.white,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.3),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandingText() {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LTF ',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.bold,
                fontSize: 40 * _expandAnimation.value,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            Text(
              'R',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.bold,
                fontSize: 80,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            Text(
              'CU',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.bold,
                fontSize: 40 * _expandAnimation.value,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
