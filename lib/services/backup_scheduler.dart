import 'package:workmanager/workmanager.dart';

import 'backup_restore_service.dart';

const String automaticWeeklyBackupTask = 'bhaktichart_automatic_weekly_backup';

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // --------------------------------------------------------
      // CHECK TASK
      // --------------------------------------------------------

      if (task != automaticWeeklyBackupTask) {
        return true;
      }

      // --------------------------------------------------------
      // CREATE WEEKLY BACKUP
      //
      // BackupRestoreService will:
      //
      // 1. Create one dated backup.
      // 2. Save it to:
      //    Downloads/BhaktiChart/Backups/
      // 3. Delete backups older than the newest 12.
      //
      // There is NO latest_backup.db.
      // --------------------------------------------------------

      await BackupRestoreService.instance.createAutomaticBackup();

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

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    await Workmanager().initialize(backupCallbackDispatcher);
  }

  // ============================================================
  // ENABLE WEEKLY BACKUP
  // ============================================================

  Future<void> enableWeeklyBackup() async {
    await Workmanager().registerPeriodicTask(
      _uniqueTaskName,
      automaticWeeklyBackupTask,

      // Android WorkManager does not guarantee an exact
      // execution time.
      frequency: const Duration(days: 7),

      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,

      constraints: Constraints(
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
    );
  }

  // ============================================================
  // DISABLE WEEKLY BACKUP
  // ============================================================

  Future<void> disableWeeklyBackup() async {
    await Workmanager().cancelByUniqueName(_uniqueTaskName);
  }
}
