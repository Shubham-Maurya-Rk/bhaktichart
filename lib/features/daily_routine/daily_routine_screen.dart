import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/daily_routine.dart';
import '../../models/daily_routine_goal.dart';
import '../../repositories/daily_routine_repository.dart';

class DailyRoutineScreen extends StatefulWidget {
  final int userId;

  const DailyRoutineScreen({super.key, required this.userId});

  @override
  State<DailyRoutineScreen> createState() => _DailyRoutineScreenState();
}

class _DailyRoutineScreenState extends State<DailyRoutineScreen> {
  // ============================================================
  // REPOSITORY
  // ============================================================

  final DailyRoutineRepository _repository = DailyRoutineRepository();

  // ============================================================
  // CALENDAR
  // ============================================================

  DateTime _focusedDay = DateTime.now();

  DateTime _selectedDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  CalendarFormat _calendarFormat = CalendarFormat.month;

  // ============================================================
  // DATA
  // ============================================================

  List<DailyRoutine> _monthRoutines = [];

  DailyRoutine? _selectedRoutine;

  DailyRoutineGoal? _goal;

  bool _isLoading = true;
  bool _isSaving = false;

  // ============================================================
  // STATISTICS PERIOD
  // ============================================================

  _StatisticsPeriod _statisticsPeriod = _StatisticsPeriod.last7Days;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ============================================================
  // DATE HELPERS
  // ============================================================

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime get _today => _dateOnly(DateTime.now());

  bool _isFuture(DateTime date) {
    return _dateOnly(date).isAfter(_today);
  }

  bool _isToday(DateTime date) {
    return _dateOnly(date).isAtSameMomentAs(_today);
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final routines = await _repository.getMonth(widget.userId, _focusedDay);

      final selected = await _repository.getByDate(widget.userId, _selectedDay);

      final goal = await _repository.getGoal(widget.userId);

      if (!mounted) return;

      setState(() {
        _monthRoutines = routines;
        _selectedRoutine = selected;
        _goal = goal;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showError('Unable to load daily routine: $e');
    }
  }

  // ============================================================
  // REFRESH SELECTED DAY
  // ============================================================

  Future<void> _refreshSelectedDay() async {
    try {
      final routine = await _repository.getByDate(widget.userId, _selectedDay);

      final routines = await _repository.getMonth(widget.userId, _focusedDay);

      if (!mounted) return;

      setState(() {
        _selectedRoutine = routine;
        _monthRoutines = routines;
      });
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to refresh routine.');
    }
  }

  // ============================================================
  // FIND ROUTINE
  // ============================================================

  DailyRoutine? _routineForDay(DateTime day) {
    final key = _dateOnly(day);

    for (final routine in _monthRoutines) {
      if (_dateOnly(routine.date).isAtSameMomentAs(key)) {
        return routine;
      }
    }

    return null;
  }

  // ============================================================
  // CHANGE SELECTED DAY
  // ============================================================

  Future<void> _changeSelectedDay(int offset) async {
    final newDay = _dateOnly(_selectedDay.add(Duration(days: offset)));

    // ----------------------------------------------------------
    // Never allow future dates.
    // ----------------------------------------------------------

    if (_isFuture(newDay)) {
      _showMessage('Future dates cannot be selected.');
      return;
    }

    final routine = await _repository.getByDate(widget.userId, newDay);

    if (!mounted) return;

    setState(() {
      _selectedDay = newDay;
      _focusedDay = newDay;
      _selectedRoutine = routine;
    });

    // ----------------------------------------------------------
    // Load month if required.
    // ----------------------------------------------------------

    final selectedMonth = DateTime(newDay.year, newDay.month);

    final focusedMonth = DateTime(_focusedDay.year, _focusedDay.month);

    if (selectedMonth != focusedMonth) {
      final routines = await _repository.getMonth(widget.userId, newDay);

      if (!mounted) return;

      setState(() {
        _monthRoutines = routines;
      });
    }
  }

  // ============================================================
  // SELECT WAKE TIME
  // ============================================================

  Future<void> _selectWakeUpTime() async {
    if (_isFuture(_selectedDay)) {
      _showMessage('Future dates cannot be filled.');
      return;
    }

    final initialTime = _selectedRoutine?.wakeUpTime != null
        ? TimeOfDay(
            hour: _selectedRoutine!.wakeUpTime!.hour,
            minute: _selectedRoutine!.wakeUpTime!.minute,
          )
        : const TimeOfDay(hour: 6, minute: 0);

    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Select wake-up time',
    );

    if (selected == null) return;

    await _saveWakeTime(selected);
  }

  // ============================================================
  // SELECT SLEEP TIME
  // ============================================================

  Future<void> _selectSleepTime() async {
    if (_isFuture(_selectedDay)) {
      _showMessage('Future dates cannot be filled.');
      return;
    }

    final initialTime = _selectedRoutine?.sleepTime != null
        ? TimeOfDay(
            hour: _selectedRoutine!.sleepTime!.hour,
            minute: _selectedRoutine!.sleepTime!.minute,
          )
        : const TimeOfDay(hour: 22, minute: 0);

    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Select sleep time',
    );

    if (selected == null) return;

