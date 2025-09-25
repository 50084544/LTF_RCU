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
  late List<AnimationController> _letterControllers;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _expandAnimation;
  late List<Animation<double>> _letterAnimations;

  // Animation states
  bool _showFullText = false;

  @override
  void initState() {
    super.initState();

    // First animation: S appears
    _initialController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    // Second animation: Text expands and S slides to the left
    _expandController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));

    // Infinite loader animation
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // Individual letter animations (A, C, H, E, T)
    _letterControllers = List.generate(
      5,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    );

    _letterAnimations = List.generate(
      5,
      (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _letterControllers[index],
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _initialController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _initialController, curve: Curves.easeOutBack),
    );

    _expandAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _expandController, curve: Curves.easeOutCubic),
    );

    // Sequence the animations
    _initialController.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        setState(() {
          _showFullText = true;
        });
        _expandController.forward();
        _startLetterAnimations();
        _loadInitialData();
      });
    });
  }

  void _startLetterAnimations() {
    // Start each letter animation with a delay between them
    for (int i = 0; i < _letterControllers.length; i++) {
      Future.delayed(Duration(milliseconds: 100 + (i * 120)), () {
        if (mounted) {
          _letterControllers[i].forward();
        }
      });
    }
  }

  Future<void> _loadInitialData() async {
    // Simulate API call or any async logic here
    await Future.delayed(const Duration(seconds: 3)); // Replace with real logic
    if (mounted) {
      try {
        Navigator.of(context).pushReplacementNamed('/startuppage');
      } catch (e) {
        debugPrint('Navigation error: $e');
        // Fallback to home if there's an issue with navigation
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  @override
  void dispose() {
    _initialController.dispose();
    _expandController.dispose();
    _loaderController.dispose();

    // Dispose letter animation controllers
    for (var controller in _letterControllers) {
      controller.dispose();
    }

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
            // Animation container
            SizedBox(
              height: 100,
              width: 350, // Ensure enough width for the text
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: _showFullText
                      // Second animation stage - show full text with sliding animation
                      ? AnimatedBuilder(
                          animation: _expandAnimation,
                          builder: (context, child) {
                            // Use a completely different approach with RichText
                            // This guarantees no gaps between characters
                            final TextStyle baseStyle = getSachetTextStyle(60);

                            return Center(
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    // The S character with consistent vertical alignment
                                    WidgetSpan(
                                      child: Text(
                                        "S",
                                        style: baseStyle,
                                      ),
                                    ),
                                    // Individual letter animations for ACHET with staggered effects
                                    WidgetSpan(
                                      child: Transform.translate(
                                        offset: Offset(
                                            0,
                                            10 *
                                                (1 -
                                                    _letterAnimations[0]
                                                        .value)),
                                        child: Transform.scale(
                                          scale: 0.5 +
                                              (0.5 *
                                                  _letterAnimations[0].value),
                                          child: Opacity(
                                            opacity:
                                                _letterAnimations[0].value *
                                                    _expandAnimation.value,
                                            child: Text(
                                              "A",
                                              style: baseStyle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    WidgetSpan(
                                      child: Transform.translate(
                                        offset: Offset(
                                            0,
                                            10 *
                                                (1 -
                                                    _letterAnimations[1]
                                                        .value)),
                                        child: Transform.scale(
                                          scale: 0.5 +
                                              (0.5 *
                                                  _letterAnimations[1].value),
                                          child: Opacity(
                                            opacity:
                                                _letterAnimations[1].value *
                                                    _expandAnimation.value,
                                            child: Text(
                                              "C",
                                              style: baseStyle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    WidgetSpan(
                                      child: Transform.translate(
                                        offset: Offset(
                                            0,
                                            10 *
                                                (1 -
                                                    _letterAnimations[2]
                                                        .value)),
                                        child: Transform.scale(
                                          scale: 0.5 +
                                              (0.5 *
                                                  _letterAnimations[2].value),
                                          child: Opacity(
                                            opacity:
                                                _letterAnimations[2].value *
                                                    _expandAnimation.value,
                                            child: Text(
                                              "H",
                                              style: baseStyle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    WidgetSpan(
                                      child: Transform.translate(
                                        offset: Offset(
                                            0,
                                            10 *
                                                (1 -
                                                    _letterAnimations[3]
                                                        .value)),
                                        child: Transform.scale(
                                          scale: 0.5 +
                                              (0.5 *
                                                  _letterAnimations[3].value),
                                          child: Opacity(
                                            opacity:
                                                _letterAnimations[3].value *
                                                    _expandAnimation.value,
                                            child: Text(
                                              "E",
                                              style: baseStyle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    WidgetSpan(
                                      child: Transform.translate(
                                        offset: Offset(
                                            0,
                                            10 *
                                                (1 -
                                                    _letterAnimations[4]
                                                        .value)),
                                        child: Transform.scale(
                                          scale: 0.5 +
                                              (0.5 *
                                                  _letterAnimations[4].value),
                                          child: Opacity(
                                            opacity:
                                                _letterAnimations[4].value *
                                                    _expandAnimation.value,
                                            child: Text(
                                              "T",
                                              style: baseStyle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      // First animation stage - only show S in center
                      : Center(
                          child: Text(
                            "S",
                            style: getSachetTextStyle(60),
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Progress indicator
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.3),
                color: Colors.white,
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to apply text shadow style
  TextStyle getSachetTextStyle(double fontSize) {
    return TextStyle(
      // Using a standard font that renders more predictably for spacing
      fontFamily: 'Roboto',
      fontWeight: FontWeight.bold,
      fontSize: fontSize,
      letterSpacing: -1.5, // Reduce letter spacing to close gaps
      color: Colors
          .white, // Set text color to black for visibility on yellow background
      shadows: [
        Shadow(
          color: Colors.white.withOpacity(0.5),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ],
    );
  }
}
