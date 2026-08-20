import 'package:flutter/material.dart';

import 'package:bhaktichart/models/goal_model.dart';
import 'package:bhaktichart/models/sadhana_type_model.dart';
import 'package:bhaktichart/repositories/sadhana_repository.dart';
import 'package:bhaktichart/features/backup_restore/backup_restore_screen.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  // ============================================================
  // REPOSITORY
  // ============================================================

  final SadhanaRepository _repository = SadhanaRepository();

  // ============================================================
  // USER
  // ============================================================

  int? _userId;
  String _userName = '';

  // ============================================================
  // SADHANA TYPES
  // ============================================================

  List<SadhanaTypeModel> _sadhanaTypes = [];

  // ============================================================
  // GOALS
  // ============================================================

  final Map<int, GoalModel?> _goals = {};

  // ============================================================
  // LOADING
  // ============================================================

  bool _isLoading = true;

  // ============================================================
  // BACKUP / RESTORE NAVIGATION
  // ============================================================

  bool _isOpeningBackup = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadGoals();
  }

  // ============================================================
  // LOAD GOALS & USER
  // ============================================================

  Future<void> _loadGoals() async {
    try {
      final user = await _repository.getUser();

      if (user == null || user.id == null) {
        return;
      }

      final types = await _repository.getSadhanaTypes();

      final Map<int, GoalModel?> goals = {};

      for (final type in types) {
        if (type.id == null) {
          continue;
        }

        goals[type.id!] = await _repository.getGoal(user.id!, type.id!);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _userId = user.id;
        _userName = user.name ?? '';
        _sadhanaTypes = types;

        _goals.clear();
        _goals.addAll(goals);
      });
    } catch (e) {
      debugPrint('Error loading goals: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // EDIT USER NAME DIALOG
  // ============================================================

  Future<void> _openEditNameDialog() async {
    final controller = TextEditingController(text: _userName);
    String? errorMessage;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Edit Profile Name',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMessage!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Your Name',
                      hintText: 'Enter your name',
                      prefixIcon: Icon(Icons.edit),
                    ),
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setDialogState(() {
                          errorMessage = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: () async {
                    final newName = controller.text.trim();
                    if (newName.isEmpty) {
                      setDialogState(() {
                        errorMessage = 'Name cannot be empty';
                      });
                      return;
                    }

                    try {
                      await _repository.updateUser(_userId!, newName);

                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        errorMessage = 'Failed to update name: $e';
                      });
                    }
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      await _loadGoals();
    }
  }

  // ============================================================
  // OPEN GOAL DIALOG
  // ============================================================

  Future<void> _openGoalDialog(SadhanaTypeModel type) async {
    if (_userId == null || type.id == null) {
      return;
    }

    final existing = _goals[type.id!];

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return GoalEditDialog(
          type: type,
          existingGoal: existing,
          userId: _userId!,
          repository: _repository,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (result == true) {
      await _loadGoals();
    }
  }

  // ============================================================
  // OPEN BACKUP & RESTORE
  // ============================================================

  Future<void> _openBackupRestore() async {
    if (_isOpeningBackup) {
      return;
    }

    setState(() {
      _isOpeningBackup = true;
    });

    try {
      final restored = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
      );

      if (!mounted) {
        return;
      }

      if (restored == true) {
        setState(() {
          _isLoading = true;
        });

        await _loadGoals();
      }
    } catch (e) {
      debugPrint('Error opening Backup & Restore: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningBackup = false;
        });
      }
    }
  }

  // ============================================================
  // FORMAT
  // ============================================================

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  // ============================================================
  // USER PROFILE CARD
  // ============================================================

  Widget _buildUserProfileCard() {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openEditNameDialog,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : '🙏',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName.isEmpty ? 'Set Your Name' : _userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to edit name',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit_outlined),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // GOAL CARD (FIXED RENDERFLEX OVERFLOW)
  // ============================================================

  Widget _buildGoalCard(SadhanaTypeModel type) {
    final goal = type.id == null ? null : _goals[type.id!];
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openGoalDialog(type),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ICON
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    type.icon ?? '🙏',
                    style: const TextStyle(fontSize: 25),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // GOAL DETAILS (Wrapped safely to prevent horizontal overflow)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (goal == null)
                      Text(
                        'No daily goal set',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        '${_formatValue(goal.targetValue)} '
                        '${goal.unit ?? ''} / day',
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ACTION ICON
              Icon(
                goal == null ? Icons.add_circle_outline : Icons.edit_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BACKUP & RESTORE CARD
  // ============================================================

  Widget _buildBackupRestoreCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isOpeningBackup ? null : _openBackupRestore,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.backup_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 27,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup & Restore',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Export your data or restore a previous backup',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              _isOpeningBackup
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadGoals,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildUserProfileCard(),
                      const Text(
                        'Daily Sadhana Goals',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Set a simple daily target for your spiritual practice.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ..._sadhanaTypes.map(_buildGoalCard),
                      const SizedBox(height: 8),
                      _buildBackupRestoreCard(context),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ==================================================================
// GOAL EDIT DIALOG
// ==================================================================

class GoalEditDialog extends StatefulWidget {
  final SadhanaTypeModel type;
  final GoalModel? existingGoal;
  final int userId;
  final SadhanaRepository repository;

  const GoalEditDialog({
    super.key,
    required this.type,
    required this.existingGoal,
    required this.userId,
    required this.repository,
  });

  @override
  State<GoalEditDialog> createState() => _GoalEditDialogState();
}

class _GoalEditDialogState extends State<GoalEditDialog> {
  late final TextEditingController _controller;
  late String _selectedUnit;

  bool _isSaving = false;
  bool _isDeleting = false;

  bool get _isReading => widget.type.name.toLowerCase() == 'reading';

  @override
  void initState() {
    super.initState();

    final existing = widget.existingGoal;
    _selectedUnit = existing?.unit ?? _defaultUnit(widget.type);

    _controller = TextEditingController(
      text: existing == null ? '' : _formatValue(existing.targetValue),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _defaultUnit(SadhanaTypeModel type) {
    switch (type.name.toLowerCase()) {
      case 'chanting':
        return 'rounds';
      case 'reading':
        return 'pages';
      case 'hearing':
        return 'minutes';
      case 'aarti':
        return 'aartis';
      default:
        return 'times';
    }
  }

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final value = double.tryParse(_controller.text.trim());

    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid goal.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now().toIso8601String();

      final goal = GoalModel(
        id: widget.existingGoal?.id,
        userId: widget.userId,
        sadhanaTypeId: widget.type.id!,
        targetValue: value,
        unit: _selectedUnit,
        isActive: true,
        createdAt: widget.existingGoal?.createdAt ?? now,
        updatedAt: now,
      );

      await widget.repository.saveGoal(goal);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save goal: $e')));
    }
  }

  Future<void> _delete() async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await widget.repository.deleteGoal(widget.userId, widget.type.id!);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to remove goal: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Text(widget.type.icon ?? '🙏', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(child: Text('${widget.type.name} Goal')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isReading) ...[
              const Text(
                'Measure reading by',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(value: 'pages', label: Text('Pages')),
                  ButtonSegment<String>(
                    value: 'shlokas',
                    label: Text('Shlokas'),
                  ),
                  ButtonSegment<String>(
                    value: 'minutes',
                    label: Text('Minutes'),
                  ),
                ],
                selected: {_selectedUnit},
                onSelectionChanged: (values) {
                  if (values.isEmpty) return;

                  setState(() {
                    _selectedUnit = values.first;
                  });
                },
              ),
              const SizedBox(height: 20),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Daily target',
                suffixText: _selectedUnit,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (widget.existingGoal != null) ...[
              const SizedBox(height: 12),
              Text(
                'Current goal: '
                '${_formatValue(widget.existingGoal!.targetValue)} '
                '${widget.existingGoal!.unit ?? ''}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.existingGoal != null)
          TextButton(
            onPressed: (_isDeleting || _isSaving) ? null : _delete,
            child: _isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('REMOVE'),
          ),
        TextButton(
          onPressed: (_isSaving || _isDeleting)
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: (_isSaving || _isDeleting) ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('SAVE'),
        ),
      ],
    );
  }
}
