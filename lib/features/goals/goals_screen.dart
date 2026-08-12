import 'package:flutter/material.dart';

import 'package:bhaktichart/models/goal_model.dart';
import 'package:bhaktichart/models/sadhana_type_model.dart';
import 'package:bhaktichart/repositories/sadhana_repository.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final SadhanaRepository _repository = SadhanaRepository();

  int? _userId;

  List<SadhanaTypeModel> _sadhanaTypes = [];

  final Map<int, GoalModel?> _goals = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _loadGoals();
  }

  // ============================================================
  // LOAD
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

      if (!mounted) return;

      setState(() {
        _userId = user.id;
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

    if (!mounted) return;

    if (result == true) {
      await _loadGoals();
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
  // GOAL CARD
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
                    ),

                    const SizedBox(height: 4),

                    if (goal == null)
                      Text(
                        'No daily goal set',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Text(
                        '${_formatValue(goal.targetValue)} ${goal.unit ?? ''} / day',
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),

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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Goals',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 20),

                    ..._sadhanaTypes.map(_buildGoalCard),
                  ],
                ),
              ),
            ),
    );
  }
}

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

  // ============================================================
  // DEFAULT UNIT
  // ============================================================

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
  // SAVE
  // ============================================================

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

  // ============================================================
  // DELETE
  // ============================================================

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

  // ============================================================
  // BUILD
  // ============================================================

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
                  if (values.isEmpty) {
                    return;
                  }

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
              : () {
                  Navigator.of(context).pop(false);
                },
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
