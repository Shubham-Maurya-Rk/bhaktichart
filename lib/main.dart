import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite before the app starts.
  await DatabaseHelper.instance.database;

  runApp(const ProviderScope(child: BhaktiChartApp()));
}
