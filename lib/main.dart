import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/backup_scheduler.dart';

import 'app/app.dart';
import 'core/database/database_helper.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep the native splash screen visible while the app initializes.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Initialize database before starting the app.
  await DatabaseHelper.instance.database;

  await BackupScheduler.instance.initialize();

  runApp(const ProviderScope(child: BhaktiChartApp()));
}
