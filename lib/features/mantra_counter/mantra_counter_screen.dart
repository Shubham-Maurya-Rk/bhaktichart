import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bhaktichart/core/utils/date_utils.dart';
import 'package:bhaktichart/models/daily_sadhana_model.dart';
import 'package:bhaktichart/models/sadhana_type_model.dart';
import 'package:bhaktichart/repositories/sadhana_repository.dart';

class MantraCounterScreen extends StatefulWidget {
  const MantraCounterScreen({super.key});

  @override
  State<MantraCounterScreen> createState() => _MantraCounterScreenState();
}

class _MantraCounterScreenState extends State<MantraCounterScreen>
    with WidgetsBindingObserver {
  static const int _mantrasPerRound = 108;
  static const String _defaultMantra =
      'Hare Krishna Hare Krishna Krishna Krishna Hare Hare '
      'Hare Rama Hare Rama Rama Rama Hare Hare';

  static const String _mantraPrefsKey = 'mantra_counter_mantra';
  static const String _buttonXPrefsKey = 'mantra_counter_button_x';
  static const String _buttonYPrefsKey = 'mantra_counter_button_y';
  static const String _counterDatePrefsKey = 'mantra_counter_date';
  static const String _counterCountPrefsKey = 'mantra_counter_count';
  static const String _counterSavedRoundsPrefsKey =
      'mantra_counter_saved_rounds';

  final SadhanaRepository _repository = SadhanaRepository();

  int? _userId;
  SadhanaTypeModel? _chantingType;

  String _mantra = _defaultMantra;
  String _counterDate = '';
  int _count = 0;
  int _savedRounds = 0;

  bool _isLoading = true;
  bool _isSaving = false;

  // Position of the large draggable increment button.
  double? _buttonX;
  double? _buttonY;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForNewDay();
    }
  }

  String _todayKey() {
    return AppDateUtils.formatDate(DateTime.now());
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedMantra = prefs.getString(_mantraPrefsKey);
      final savedDate = prefs.getString(_counterDatePrefsKey);
      final savedCount = prefs.getInt(_counterCountPrefsKey) ?? 0;
      final savedCounterRounds =
          prefs.getInt(_counterSavedRoundsPrefsKey) ?? 0;

      final user = await _repository.getUser();
      if (user == null || user.id == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final types = await _repository.getSadhanaTypes();

      SadhanaTypeModel? chanting;
      for (final type in types) {
        if (type.name.toLowerCase() == 'chanting') {
          chanting = type;
          break;
        }
      }

      final today = _todayKey();

      // The unsaved counter belongs only to today's session.
      final countForToday = savedDate == today ? savedCount : 0;

      // The counter is reset every day. The "Saved" figure shown on this
      // screen is also reset every day because it represents only rounds
      // saved from this counter, not the user's total chanting for today.
      final savedRoundsForToday =
          savedDate == today ? savedCounterRounds : 0;

      if (savedDate != today) {
        await prefs.setString(_counterDatePrefsKey, today);
        await prefs.setInt(_counterCountPrefsKey, 0);
        await prefs.setInt(_counterSavedRoundsPrefsKey, 0);
      }

      if (!mounted) return;

      setState(() {
        _userId = user.id;
        _chantingType = chanting;
        _mantra = savedMantra?.trim().isNotEmpty == true
            ? savedMantra!.trim()
            : _defaultMantra;
        _counterDate = today;
        _count = countForToday;
        _savedRounds = savedRoundsForToday;
        _buttonX = prefs.getDouble(_buttonXPrefsKey);
        _buttonY = prefs.getDouble(_buttonYPrefsKey);
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Mantra counter initialization error: $e');

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load mantra counter: $e')),
        );
      }
    }
  }

  Future<void> _checkForNewDay() async {
    if (_counterDate.isEmpty) return;

    final today = _todayKey();
    if (today == _counterDate) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_counterDatePrefsKey, today);
    await prefs.setInt(_counterCountPrefsKey, 0);

    if (!mounted) return;

    setState(() {
      _counterDate = today;
      _count = 0;
    });

    // The counter and its Saved figure both belong to the new day.
  }

  Future<void> _persistCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_counterDatePrefsKey, _counterDate);
    await prefs.setInt(_counterCountPrefsKey, _count);
  }

  void _increment() {
    if (_isSaving) return;

    setState(() {
      _count++;
    });

    _persistCount();
  }

  void _decrement() {
    if (_isSaving || _count <= 0) return;

    setState(() {
      _count--;
    });

    _persistCount();
  }

  Future<void> _saveButtonPosition() async {
    final prefs = await SharedPreferences.getInstance();

    if (_buttonX != null) {
      await prefs.setDouble(_buttonXPrefsKey, _buttonX!);
    }

    if (_buttonY != null) {
      await prefs.setDouble(_buttonYPrefsKey, _buttonY!);
    }
  }

  void _moveButton(DragUpdateDetails details, Size size) {
    const buttonSize = 180.0;
    const margin = 12.0;

    final currentX = _buttonX ?? (size.width - buttonSize) / 2;
    final currentY = _buttonY ?? size.height - buttonSize - 40;

    final nextX = (currentX + details.delta.dx).clamp(
      margin,
      size.width - buttonSize - margin,
    );

    final nextY = (currentY + details.delta.dy).clamp(
      margin,
      size.height - buttonSize - margin,
    );

    setState(() {
      _buttonX = nextX.toDouble();
      _buttonY = nextY.toDouble();
    });
  }

  Future<void> _saveRounds() async {
    if (_isSaving) return;

    if (_userId == null || _chantingType?.id == null) {
      _showMessage('Chanting Sadhana type was not found.');
      return;
    }

    final roundsToSave = _count ~/ _mantrasPerRound;

    if (roundsToSave <= 0) {
      _showMessage('Complete at least 108 mantras to save 1 round.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final today = _todayKey();

      final existing = await _repository.getSadhana(
        _userId!,
        today,
        _chantingType!.id!,
      );

      final existingRounds = existing?.value ?? 0;
      final newTotalRounds = existingRounds + roundsToSave;
      final now = DateTime.now().toIso8601String();

      final sadhana = DailySadhanaModel(
        id: existing?.id,
        userId: _userId!,
        date: today,
        sadhanaTypeId: _chantingType!.id!,
        value: newTotalRounds,
        unit: 'rounds',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await _repository.saveSadhana(sadhana);

      // Remove only the complete rounds from the local counter.
      // A partial round remains available as unsaved chanting.
      final remainingCount = _count - (roundsToSave * _mantrasPerRound);

      final prefs = await SharedPreferences.getInstance();
      // Persist the local "Saved" value separately. This is intentionally
      // NOT read from the Sadhana DB because the DB contains the user's
      // cumulative chanting for today. The counter's Saved value should
      // represent only rounds saved from this counter.
      final savedRoundsFromCounter = _savedRounds + roundsToSave;

      await prefs.setString(_counterDatePrefsKey, today);
      await prefs.setInt(_counterCountPrefsKey, remainingCount);
      await prefs.setInt(
        _counterSavedRoundsPrefsKey,
        savedRoundsFromCounter,
      );

      if (!mounted) return;

      setState(() {
        _savedRounds = savedRoundsFromCounter;
        _count = remainingCount;
        _isSaving = false;
      });

      _showMessage(
        '$roundsToSave ${roundsToSave == 1 ? 'round' : 'rounds'} saved to today\'s Sadhana.',
      );
    } catch (e) {
      debugPrint('Error saving mantra rounds: $e');

      if (!mounted) return;

      setState(() => _isSaving = false);

      _showMessage('Could not save rounds. Please try again.');
    }
  }

  Future<void> _resetCounter() async {
    if (_count == 0) return;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Counter?'),
          content: const Text(
            'This will remove all unsaved mantras from today. '
            'Rounds already saved to Daily Sadhana will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('RESET'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) return;

    setState(() {
      _count = 0;
    });

    await _persistCount();

    if (mounted) {
      _showMessage('Unsaved counter reset.');
    }
  }

  Future<void> _editMantra() async {
    final controller = TextEditingController(text: _mantra);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Mantra'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Mantra',
              hintText: 'Enter your mantra',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) return;

                Navigator.pop(dialogContext, value);
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );

    if (result == null || result.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mantraPrefsKey, result.trim());

    if (!mounted) return;

    setState(() {
      _mantra = result.trim();
    });

    _showMessage('Mantra updated.');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _savedRoundLabel {
    return _savedRounds == 1 ? 'round' : 'rounds';
  }

  String get _unsavedRoundText {
    final completeRounds = _count ~/ _mantrasPerRound;
    final remainder = _count % _mantrasPerRound;

    if (_count == 0) return '0 rounds';

    if (remainder == 0) {
      return '$completeRounds ${completeRounds == 1 ? 'round' : 'rounds'}';
    }

    return '$completeRounds.${((remainder / _mantrasPerRound) * 10).floor()} rounds';
  }

  Widget _buildStatCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounterButton(Size size) {
    const buttonSize = 180.0;

    final defaultX = (size.width - buttonSize) / 2;
    final defaultY = size.height - buttonSize - 40;

    final x = (_buttonX ?? defaultX)
        .clamp(12.0, size.width - buttonSize - 12.0)
        .toDouble();

    final y = (_buttonY ?? defaultY)
        .clamp(12.0, size.height - buttonSize - 12.0)
        .toDouble();

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _increment,
        onPanUpdate: (details) => _moveButton(details, size),
        onPanEnd: (_) => _saveButtonPosition(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary,
            boxShadow: [
              BoxShadow(
                blurRadius: 20,
                spreadRadius: 2,
                color: Colors.black.withValues(alpha: 0.16),
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.touch_app_rounded,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(height: 8),
              Text(
                'TAP',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'DRAG TO MOVE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);

    final progress = (_count % _mantrasPerRound) / _mantrasPerRound;
    final completeUnsavedRounds = _count ~/ _mantrasPerRound;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantra Counter'),
        actions: [
          IconButton(
            tooltip: 'Edit Mantra',
            onPressed: _editMantra,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Reset Counter',
            onPressed: _count == 0 ? null : _resetCounter,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 250),
              child: Column(
                children: [
                  // --------------------------------------------------------
                  // MANTRA
                  // --------------------------------------------------------
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _editMantra,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MANTRA',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme
                                          .colorScheme
                                          .onPrimaryContainer
                                          .withValues(alpha: 0.70),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _mantra,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onPrimaryContainer,
                                          fontWeight: FontWeight.w700,
                                          height: 1.45,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit mantra',
                              onPressed: _editMantra,
                              icon: const Icon(Icons.edit_outlined),
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --------------------------------------------------------
                  // CURRENT COUNT
                  // --------------------------------------------------------
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'TODAY\'S UNSAVED COUNT',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_count',
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'mantras',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: progress == 0 && _count > 0
                                  ? 1.0
                                  : progress,
                              minHeight: 9,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$completeUnsavedRounds complete • '
                            '${_count % _mantrasPerRound}/$_mantrasPerRound '
                            'towards next round',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // --------------------------------------------------------
                  // SAVED / UNSAVED
                  // Saved = only complete rounds saved from THIS counter.
                  // It is deliberately different from today's total Sadhana.
                  // --------------------------------------------------------
                  Row(
                    children: [
                      _buildStatCard(
                        context: context,
                        icon: Icons.cloud_done_outlined,
                        title: 'Saved',
                        value: '$_savedRounds',
                        subtitle: _savedRoundLabel,
                      ),
                      const SizedBox(width: 10),
                      _buildStatCard(
                        context: context,
                        icon: Icons.pending_actions_outlined,
                        title: 'Unsaved',
                        value: _unsavedRoundText,
                        subtitle: '$_count mantras',
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // --------------------------------------------------------
                  // SAVE BUTTON
                  // --------------------------------------------------------
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _isSaving || _count < _mantrasPerRound
                          ? null
                          : _saveRounds,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _count < _mantrasPerRound
                            ? 'Complete 108 Mantras to Save'
                            : 'Save $completeUnsavedRounds '
                                  '${completeUnsavedRounds == 1 ? 'Round' : 'Rounds'}',
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  OutlinedButton.icon(
                    onPressed: _count == 0 ? null : _decrement,
                    icon: const Icon(Icons.remove),
                    label: const Text('Undo Last Mantra'),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    '1 round = 108 mantras',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Tap the large button to count. '
                    'Drag it anywhere comfortable on the screen.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // --------------------------------------------------------------
            // LARGE DRAGGABLE INCREMENT BUTTON
            // --------------------------------------------------------------
            _buildCounterButton(screenSize),
          ],
        ),
      ),
    );
  }
}
