import 'package:flutter/material.dart';

import 'startup_screen.dart';
import 'theme.dart';

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

      home: const StartupScreen(),
    );
  }
}
