import 'package:workmanager/workmanager.dart';

import 'backup_restore_service.dart';

const String automaticWeeklyBackupTask = 'bhaktichart_automatic_weekly_backup';

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == automaticWeeklyBackupTask) {
        await BackupRestoreService.instance.createAutomaticBackup();
      }

      return true;
    } catch (e, stackTrace) {
      print('BhaktiChart automatic backup failed: $e');
      print(stackTrace);
      return false;
    }
  });
}

class BackupScheduler {
  BackupScheduler._();

  static final BackupScheduler instance = BackupScheduler._();

  static const String _uniqueTaskName = 'bhaktichart_weekly_automatic_backup';

  Future<void> initialize() async {
    await Workmanager().initialize(backupCallbackDispatcher);
  }

  Future<void> enableWeeklyBackup() async {
    await Workmanager().registerPeriodicTask(
      _uniqueTaskName,
      automaticWeeklyBackupTask,
      frequency: const Duration(days: 7),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
    );
  }

  Future<void> disableWeeklyBackup() async {
    await Workmanager().cancelByUniqueName(_uniqueTaskName);
  }
}
