import 'package:flutter/material.dart';

import 'theme.dart';
import '../features/onboarding/onboarding_screen.dart';

class BhaktiChartApp extends StatelessWidget {
  const BhaktiChartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BhaktiChart',

      debugShowCheckedModeBanner: false,

      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: ThemeMode.system,

      home: const OnboardingScreen(),
    );
  }
}