    await _saveSleepTime(selected);
  }

  // ============================================================
  // SAVE WAKE TIME
  // ============================================================

  Future<void> _saveWakeTime(TimeOfDay time) async {
    if (_isFuture(_selectedDay)) {
      _showMessage('Future dates cannot be filled.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final dateTime = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        time.hour,
        time.minute,
      );

      await _repository.updateWakeTime(
        userId: widget.userId,
        date: _selectedDay,
        time: dateTime,
      );

      await _refreshSelectedDay();

      if (!mounted) return;

      _showMessage('Wake-up time saved.');
    } catch (e) {
      if (!mounted) return;

      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // SAVE SLEEP TIME
  // ============================================================

  Future<void> _saveSleepTime(TimeOfDay time) async {
    if (_isFuture(_selectedDay)) {
      _showMessage('Future dates cannot be filled.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final dateTime = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        time.hour,
        time.minute,
      );

      await _repository.updateSleepTime(
        userId: widget.userId,
        date: _selectedDay,
        time: dateTime,
      );

      await _refreshSelectedDay();

      if (!mounted) return;

      _showMessage('Sleep time saved.');
    } catch (e) {
      if (!mounted) return;

      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // DELETE ROUTINE
  // ============================================================

  Future<void> _deleteRoutine() async {
    final routine = _selectedRoutine;

    if (routine == null || routine.id == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete routine?'),
          content: Text(
            'Delete wake-up and sleep data for '
            '${_formatDate(_selectedDay)}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await _repository.delete(routine.id!);

      await _refreshSelectedDay();

      if (!mounted) return;

      _showMessage('Routine deleted.');
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to delete routine.');
    }
  }

  // ============================================================
  // GOALS
  // ============================================================

  Future<void> _editGoals() async {
    int wakeHour = _goal?.wakeUpHour ?? 6;
    int wakeMinute = _goal?.wakeUpMinute ?? 0;

    int sleepHour = _goal?.sleepHour ?? 22;
    int sleepMinute = _goal?.sleepMinute ?? 0;

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final wakeText = _formatTime(
              DateTime(2000, 1, 1, wakeHour, wakeMinute),
            );

            final sleepText = _formatTime(
              DateTime(2000, 1, 1, sleepHour, sleepMinute),
            );

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.flag_rounded),
                  SizedBox(width: 10),
                  Text('Routine Goals'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _goalTimePickerRow(
                    context: context,
                    icon: Icons.wb_sunny_rounded,
                    title: 'Wake-up goal',
                    value: wakeText,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: wakeHour,
                          minute: wakeMinute,
                        ),
                        helpText: 'Wake-up goal',
                      );

                      if (picked == null) return;

                      setDialogState(() {
                        wakeHour = picked.hour;
                        wakeMinute = picked.minute;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _goalTimePickerRow(
                    context: context,
                    icon: Icons.nightlight_round,
                    title: 'Sleep goal',
                    value: sleepText,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: sleepHour,
                          minute: sleepMinute,
                        ),
                        helpText: 'Sleep goal',
                      );

                      if (picked == null) return;

                      setDialogState(() {
                        sleepHour = picked.hour;
                        sleepMinute = picked.minute;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'wake_hour': wakeHour,
                      'wake_minute': wakeMinute,
                      'sleep_hour': sleepHour,
                      'sleep_minute': sleepMinute,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    try {
      final now = DateTime.now();

      final goal = DailyRoutineGoal(
        id: _goal?.id,
        userId: widget.userId,
        wakeUpHour: result['wake_hour']!,
        wakeUpMinute: result['wake_minute']!,
        sleepHour: result['sleep_hour']!,
        sleepMinute: result['sleep_minute']!,
        createdAt: _goal?.createdAt ?? now,
        updatedAt: now,
      );

      await _repository.saveGoal(goal);

      final savedGoal = await _repository.getGoal(widget.userId);

      if (!mounted) return;

      setState(() {
        _goal = savedGoal;
      });

      _showMessage('Goals updated.');
    } catch (e) {
      if (!mounted) return;

      _showError('Unable to save goals: $e');
    }
  }

  // ============================================================
  // GOAL TIME PICKER ROW
  // ============================================================

  Widget _goalTimePickerRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CALENDAR CELL
  // ============================================================

  Widget _buildCalendarCell(BuildContext context, DateTime day) {
    final routine = _routineForDay(day);

    final hasWake = routine?.wakeUpTime != null;
    final hasSleep = routine?.sleepTime != null;

    final isFuture = _isFuture(day);

    final selected = _dateOnly(day).isAtSameMomentAs(_dateOnly(_selectedDay));

    final today = _isToday(day);

    final colorScheme = Theme.of(context).colorScheme;

    // ----------------------------------------------------------
    // Clickable cells get a visible border.
    // Future dates are not clickable and appear disabled.
    // ----------------------------------------------------------

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: selected
            ? colorScheme.primary.withOpacity(0.12)
            : colorScheme.surface,
        border: Border.all(
          color: selected
              ? colorScheme.primary
              : isFuture
              ? colorScheme.outlineVariant.withOpacity(0.25)
              : today
              ? colorScheme.primary.withOpacity(0.55)
              : colorScheme.outlineVariant,
          width: selected ? 1.7 : 0.8,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 5,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: today || selected
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: isFuture
                    ? colorScheme.onSurface.withOpacity(0.30)
                    : colorScheme.onSurface,
              ),
            ),
          ),

          Positioned(
            right: 4,
            bottom: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasWake)
                  _calendarIcon(Icons.wb_sunny_rounded, Colors.orange),
                if (hasWake && hasSleep) const SizedBox(width: 2),
                if (hasSleep)
                  _calendarIcon(Icons.nightlight_round, Colors.indigo),
              ],
            ),
          ),

          if (routine?.sleepDuration != null)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      routine!.formattedSleepDuration,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _calendarIcon(IconData icon, Color color) {
    return Icon(icon, size: 13, color: color);
  }

  // ============================================================
  // SELECTED DAY CARD
  // ============================================================

  Widget _buildSelectedDayCard(BuildContext context) {
    final routine = _selectedRoutine;

    final isFuture = _isFuture(_selectedDay);

    final wake = routine?.wakeUpTime;
    final sleep = routine?.sleepTime;

    final duration = routine?.sleepDuration;

    final canGoPrevious = !_selectedDay.isAtSameMomentAs(DateTime(2020, 1, 1));

    final canGoNext = !_isToday(_selectedDay);

    // ----------------------------------------------------------
    // Swipe area.
    //
    // Left swipe  -> next day
    // Right swipe -> previous day
    // ----------------------------------------------------------

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;

        if (velocity < -250 && canGoNext) {
          _changeSelectedDay(1);
        } else if (velocity > 250 && canGoPrevious) {
          _changeSelectedDay(-1);
        }
      },
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: canGoPrevious
                        ? () => _changeSelectedDay(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _formatDate(_selectedDay),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isFuture
                              ? 'Future date'
                              : _isToday(_selectedDay)
                              ? 'Today'
                              : 'Daily routine',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    tooltip: 'Next day',
                    onPressed: canGoNext ? () => _changeSelectedDay(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              if (routine != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Delete',
                    onPressed: isFuture ? null : _deleteRoutine,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _timeCard(
                      context: context,
                      icon: Icons.wb_sunny_rounded,
                      iconColor: Colors.orange,
                      title: 'Wake up',
                      value: wake == null
                          ? '--'
                          : DailyRoutine.formatTime(wake),
                      goal: _goal == null ? null : _goal!.wakeUpTimeText,
                      onTap: isFuture ? null : _selectWakeUpTime,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _timeCard(
                      context: context,
                      icon: Icons.nightlight_round,
                      iconColor: Colors.indigo,
                      title: 'Sleep',
                      value: sleep == null
                          ? '--'
                          : DailyRoutine.formatTime(sleep),
                      goal: _goal == null ? null : _goal!.sleepTimeText,
                      onTap: isFuture ? null : _selectSleepTime,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.08),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bedtime_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Sleep duration',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      duration == null ? '--' : _formatDuration(duration),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              if (_goal != null && duration != null) ...[
                const SizedBox(height: 10),
                _buildDailyPerformance(context, routine!),
              ],

              if (isFuture) ...[
                const SizedBox(height: 12),
                _futureDateWarning(context),
              ],

              const SizedBox(height: 6),

              Center(
                child: Text(
                  'Swipe left/right to change day',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DAILY PERFORMANCE
  // ============================================================

  Widget _buildDailyPerformance(BuildContext context, DailyRoutine routine) {
    final goalDuration = _goalSleepDuration;

    if (goalDuration == null) {
      return const SizedBox.shrink();
    }

    final actual = routine.sleepDuration;

    if (actual == null) {
      return const SizedBox.shrink();
    }

    final actualMinutes = actual.inMinutes;
    final goalMinutes = goalDuration.inMinutes;

    final difference = actualMinutes - goalMinutes;

    final percentage = goalMinutes == 0 ? 0.0 : actualMinutes / goalMinutes;

    final clamped = percentage.clamp(0.0, 1.5);

    final isGood = actualMinutes >= goalMinutes;

    final color = isGood ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.08),
      ),
      child: Row(
        children: [
          Icon(
            isGood ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isGood ? 'Sleep goal achieved' : 'Below sleep goal',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  '${difference >= 0 ? '+' : ''}'
                  '${_formatMinutesDifference(difference)} '
                  'vs ${_formatDuration(goalDuration)} goal',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: clamped / 1.5,
                  strokeWidth: 4,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '${(percentage * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TIME CARD
  // ============================================================

  Widget _timeCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String? goal,
    required VoidCallback? onTap,
  }) {
    final hasValue = value != '--';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 21),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (onTap != null) const Icon(Icons.edit_rounded, size: 16),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: hasValue
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (goal != null) ...[
              const SizedBox(height: 4),
              Text(
                'Goal: $goal',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FUTURE WARNING
  // ============================================================

  Widget _futureDateWarning(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.orange.withOpacity(0.10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Future dates cannot be filled.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GOAL CARD
  // ============================================================

  Widget _buildGoalCard(BuildContext context) {
    final goal = _goal;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_rounded),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Daily Goals',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit goals',
                  onPressed: _editGoals,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _goalBox(
                    context,
                    icon: Icons.wb_sunny_rounded,
                    color: Colors.orange,
                    title: 'Wake-up',
                    value: goal?.wakeUpTimeText ?? '6:00 AM',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _goalBox(
                    context,
                    icon: Icons.nightlight_round,
                    color: Colors.indigo,
                    title: 'Sleep',
                    value: goal?.sleepTimeText ?? '10:00 PM',
                  ),
                ),
              ],
            ),

            if (_goalSleepDuration != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.06),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_bottom_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Target sleep duration',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _formatDuration(_goalSleepDuration!),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _goalBox(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GOAL SLEEP DURATION
  // ============================================================

  Duration? get _goalSleepDuration {
    if (_goal == null) {
      return null;
    }

    final sleep = DateTime(2000, 1, 1, _goal!.sleepHour, _goal!.sleepMinute);

    DateTime wake = DateTime(
      2000,
      1,
      1,
      _goal!.wakeUpHour,
      _goal!.wakeUpMinute,
    );

    if (!wake.isAfter(sleep)) {
      wake = wake.add(const Duration(days: 1));
    }

    final duration = wake.difference(sleep);

    if (duration.isNegative || duration > const Duration(hours: 24)) {
      return null;
    }

    return duration;
  }

  // ============================================================
  // STATISTICS SECTION
  // ============================================================

  Widget _buildStatisticsSection(BuildContext context) {
    return FutureBuilder<_RoutineStatistics>(
      future: _calculateStatistics(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return _errorCard(context, 'Unable to calculate statistics.');
        }

        final stats = snapshot.data;

        if (stats == null) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Statistics',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildStatisticsPeriodDropdown(context),
              ],
            ),

            const SizedBox(height: 12),

            _buildSummaryCards(context, stats),

            const SizedBox(height: 16),

            _buildSleepChart(context, stats),

            const SizedBox(height: 16),

            _buildWakeChart(context, stats),

            const SizedBox(height: 16),

            _buildSleepTimeChart(context, stats),

            const SizedBox(height: 16),

            _buildPeriodStatistics(context, stats),
          ],
        );
      },
    );
  }

  // ============================================================
  // PERIOD DROPDOWN
  // ============================================================

  Widget _buildStatisticsPeriodDropdown(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_StatisticsPeriod>(
          value: _statisticsPeriod,
          isDense: true,
          items: const [
            DropdownMenuItem(
              value: _StatisticsPeriod.last7Days,
              child: Text('7 Days'),
            ),
            DropdownMenuItem(
              value: _StatisticsPeriod.last30Days,
              child: Text('30 Days'),
            ),
            DropdownMenuItem(
              value: _StatisticsPeriod.year,
              child: Text('Year'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              _statisticsPeriod = value;
            });
          },
        ),
      ),
    );
  }

  // ============================================================
  // CALCULATE STATISTICS
  // ============================================================

  Future<_RoutineStatistics> _calculateStatistics() async {
    final now = _today;

    final routines = <DailyRoutine>[];

    // ----------------------------------------------------------
    // Load one year of historical data.
    // ----------------------------------------------------------

    for (int i = 0; i < 365; i++) {
      final date = now.subtract(Duration(days: i));

      final routine = await _repository.getByDate(widget.userId, date);

      if (routine != null) {
        routines.add(routine);
      }
    }

    return _RoutineStatistics(routines: routines, today: now, goal: _goal);
  }

  // ============================================================
  // SUMMARY CARDS
  // ============================================================

  Widget _buildSummaryCards(BuildContext context, _RoutineStatistics stats) {
    final periodRoutines = stats.periodRoutines(_statisticsPeriod);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,

          // Slightly taller cards to avoid RenderFlex overflow,
          // especially with larger system font sizes.
          childAspectRatio: 1.55,

          children: [
            _statCard(
              context,
              title: 'Avg Sleep',
              value: stats.averageSleepForPeriod(_statisticsPeriod),
              goal: stats.sleepGoalText,
              isGoalMet: stats.sleepGoalPerformance(_statisticsPeriod) != null
                  ? stats.sleepGoalPerformance(_statisticsPeriod)! >= 100
                  : null,
              icon: Icons.bedtime_rounded,
            ),

            _statCard(
              context,
              title: 'Avg Wake',
              value: stats.averageWakeForPeriod(_statisticsPeriod),
              goal: stats.wakeGoalText,
              isGoalMet: stats.wakeGoalPerformance(_statisticsPeriod) != null
                  ? stats.wakeGoalPerformance(_statisticsPeriod)! >= 100
                  : null,
              icon: Icons.wb_sunny_rounded,
            ),

            _statCard(
              context,
              title: 'Sleep Performance',
              value: stats.sleepPerformanceText(_statisticsPeriod),
              goal: stats.sleepPerformanceStatus(_statisticsPeriod),
              isGoalMet: stats.sleepGoalPerformance(_statisticsPeriod) != null
                  ? stats.sleepGoalPerformance(_statisticsPeriod)! >= 100
                  : null,
              icon: Icons.track_changes_rounded,
            ),

            _statCard(
              context,
              title: 'Recorded Days',
              value: '${periodRoutines.length}',
              goal: 'of ${stats.periodDays(_statisticsPeriod)} days',
              icon: Icons.calendar_month_rounded,
            ),
          ],
        ),

        const SizedBox(height: 12),

        _buildOverallPerformance(context, stats),
      ],
    );
  }

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _statCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    String? goal,
    bool? isGoalMet,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ------------------------------------------------------
            // ICON
            // ------------------------------------------------------
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: colorScheme.primary),
            ),

            const SizedBox(width: 10),

            // ------------------------------------------------------
            // CONTENT
            // ------------------------------------------------------
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 2),

                  // FittedBox prevents long values such as
                  // "12h 30m" or "125%" from overflowing.
                  SizedBox(
                    height: 25,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  if (goal != null) ...[
                    const SizedBox(height: 1),

                    Row(
                      children: [
                        if (isGoalMet != null) ...[
                          Icon(
                            isGoalMet
                                ? Icons.check_circle_rounded
                                : Icons.flag_rounded,
                            size: 11,
                            color: isGoalMet
                                ? Colors.green
                                : colorScheme.onSurfaceVariant,
                          ),

                          const SizedBox(width: 3),
                        ],

                        Expanded(
                          child: Text(
                            goal,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  } // ============================================================
  // OVERALL PERFORMANCE
  // ============================================================

  Widget _buildOverallPerformance(
    BuildContext context,
    _RoutineStatistics stats,
  ) {
    final percentage = stats.sleepGoalPerformance(_statisticsPeriod);

    if (percentage == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Row(
          children: [
            Icon(Icons.insights_rounded),
            SizedBox(width: 10),
            Expanded(child: Text('Add sleep records to see goal performance.')),
          ],
        ),
      );
    }

    final color = percentage >= 100
        ? Colors.green
        : percentage >= 90
        ? Colors.orange
        : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
            ),
            alignment: Alignment.center,
            child: Text(
              '${percentage.round()}%',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sleep Goal Performance',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  percentage >= 100
                      ? 'You are meeting your sleep-duration goal.'
                      : 'Your average sleep is below your target.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SLEEP CHART
  // ============================================================

  Widget _buildSleepChart(BuildContext context, _RoutineStatistics stats) {
    final points = stats.chartSleepPoints(_statisticsPeriod);

    final goalHours = stats.sleepGoalHours;

    final maxActual = points
        .map((e) => e.hours)
        .whereType<double>()
        .fold<double>(0, math.max);

    final maxY = math.max(
      12.0,
      math.max(maxActual + 1.0, (goalHours ?? 0.0) + 1.0).ceilToDouble(),
    );

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sleep Duration',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (goalHours != null)
                  _chartLegend(
                    context,
                    Colors.red,
                    'Goal ${goalHours.toStringAsFixed(1)}h',
                  ),
              ],
            ),

            const SizedBox(height: 5),

            Text(
              _statisticsPeriod.chartSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 250,
              child: points.isEmpty
                  ? _emptyChart()
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: goalHours == null
                              ? []
                              : [
                                  HorizontalLine(
                                    y: goalHours,
                                    color: Colors.red,
                                    strokeWidth: 2,
                                    dashArray: [7, 5],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                        bottom: 4,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                      labelResolver: (_) => 'Goal',
                                    ),
                                  ),
                                ],
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              interval: 2,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '${value.toInt()}h',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: _bottomTitleInterval(points.length),
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();

                                if (index < 0 || index >= points.length) {
                                  return const SizedBox();
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    points[index].label,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _sleepSpots(points),
                            isCurved: true,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.08),
                            ),
                            color: Theme.of(context).colorScheme.primary,
                            isStrokeCapRound: true,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _sleepSpots(List<_ChartPoint> points) {
    final spots = <FlSpot>[];

    for (int i = 0; i < points.length; i++) {
      final value = points[i].hours;

      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
    }

    return spots;
  }

  // ============================================================
  // WAKE CHART
  // ============================================================

  Widget _buildWakeChart(BuildContext context, _RoutineStatistics stats) {
    final points = stats.chartWakePoints(_statisticsPeriod);

    final goalHour = stats.wakeGoalHour;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Wake-up Time',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (goalHour != null)
                  _chartLegend(
                    context,
                    Colors.red,
                    'Goal ${_formatDecimalHour(goalHour)}',
                  ),
              ],
            ),

            const SizedBox(height: 5),

            Text(
              'Wake-up times are shown using the actual clock time.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 250,
              child: points.isEmpty
                  ? _emptyChart()
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 24,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: goalHour == null
                              ? []
                              : [
                                  HorizontalLine(
                                    y: goalHour,
                                    color: Colors.red,
                                    strokeWidth: 2,
                                    dashArray: [7, 5],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                        bottom: 4,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                      labelResolver: (_) => 'Goal',
                                    ),
                                  ),
                                ],
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              interval: 4,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  _hourLabel(value),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: _bottomTitleInterval(points.length),
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();

                                if (index < 0 || index >= points.length) {
                                  return const SizedBox();
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    points[index].label,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _wakeSpots(points),
                            isCurved: true,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            color: Colors.orange,
                            isStrokeCapRound: true,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _wakeSpots(List<_WakeChartPoint> points) {
    final spots = <FlSpot>[];

    for (int i = 0; i < points.length; i++) {
      final value = points[i].hour;

      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
    }

    return spots;
  }

  // ============================================================
  // SLEEP TIME CHART
  // ============================================================

  Widget _buildSleepTimeChart(BuildContext context, _RoutineStatistics stats) {
    final points = stats.chartSleepTimePoints(_statisticsPeriod);
    final goalHour = stats.sleepGoalHour;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sleep Time',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (goalHour != null)
                  _chartLegend(
                    context,
                    Colors.indigo,
                    'Goal ${_formatDecimalHour(goalHour)}',
                  ),
              ],
            ),

            const SizedBox(height: 5),

            Text(
              'Your recorded bedtime by day.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 250,
              child: points.isEmpty
                  ? _emptyChart()
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 24,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: goalHour == null
                              ? []
                              : [
                                  HorizontalLine(
                                    y: goalHour,
                                    color: Colors.red,
                                    strokeWidth: 2,
                                    dashArray: [7, 5],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                        bottom: 4,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                      labelResolver: (_) => 'Goal',
                                    ),
                                  ),
                                ],
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              interval: 4,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  _hourLabel(value),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: _bottomTitleInterval(points.length),
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();

                                if (index < 0 || index >= points.length) {
                                  return const SizedBox();
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    points[index].label,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _sleepTimeSpots(points),
                            isCurved: true,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            color: Colors.indigo,
                            isStrokeCapRound: true,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _sleepTimeSpots(List<_SleepTimeChartPoint> points) {
    final spots = <FlSpot>[];

    for (int i = 0; i < points.length; i++) {
      final value = points[i].hour;

      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
    }

    return spots;
  }

  // ============================================================
  // CHART LEGEND
  // ============================================================

  Widget _chartLegend(BuildContext context, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PERIOD STATISTICS
  // ============================================================

  Widget _buildPeriodStatistics(
    BuildContext context,
    _RoutineStatistics stats,
  ) {
    final period = _statisticsPeriod;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Period Statistics',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  period.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            _periodRow(
              context,
              'Recorded days',
              stats.periodRoutines(period).length,
              'of ${stats.periodDays(period)} days',
            ),

            const Divider(height: 22),

            _periodRow(
              context,
              'Average sleep',
              null,
              stats.averageSleepForPeriod(period),
              trailing: stats.sleepGoalText,
            ),

            const Divider(height: 22),

            _periodRow(
              context,
              'Average wake-up',
              null,
              stats.averageWakeForPeriod(period),
              trailing: stats.wakeGoalText,
            ),

            const Divider(height: 22),

            _periodRow(
              context,
              'Sleep performance',
              null,
              stats.sleepPerformanceText(period),
              trailing: stats.sleepPerformanceStatus(period),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodRow(
    BuildContext context,
    String title,
    int? count,
    String value, {
    String? trailing,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (count != null)
              Text(
                '$count recorded',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY CHART
  // ============================================================

  Widget _emptyChart() {
    return const Center(
      child: Text(
        'Not enough data yet',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Routine'),
        actions: [
          IconButton(
            tooltip: 'Goals',
            onPressed: _editGoals,
            icon: const Icon(Icons.flag_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ==================================================
                    // CALENDAR
                    // ==================================================
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TableCalendar(
                          firstDay: DateTime(2020, 1, 1),
                          lastDay: _today,
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) {
                            return _dateOnly(
                              day,
                            ).isAtSameMomentAs(_dateOnly(_selectedDay));
                          },
                          calendarFormat: _calendarFormat,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Month',
                          },
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          rowHeight: 52,
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            weekendStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          calendarStyle: const CalendarStyle(
                            outsideDaysVisible: false,
                            isTodayHighlighted: false,
                            defaultDecoration: BoxDecoration(),
                            weekendDecoration: BoxDecoration(),
                            selectedDecoration: BoxDecoration(),
                            todayDecoration: BoxDecoration(),
                          ),
                          calendarBuilders: CalendarBuilders(
                            defaultBuilder: (context, day, focusedDay) {
                              return _buildCalendarCell(context, day);
                            },
                            selectedBuilder: (context, day, focusedDay) {
                              return _buildCalendarCell(context, day);
                            },
                            todayBuilder: (context, day, focusedDay) {
                              return _buildCalendarCell(context, day);
                            },
                          ),
                          onDaySelected: (selectedDay, focusedDay) async {
                            if (_isFuture(selectedDay)) {
                              _showMessage('Future dates cannot be filled.');
                              return;
                            }

                            setState(() {
                              _selectedDay = _dateOnly(selectedDay);
                              _focusedDay = focusedDay;
                            });

                            final routine = await _repository.getByDate(
                              widget.userId,
                              _selectedDay,
                            );

                            if (!mounted) return;

                            setState(() {
                              _selectedRoutine = routine;
                            });
                          },
                          onPageChanged: (focusedDay) async {
                            _focusedDay = focusedDay;

                            final routines = await _repository.getMonth(
                              widget.userId,
                              focusedDay,
                            );

                            if (!mounted) return;

                            setState(() {
                              _monthRoutines = routines;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ==================================================
                    // SELECTED DAY
                    // ==================================================
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _buildSelectedDayCard(context),
                    ),

                    const SizedBox(height: 14),

                    // ==================================================
                    // GOALS
                    // ==================================================
                    _buildGoalCard(context),

                    const SizedBox(height: 24),

                    // ==================================================
                    // STATISTICS
                    // ==================================================
                    _buildStatisticsSection(context),
                  ],
                ),
              ),
            ),
      bottomSheet: _isSaving ? const LinearProgressIndicator() : null,
    );
  }

  // ============================================================
  // FORMAT DATE
  // ============================================================

  String _formatDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${weekdays[date.weekday - 1]}, '
        '${date.day} ${months[date.month - 1]} '
        '${date.year}';
  }

  // ============================================================
  // FORMAT TIME
  // ============================================================

  String _formatTime(DateTime time) {
    return DailyRoutine.formatTime(time);
  }

  // ============================================================
  // FORMAT DURATION
  // ============================================================

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    if (hours == 0) {
      return '${minutes}m';
    }

    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}m';
  }

  // ============================================================
  // FORMAT DIFFERENCE
  // ============================================================

  String _formatMinutesDifference(int minutes) {
    final absolute = minutes.abs();

    final hours = absolute ~/ 60;

    final remaining = absolute % 60;

    if (hours == 0) {
      return '${remaining}m';
    }

    if (remaining == 0) {
      return '${hours}h';
    }

    return '${hours}h ${remaining}m';
  }

  // ============================================================
  // HOUR LABEL
  // ============================================================

  String _hourLabel(double value) {
    final hour = value.toInt() % 24;

    final h = hour % 12 == 0 ? 12 : hour % 12;

    final period = hour >= 12 ? 'PM' : 'AM';

    return '$h $period';
  }

  // ============================================================
  // DECIMAL HOUR
  // ============================================================

  String _formatDecimalHour(double value) {
    final totalMinutes = (value * 60).round();

    final hour = (totalMinutes ~/ 60) % 24;

    final minute = totalMinutes % 60;

    return DailyRoutine.formatTime(DateTime(2000, 1, 1, hour, minute));
  }

  // ============================================================
  // BOTTOM TITLE INTERVAL
  // ============================================================

  double _bottomTitleInterval(int length) {
    if (length <= 10) {
      return 1;
    }

    if (length <= 31) {
      return 5;
    }

    if (length <= 100) {
      return 15;
    }

    return 30;
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _errorCard(BuildContext context, String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STATISTICS PERIOD
// ============================================================================

enum _StatisticsPeriod { last7Days, last30Days, year }

extension _StatisticsPeriodExtension on _StatisticsPeriod {
  String get label {
    switch (this) {
      case _StatisticsPeriod.last7Days:
        return '7 Days';

      case _StatisticsPeriod.last30Days:
        return '30 Days';

      case _StatisticsPeriod.year:
        return 'Year';
    }
  }

  String get chartSubtitle {
    switch (this) {
      case _StatisticsPeriod.last7Days:
        return 'Last 7 days';

      case _StatisticsPeriod.last30Days:
        return 'Last 30 days';

      case _StatisticsPeriod.year:
        return 'Last 365 days';
    }
  }
}

// ============================================================================
// STATISTICS MODEL
// ============================================================================

class _RoutineStatistics {
  final List<DailyRoutine> routines;
  final DateTime today;
  final DailyRoutineGoal? goal;

  _RoutineStatistics({
    required this.routines,
    required this.today,
    required this.goal,
  });

  // ============================================================
  // WAKE PERFORMANCE
  // ============================================================

  double? wakeGoalPerformance(_StatisticsPeriod period) {
    final goal = wakeGoalHour;

    if (goal == null) {
      return null;
    }

    final average = _averageWakeTime(periodRoutines(period));

    if (average == null) {
      return null;
    }

    final actual = average.hour + average.minute / 60.0;

    // Earlier than or equal to the goal = 100% or better.
    //
    // Example:
    // Goal  = 6:00 AM
    // Actual = 5:45 AM -> achieved
    //
    // Actual = 6:30 AM -> below goal
    final difference = actual - goal;

    if (difference <= 0) {
      return 100.0;
    }

    // Every hour late reduces performance by 100%.
    // 30 minutes late = 50%.
    final performance = 100.0 - (difference * 100.0);

    return performance.clamp(0.0, 100.0);
  }

  // ============================================================
  // PERIOD ROUTINES
  // ============================================================

  List<DailyRoutine> periodRoutines(_StatisticsPeriod period) {
    switch (period) {
      case _StatisticsPeriod.last7Days:
        return _lastDays(7);

      case _StatisticsPeriod.last30Days:
        return _lastDays(30);

      case _StatisticsPeriod.year:
        return _lastDays(365);
    }
  }

  // ============================================================
  // LAST DAYS
  // ============================================================

  List<DailyRoutine> _lastDays(int days) {
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: days - 1));

    return routines.where((routine) {
      final date = DateTime(
        routine.date.year,
        routine.date.month,
        routine.date.day,
      );

      return !date.isBefore(start) && !date.isAfter(today);
    }).toList();
  }

  // ============================================================
  // PERIOD DAYS
  // ============================================================

  int periodDays(_StatisticsPeriod period) {
    switch (period) {
      case _StatisticsPeriod.last7Days:
        return 7;

      case _StatisticsPeriod.last30Days:
        return 30;

      case _StatisticsPeriod.year:
        return 365;
    }
  }

  // ============================================================
  // GOAL SLEEP DURATION
  // ============================================================

  Duration? get sleepGoalDuration {
    if (goal == null) {
      return null;
    }

    final sleep = DateTime(2000, 1, 1, goal!.sleepHour, goal!.sleepMinute);

    var wake = DateTime(2000, 1, 1, goal!.wakeUpHour, goal!.wakeUpMinute);

    // Wake-up is normally on the following day.
    if (!wake.isAfter(sleep)) {
      wake = wake.add(const Duration(days: 1));
    }

    final duration = wake.difference(sleep);

    if (duration <= Duration.zero || duration > const Duration(hours: 24)) {
      return null;
    }

    return duration;
  }

  double? get sleepGoalHours {
    final duration = sleepGoalDuration;

    if (duration == null) {
      return null;
    }

    return duration.inMinutes / 60;
  }

  String get sleepGoalText {
    final duration = sleepGoalDuration;

    if (duration == null) {
      return 'No goal';
    }

    return 'Goal ${_formatDuration(duration)}';
  }

  // ============================================================
  // WAKE GOAL
  // ============================================================

  double? get wakeGoalHour {
    if (goal == null) {
      return null;
    }

    return goal!.wakeUpHour + goal!.wakeUpMinute / 60;
  }

  double? get sleepGoalHour {
    if (goal == null) {
      return null;
    }

    return goal!.sleepHour + goal!.sleepMinute / 60;
  }

  String get wakeGoalText {
    if (goal == null) {
      return 'No goal';
    }

    final date = DateTime(2000, 1, 1, goal!.wakeUpHour, goal!.wakeUpMinute);

    return 'Goal ${DailyRoutine.formatTime(date)}';
  }

  // ============================================================
  // AVERAGE SLEEP
  // ============================================================

  Duration? _averageSleep(List<DailyRoutine> list) {
    final durations = list
        .map((e) => e.sleepDuration)
        .whereType<Duration>()
        .toList();

    if (durations.isEmpty) {
      return null;
    }

    final totalMinutes = durations.fold<int>(
      0,
      (sum, duration) => sum + duration.inMinutes,
    );

    return Duration(minutes: totalMinutes ~/ durations.length);
  }

  String _formatAverage(List<DailyRoutine> list) {
    final duration = _averageSleep(list);

    if (duration == null) {
      return '--';
    }

    return _formatDuration(duration);
  }

  String averageSleepForPeriod(_StatisticsPeriod period) {
    return _formatAverage(periodRoutines(period));
  }

  // ============================================================
  // AVERAGE WAKE
  // ============================================================

  DateTime? _averageWakeTime(List<DailyRoutine> list) {
    final wakeTimes = list
        .map((e) => e.wakeUpTime)
        .whereType<DateTime>()
        .toList();

    if (wakeTimes.isEmpty) {
      return null;
    }

    final totalMinutes = wakeTimes.fold<int>(
      0,
      (sum, time) => sum + time.hour * 60 + time.minute,
    );

    final average = totalMinutes ~/ wakeTimes.length;

    return DateTime(2000, 1, 1, average ~/ 60, average % 60);
  }

  String averageWakeForPeriod(_StatisticsPeriod period) {
    final time = _averageWakeTime(periodRoutines(period));

    if (time == null) {
      return '--';
    }

    return DailyRoutine.formatTime(time);
  }

  // ============================================================
  // SLEEP PERFORMANCE
  // ============================================================

  double? sleepGoalPerformance(_StatisticsPeriod period) {
    final goal = sleepGoalDuration;

    if (goal == null) {
      return null;
    }

    final average = _averageSleep(periodRoutines(period));

    if (average == null || goal.inMinutes == 0) {
      return null;
    }

    return average.inMinutes / goal.inMinutes * 100;
  }

  String sleepPerformanceText(_StatisticsPeriod period) {
    final value = sleepGoalPerformance(period);

    if (value == null) {
      return '--';
    }

    return '${value.round()}%';
  }

  String sleepPerformanceStatus(_StatisticsPeriod period) {
    final value = sleepGoalPerformance(period);

    if (value == null) {
      return 'No data';
    }

    if (value >= 100) {
      return 'Goal achieved';
    }

    final difference = 100 - value;

    return '${difference.round()}% below goal';
  }

  // ============================================================
  // SLEEP POINTS
  // ============================================================

  List<_ChartPoint> chartSleepPoints(_StatisticsPeriod period) {
    final days = periodDays(period);

    final result = <_ChartPoint>[];

    // ----------------------------------------------------------
    // For year view, plotting all 365 days is technically valid,
    // but labels are reduced heavily.
    // ----------------------------------------------------------

    for (int i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));

      DailyRoutine? routine;

      for (final item in routines) {
        if (_sameDate(item.date, date)) {
          routine = item;
          break;
        }
      }

      final duration = routine?.sleepDuration;

      result.add(
        _ChartPoint(
          label: _chartDateLabel(date, period),
          hours: duration == null ? null : duration.inMinutes / 60,
        ),
      );
    }

    return result;
  }

  // ============================================================
  // WAKE POINTS
  // ============================================================

  List<_WakeChartPoint> chartWakePoints(_StatisticsPeriod period) {
    final days = periodDays(period);

    final result = <_WakeChartPoint>[];

    for (int i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));

      DailyRoutine? routine;

      for (final item in routines) {
        if (_sameDate(item.date, date)) {
          routine = item;
          break;
        }
      }

      final wake = routine?.wakeUpTime;

      result.add(
        _WakeChartPoint(
          label: _chartDateLabel(date, period),
          hour: wake == null ? null : wake.hour + wake.minute / 60.0,
        ),
      );
    }

    return result;
  }

  // ============================================================
  // SLEEP TIME POINTS
  // ============================================================

  List<_SleepTimeChartPoint> chartSleepTimePoints(_StatisticsPeriod period) {
    final days = periodDays(period);
    final result = <_SleepTimeChartPoint>[];

    for (int i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));

      DailyRoutine? routine;

      for (final item in routines) {
        if (_sameDate(item.date, date)) {
          routine = item;
          break;
        }
      }

      final sleep = routine?.sleepTime;

      result.add(
        _SleepTimeChartPoint(
          label: _chartDateLabel(date, period),
          hour: sleep == null ? null : sleep.hour + sleep.minute / 60.0,
        ),
      );
    }

    return result;
  }

  // ============================================================
  // CHART LABEL
  // ============================================================

  String _chartDateLabel(DateTime date, _StatisticsPeriod period) {
    if (period == _StatisticsPeriod.year) {
      if (date.day == 1) {
        return _monthShort(date.month);
      }

      return '';
    }

    if (period == _StatisticsPeriod.last30Days) {
      return '${date.day}';
    }

    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return names[date.weekday - 1];
  }

  // ============================================================
  // DATE COMPARISON
  // ============================================================

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ============================================================
  // MONTH SHORT
  // ============================================================

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[month - 1];
  }

  // ============================================================
  // FORMAT DURATION
  // ============================================================

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    if (hours == 0) {
      return '${minutes}m';
    }

    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}m';
  }
}

// ============================================================================
// CHART POINT
// ============================================================================

class _ChartPoint {
  final String label;
  final double? hours;

  const _ChartPoint({required this.label, required this.hours});
}

// ============================================================================
// SLEEP TIME CHART POINT
// ============================================================================

class _SleepTimeChartPoint {
  final String label;
  final double? hour;

  const _SleepTimeChartPoint({required this.label, required this.hour});
}

// ============================================================================
// WAKE CHART POINT
// ============================================================================

class _WakeChartPoint {
  final String label;
  final double? hour;

  const _WakeChartPoint({required this.label, required this.hour});
}
