import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backup_restore_service.dart';
import '../../services/backup_scheduler.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final BackupRestoreService _backupService = BackupRestoreService.instance;

  bool _isExporting = false;
  bool _isImporting = false;

  bool _automaticBackupEnabled = true;
  bool _isAutomaticBackupLoading = true;
  bool _isAutomaticBackupRunning = false;
  DateTime? _lastAutomaticBackup;

  @override
  void initState() {
    super.initState();
    _loadAutomaticBackupStatus();
  }

  Future<void> _loadAutomaticBackupStatus() async {
    try {
      final lastBackup =
          await BackupRestoreService.instance.getLastAutomaticBackupTime();

      if (!mounted) return;

      setState(() {
        _lastAutomaticBackup = lastBackup;
        _isAutomaticBackupLoading = false;
      });
    } catch (e) {
      debugPrint('Automatic backup status error: $e');

      if (mounted) {
        setState(() {
          _isAutomaticBackupLoading = false;
        });
      }
    }
  }

  Future<void> _setAutomaticBackupEnabled(bool enabled) async {
    if (_isAutomaticBackupRunning) return;

    setState(() {
      _isAutomaticBackupRunning = true;
    });

    try {
      if (enabled) {
        await BackupScheduler.instance.enableWeeklyBackup();
      } else {
        await BackupScheduler.instance.disableWeeklyBackup();
      }

      if (!mounted) return;

      setState(() {
        _automaticBackupEnabled = enabled;
        _isAutomaticBackupRunning = false;
      });

      _showSuccess(
        enabled
            ? 'Automatic weekly backup enabled.'
            : 'Automatic weekly backup disabled.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAutomaticBackupRunning = false;
      });

      _showError('Unable to update automatic backup.\n\n$e');
    }
  }

  Future<void> _runAutomaticBackupNow() async {
    if (_isBusy || _isAutomaticBackupRunning) return;

    setState(() {
      _isAutomaticBackupRunning = true;
    });

    try {
      final result =
          await BackupRestoreService.instance.createAutomaticBackup();

      if (!mounted) return;

      setState(() {
        _lastAutomaticBackup = result.createdAt;
        _isAutomaticBackupRunning = false;
      });

      _showSuccess(
        'Backup saved to Downloads/BhaktiChart/Backups.',
      );
    } catch (e, stackTrace) {
      debugPrint('Automatic backup error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isAutomaticBackupRunning = false;
      });

      _showError('Unable to create automatic backup.\n\n$e');
    }
  }

  String _formatBackupDate(DateTime? date) {
    if (date == null) return 'Never';

    final local = date.toLocal();

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  // ============================================================
  // BUSY
  // ============================================================

  bool get _isBusy {
    return _isExporting || _isImporting;
  }

  // ============================================================
  // EXPORT
  // ============================================================

  Future<void> _exportBackup() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      // --------------------------------------------------------
      // CREATE BACKUP
      // --------------------------------------------------------

      final backupFile = await _backupService.createBackupFile();

      if (!mounted) {
        return;
      }

      // --------------------------------------------------------
      // SHARE BACKUP
      // --------------------------------------------------------

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              backupFile.path,
              name: backupFile.uri.pathSegments.last,
              mimeType: 'application/octet-stream',
            ),
          ],
          title: 'Bhaktichart Backup',
          subject: 'Bhaktichart Database Backup',
          text:
              'Bhaktichart database backup.\n\n'
              'Keep this file safe. You can use it later '
              'to restore your Sadhana data.',
        ),
      );

      if (!mounted) {
        return;
      }

      _showSuccess('Backup created successfully.');
    } catch (e, stackTrace) {
      debugPrint('====================================');
      debugPrint('EXPORT BACKUP ERROR');
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint('====================================');

      if (!mounted) {
        return;
      }

      _showError('Unable to create backup.\n\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // ============================================================
  // IMPORT
  // ============================================================

  Future<void> _importBackup() async {
    if (_isBusy) {
      return;
    }

    // ----------------------------------------------------------
    // CONFIRM
    // ----------------------------------------------------------

    final confirmed = await _showRestoreConfirmation();

    if (confirmed != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    File? temporaryPickedFile;

    try {
      // --------------------------------------------------------
      // FILE PICKER
      // --------------------------------------------------------
      //
      // IMPORTANT:
      //
      // Do NOT use:
      //
      // FileType.custom
      // allowedExtensions: ['db']
      //
      // Some Android document providers don't expose .db files
      // correctly through extension filtering.
      //
      // We therefore use FileType.any and validate the database
      // ourselves.
      // --------------------------------------------------------

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,

        // Important for Android SAF providers.
        withData: true,
      );

      // --------------------------------------------------------
      // USER CANCELLED
      // --------------------------------------------------------

      if (result == null || result.files.isEmpty) {
        return;
      }

      final pickedFile = result.files.single;

      debugPrint('====================================');
      debugPrint('FILE PICKER RESULT');
      debugPrint('Name: ${pickedFile.name}');
      debugPrint('Path: ${pickedFile.path}');
      debugPrint('Bytes: ${pickedFile.bytes?.length ?? 0}');
      debugPrint('Size: ${pickedFile.size}');
      debugPrint('====================================');

      // --------------------------------------------------------
      // RESOLVE FILE
      // --------------------------------------------------------

      File? backupFile;

      // ========================================================
      // OPTION 1
      // ========================================================
      //
      // File picker gave us an accessible path.
      //
      // ========================================================

      if (pickedFile.path != null && pickedFile.path!.trim().isNotEmpty) {
        final candidate = File(pickedFile.path!);

        if (await candidate.exists()) {
          backupFile = candidate;
        }
      }

      // ========================================================
      // OPTION 2
      // ========================================================
      //
      // Android returned bytes instead of an accessible path.
      //
      // Create our own temporary .db file.
      //
      // ========================================================

      if (backupFile == null &&
          pickedFile.bytes != null &&
          pickedFile.bytes!.isNotEmpty) {
        final tempDirectory = Directory.systemTemp;

        final timestamp = DateTime.now().millisecondsSinceEpoch;

        final tempPath =
            '${tempDirectory.path}'
            '${Platform.pathSeparator}'
            'bhaktichart_import_$timestamp.db';

        final tempFile = File(tempPath);

        await tempFile.writeAsBytes(pickedFile.bytes!, flush: true);

        temporaryPickedFile = tempFile;

        backupFile = tempFile;
      }

      // --------------------------------------------------------
      // NO FILE ACCESS
      // --------------------------------------------------------

      if (backupFile == null) {
        throw Exception(
          'Unable to access the selected file.\n\n'
          'Please select the Bhaktichart .db backup again.',
        );
      }

      // --------------------------------------------------------
      // FILE EXISTS
      // --------------------------------------------------------

      if (!await backupFile.exists()) {
        throw Exception('Selected backup file does not exist.');
      }

      // --------------------------------------------------------
      // FILE SIZE
      // --------------------------------------------------------

      final fileSize = await backupFile.length();

      if (fileSize <= 0) {
        throw Exception('The selected backup file is empty.');
      }

      // --------------------------------------------------------
      // FILE NAME
      // --------------------------------------------------------

      final originalName = pickedFile.name.toLowerCase();

      final actualName = backupFile.path.toLowerCase();

      // --------------------------------------------------------
      // EXTENSION CHECK
      //
      // We don't rely on this for validation because the service
      // will actually inspect the SQLite database.
      //
      // We only reject obvious non-database files.
      // --------------------------------------------------------

      final looksLikeDatabase =
          originalName.endsWith('.db') ||
          originalName.endsWith('.sqlite') ||
          originalName.endsWith('.sqlite3') ||
          actualName.endsWith('.db') ||
          actualName.endsWith('.sqlite') ||
          actualName.endsWith('.sqlite3');

      if (!looksLikeDatabase) {
        throw Exception(
          'Please select a Bhaktichart database backup.\n\n'
          'Supported files:\n'
          '• .db\n'
          '• .sqlite\n'
          '• .sqlite3',
        );
      }

      // --------------------------------------------------------
      // DEBUG
      // --------------------------------------------------------

      debugPrint('====================================');
      debugPrint('IMPORTING BACKUP');
      debugPrint('Original name: ${pickedFile.name}');
      debugPrint('Resolved path: ${backupFile.path}');
      debugPrint('Size: $fileSize bytes');
      debugPrint('====================================');

      // --------------------------------------------------------
      // RESTORE
      // --------------------------------------------------------

      await _backupService.restoreDatabase(backupFile);

      // --------------------------------------------------------
      // SUCCESS
      // --------------------------------------------------------

      if (!mounted) {
        return;
      }

      await _showRestartRequiredDialog();
    } catch (e, stackTrace) {
      debugPrint('====================================');
      debugPrint('IMPORT BACKUP ERROR');
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint('====================================');

      if (!mounted) {
        return;
      }

      _showError('Unable to restore backup.\n\n$e');
    } finally {
      // --------------------------------------------------------
      // DELETE TEMP IMPORT FILE
      // --------------------------------------------------------

      if (temporaryPickedFile != null) {
        try {
          if (await temporaryPickedFile.exists()) {
            await temporaryPickedFile.delete();
          }
        } catch (_) {}
      }

      // --------------------------------------------------------
      // LOADING STATE
      // --------------------------------------------------------

      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  // ============================================================
  // RESTORE CONFIRMATION
  // ============================================================

  Future<bool?> _showRestoreConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);

        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            size: 44,
            color: theme.colorScheme.error,
          ),

          title: const Text('Restore Backup?'),

          content: const Text(
            'Restoring a backup will replace the '
            'current Bhaktichart data on this device.\n\n'
            'Any data created after the backup was made '
            'will be replaced.\n\n'
            'It is recommended to export your current '
            'data before continuing.',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('CANCEL'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('RESTORE'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SUCCESS / RESTART DIALOG
  // ============================================================

  Future<void> _showRestartRequiredDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.check_circle_outline, size: 48),

          title: const Text('Restore Successful'),

          content: const Text(
            'Your Bhaktichart backup has been restored '
            'successfully.\n\n'
            'The previous screen may still contain old '
            'data in memory. Please reopen the relevant '
            'screens to see the restored data.',
          ),

          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('DONE'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    // Return to previous screen.
    Navigator.of(context).pop(true);
  }

  // ============================================================
  // SUCCESS MESSAGE
  // ============================================================

  void _showSuccess(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ============================================================
  // ERROR MESSAGE
  // ============================================================

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
  }

  // ============================================================
  // AUTOMATIC BACKUP CARD
  // ============================================================

  Widget _buildAutomaticBackupCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    size: 30,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Automatic Backup',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automatically protect your data every week.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAutomaticBackupLoading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: _automaticBackupEnabled,
                    onChanged: _isAutomaticBackupRunning
                        ? null
                        : _setAutomaticBackupEnabled,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 19,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Downloads / BhaktiChart / Backups',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Backups are stored in shared Android storage, '
                    'outside the app database.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Last automatic backup: '
                    '${_formatBackupDate(_lastAutomaticBackup)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_isBusy || _isAutomaticBackupRunning)
                    ? null
                    : _runAutomaticBackupNow,
                icon: _isAutomaticBackupRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.backup_outlined),
                label: Text(
                  _isAutomaticBackupRunning
                      ? 'Creating Automatic Backup...'
                      : 'BACK UP NOW',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BACKUP CARD
  // ============================================================

  Widget _buildBackupCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.backup_outlined,
                size: 30,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Backup My Data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(
              'Create a complete backup of your '
              'Bhaktichart data, including Sadhana, '
              'Aarti attendance, goals, notes and '
              'daily routine.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isBusy ? null : _exportBackup,
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _isExporting ? 'Creating Backup...' : 'EXPORT BACKUP',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // RESTORE CARD
  // ============================================================

  Widget _buildRestoreCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restore_outlined,
                size: 30,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Restore My Data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(
              'Restore your Sadhana data from a '
              'previously exported Bhaktichart backup.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'Restoring will replace the '
                      'current data on this device.',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _importBackup,
                icon: _isImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_isImporting ? 'Restoring...' : 'RESTORE BACKUP'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO CARD
  // ============================================================

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security_outlined, color: theme.colorScheme.primary),

                const SizedBox(width: 8),

                const Text(
                  'Your data stays with you',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              'The backup is a copy of your local '
              'Bhaktichart database. It is not uploaded '
              'to any server by Bhaktichart.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Backup & Restore',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Protect Your Sadhana',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              Text(
                'Export your data regularly so you can '
                'restore it if you change or reset your phone.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 20),

              _buildAutomaticBackupCard(context),

              const SizedBox(height: 12),

              _buildBackupCard(context),

              const SizedBox(height: 12),

              _buildRestoreCard(context),

              const SizedBox(height: 12),

              _buildInfoCard(context),
            ],
          ),
        ),
      ),
    );
  }
}
