import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_repository.dart';
import '../features/onboarding/onboarding_screen.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final OnboardingRepository _repository = OnboardingRepository();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // IMPORTANT:
      // Wait for the user check to finish before removing
      // the native splash screen.
      await _checkUser();
    } catch (e) {
      debugPrint('Startup error: $e');
    } finally {
      FlutterNativeSplash.remove();
    }
  }

  Future<void> _checkUser() async {
    try {
      final user = await _repository.getUser();

      if (!mounted) return;

      if (user == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to start app: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // --------------------------------------------------
            // SUBTLE BACKGROUND DECORATION
            // --------------------------------------------------
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            Positioned(
              bottom: -120,
              left: -100,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            // --------------------------------------------------
            // MAIN CONTENT
            // --------------------------------------------------
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App Logo / Icon
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.15),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 58,
                      color: colorScheme.primary,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // App Name
                  Text(
                    'BhaktiChart',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Tagline
                  Text(
                    'Track • Improve • Reflect',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Progress Bar
                  SizedBox(
                    width: 180,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(10),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: colorScheme.primary,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    'Preparing your BhaktiChart...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // --------------------------------------------------
            // BOTTOM TEXT
            // --------------------------------------------------
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Text(
                '🙏 Hare Krishna',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
