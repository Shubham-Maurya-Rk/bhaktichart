import 'package:bhaktichart/core/utils/date_utils.dart';
import 'package:bhaktichart/features/daily_diary/daily_diary_screen.dart';
import 'package:bhaktichart/features/goals/goals_screen.dart';
import 'package:bhaktichart/features/daily_routine/daily_routine_screen.dart';
import 'package:bhaktichart/features/insights/monthly_insights_screen.dart';
import 'package:bhaktichart/features/insights/day_insights_screen.dart';
import 'package:bhaktichart/features/todo/daily_todo_screen.dart';
import 'package:bhaktichart/features/learning_tracker/learning_tracker_screen.dart';
import 'package:bhaktichart/models/aarti_type_model.dart';
import 'package:bhaktichart/models/daily_aarti_model.dart';
import 'package:bhaktichart/models/daily_sadhana_model.dart';
import 'package:bhaktichart/models/day_note_model.dart';
import 'package:bhaktichart/models/goal_model.dart';
import 'package:bhaktichart/models/sadhana_type_model.dart';
import 'package:bhaktichart/repositories/sadhana_repository.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:bhaktichart/features/reminders/reminders_screen.dart';
import 'package:bhaktichart/features/statistics/statistics_screen.dart';
import 'package:bhaktichart/services/sadhana_reminder_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ============================================================
  // REPOSITORY
  // ============================================================

  final SadhanaRepository _repository = SadhanaRepository();

  // ============================================================
  // USER
  // ============================================================

  int? _userId;
  String _name = '';

  // ============================================================
  // CALENDAR
  // ============================================================

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  // ============================================================
  // SADHANA TYPES
  // ============================================================

  List<SadhanaTypeModel> _sadhanaTypes = [];

  int? _selectedSadhanaTypeId;

  // ============================================================
  // MONTHLY DATA
  // ============================================================

  Map<String, double> _monthlySadhana = {};

  Map<String, DailySadhanaModel> _monthlySadhanaByDate = {};

  Map<String, int> _monthlyAarti = {};

  // IMPORTANT:
  // This list ALWAYS contains ALL SADHANA TYPES.
  //
  // Do NOT make this dependent on _selectedSadhanaTypeId.
  //
  // Today's Sadhana and Monthly Quick Stats use this list.
  List<DailySadhanaModel> _allSadhanaRecords = [];

  List<DailyAartiModel> _allAartiRecords = [];

  // ============================================================
  // DAY NOTES
  // ============================================================

  Map<String, DayNoteModel> _monthlyDayNotes = {};

  // ============================================================
  // GOALS
  // ============================================================

  GoalModel? _currentGoal;

  final Map<int, GoalModel?> _goals = {};

  // ============================================================
  // LOADING
  // ============================================================

  bool _isLoading = true;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _initializeReminderNotifications();
    _loadHomeData();
  }

  // ============================================================
  // LOAD HOME DATA
  // ============================================================
  Future<void> _initializeReminderNotifications() async {
    try {
      await SadhanaReminderService.instance.initialize();
    } catch (e) {
      debugPrint('Error initializing reminders: $e');
    }
  }

  Future<void> _openReminders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RemindersScreen()),
    );
  }

  Future<void> _loadHomeData() async {
    try {
      final user = await _repository.getUser();

      if (user == null || user.id == null) {
        return;
      }

      final types = await _repository.getSadhanaTypes();

      final Map<int, GoalModel?> loadedGoals = {};

      for (final type in types) {
        if (type.id == null) {
          continue;
        }

        loadedGoals[type.id!] = await _repository.getGoal(user.id!, type.id!);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _userId = user.id;
        _name = user.name;
        _sadhanaTypes = types;

        _goals.clear();
        _goals.addAll(loadedGoals);
      });

      // ----------------------------------------------------------
      // SELECT CHANTING BY DEFAULT
      // ----------------------------------------------------------

      if (types.isNotEmpty) {
        SadhanaTypeModel? chanting;

        try {
          chanting = types.firstWhere(
            (type) => type.name.toLowerCase() == 'chanting',
          );
        } catch (_) {
          chanting = types.first;
        }

        if (mounted) {
          setState(() {
            _selectedSadhanaTypeId = chanting?.id;
          });
        }
      }

      await _loadMonthlyData();
    } catch (e) {
      debugPrint('Error loading home data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // LOAD MONTH DATA
  // ============================================================

  Future<void> _loadMonthlyData() async {
    if (_userId == null || _selectedSadhanaTypeId == null) {
      return;
    }

    try {
      final startDate = AppDateUtils.monthStart(_focusedDay);
      final endDate = AppDateUtils.monthEnd(_focusedDay);

      // ----------------------------------------------------------
      // MONTHLY SADHANA
      //
      // This returns records for the selected month.
      // We still filter it below for the heatmap.
      // ----------------------------------------------------------

      final records = await _repository.getSadhanaForMonth(
        _userId!,
        startDate,
        endDate,
      );

      // ----------------------------------------------------------
      // AARTI MONTH
      // ----------------------------------------------------------

      final aartiRecords = await _repository.getAartiAttendanceForMonth(
        _userId!,
        startDate,
        endDate,
      );

      // ----------------------------------------------------------
      // IMPORTANT FIX:
      //
      // Load ALL SADHANA RECORDS for ALL SADHANA TYPES.
      //
      // Previously this was:
      //
      // getAllSadhana(userId, selectedTypeId)
      //
      // That caused Today's Sadhana and Monthly Quick Stats
      // to change when the heatmap selector changed.
      //
      // Now we load every Sadhana type independently and merge
      // the results into _allSadhanaRecords.
      // ----------------------------------------------------------

      final List<DailySadhanaModel> allSadhanaRecords = [];

      final Set<String> loadedRecordKeys = {};

      for (final type in _sadhanaTypes) {
        if (type.id == null) {
          continue;
        }

        try {
          final typeRecords = await _repository.getAllSadhana(
            _userId!,
            type.id!,
          );

          for (final record in typeRecords) {
            final key =
                '${record.date}_${record.sadhanaTypeId}_${record.unit ?? ''}';

            if (!loadedRecordKeys.contains(key)) {
              loadedRecordKeys.add(key);
              allSadhanaRecords.add(record);
            }
          }
        } catch (e) {
          debugPrint('Error loading Sadhana records for type ${type.id}: $e');
        }
      }

      // ----------------------------------------------------------
      // LOAD ALL AARTI
      // ----------------------------------------------------------

      final allAartiRecords = await _repository.getAllAartiAttendance(_userId!);

      // ----------------------------------------------------------
      // AARTI COUNT
      // ----------------------------------------------------------

      final Map<String, int> aartiData = {};

      for (final record in aartiRecords) {
        aartiData[record.date] = (aartiData[record.date] ?? 0) + 1;
      }

      // ----------------------------------------------------------
      // SELECTED SADHANA VALUES
      //
      // Only this data depends on selected Sadhana.
      // ----------------------------------------------------------

      final Map<String, double> data = {};

      for (final record in records) {
        if (record.sadhanaTypeId == _selectedSadhanaTypeId) {
          data[record.date] = record.value;
        }
      }

      // ----------------------------------------------------------
      // DAY NOTES
      // ----------------------------------------------------------

      final Map<String, DayNoteModel> dayNotes = {};

      final start = DateTime.parse(startDate);
      final end = DateTime.parse(endDate);

      DateTime currentDate = DateTime(start.year, start.month, start.day);

      final lastDate = DateTime(end.year, end.month, end.day);

      while (!currentDate.isAfter(lastDate)) {
        final dateKey = _dateKey(currentDate);

        try {
          final note = await _repository.getDayNote(_userId!, dateKey);

          if (note != null) {
            final hasNote = note.note != null && note.note!.trim().isNotEmpty;

            final hasDayType =
                note.isStarred ||
                note.isSankirtan ||
                note.isEkadashi ||
                note.isFestival;

            if (hasNote || hasDayType) {
              dayNotes[dateKey] = note;
            }
          }
        } catch (e) {
          debugPrint('Error loading day note for $dateKey: $e');
        }

        currentDate = currentDate.add(const Duration(days: 1));
      }

      // ----------------------------------------------------------
      // CURRENT GOAL
      // ----------------------------------------------------------

      final goal = await _repository.getGoal(_userId!, _selectedSadhanaTypeId!);

      if (!mounted) {
        return;
      }

      setState(() {
        // This map contains all records from the selected month.
        _monthlySadhanaByDate = {
          for (final item in records)
            '${item.date}_${item.sadhanaTypeId}': item,
        };

        // IMPORTANT:
        // This now contains ALL Sadhana types.
        _allSadhanaRecords = allSadhanaRecords;

        _allAartiRecords = allAartiRecords;

        // This remains selected-type-specific.
        _monthlySadhana = data;

        _monthlyAarti = aartiData;

        _monthlyDayNotes = dayNotes;

        _currentGoal = goal;

        _goals[_selectedSadhanaTypeId!] = goal;
      });
    } catch (e) {
      debugPrint('Error loading monthly data: $e');
    }
  }

  // ============================================================
  // DATE KEY
  // ============================================================

  String _dateKey(DateTime date) {
    return AppDateUtils.formatDate(date);
  }

  // ============================================================
  // GET DAY NOTE
  // ============================================================

  DayNoteModel? _getDayNote(DateTime day) {
    return _monthlyDayNotes[_dateKey(day)];
  }

  // ============================================================
  // IMPORTANT DAY
  // ============================================================

  bool _isImportantDay(DateTime day) {
    return _getDayNote(day)?.isStarred ?? false;
  }

  // ============================================================
  // HAS NOTE
  // ============================================================

  bool _hasDayNote(DateTime day) {
    final note = _getDayNote(day);

    return note?.note != null && note!.note!.trim().isNotEmpty;
  }

  // ============================================================
  // GET VALUE FOR DAY
  // ============================================================

  double _getValueForDay(DateTime day) {
    return _monthlySadhana[_dateKey(day)] ?? 0.0;
  }

  // ============================================================
  // FORMAT VALUE
  // ============================================================

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  // ============================================================
  // SELECTED SADHANA
  // ============================================================

  SadhanaTypeModel? get _selectedSadhana {
    if (_selectedSadhanaTypeId == null) {
      return null;
    }

    try {
      return _sadhanaTypes.firstWhere(
        (type) => type.id == _selectedSadhanaTypeId,
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // FIND SADHANA BY NAME
  // ============================================================

  SadhanaTypeModel? _findSadhana(String name) {
    try {
      return _sadhanaTypes.firstWhere(
        (type) => type.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // SADHANA ICON
  // ============================================================

  String _getSadhanaIcon() {
    return _selectedSadhana?.icon ?? '🙏';
  }

  // ============================================================
  // DEFAULT UNIT
  // ============================================================

  String _getDefaultUnit() {
    return _getDefaultUnitForType(_selectedSadhana);
  }

  String _getDefaultUnitForType(SadhanaTypeModel? type) {
    final name = type?.name.toLowerCase();

    switch (name) {
      case 'chanting':
        return 'rounds';

      case 'hearing':
        return 'minutes';

      case 'reading':
        return 'pages';

      default:
        return 'times';
    }
  }

  // ============================================================
  // HEATMAP COLOR
  // ============================================================

  Color _getHeatColor(BuildContext context, double? progress) {
    final colorScheme = Theme.of(context).colorScheme;

    if (progress == null || progress <= 0) {
      return colorScheme.surfaceContainerHighest;
    }

    if (progress >= 1.0) {
      return colorScheme.primary;
    }

    if (progress >= 0.75) {
      return colorScheme.primary.withValues(alpha: 0.75);
    }

    if (progress >= 0.50) {
      return colorScheme.primary.withValues(alpha: 0.55);
    }

    if (progress >= 0.25) {
      return colorScheme.primary.withValues(alpha: 0.35);
    }

    return colorScheme.primary.withValues(alpha: 0.18);
  }

  // ============================================================
  // SELECT SADHANA
  // ============================================================

  Future<void> _selectSadhana(SadhanaTypeModel type) async {
    if (type.id == null) {
      return;
    }

    setState(() {
      _selectedSadhanaTypeId = type.id;

      // Clear only selected-type heatmap data.
      _monthlySadhana = {};

      // Do NOT clear _allSadhanaRecords.
      //
      // It contains data for Today's Sadhana and
      // Monthly Quick Stats for every type.

      _currentGoal = _goals[type.id!];
    });

    Navigator.pop(context);

    await _loadMonthlyData();
  }

  // ============================================================
  // SADHANA SELECTOR
  // ============================================================

  void _showSadhanaSelector() {
    if (_sadhanaTypes.isEmpty) {
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What do you want to see?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                ..._sadhanaTypes.map((sadhana) {
                  final selected = sadhana.id == _selectedSadhanaTypeId;

                  return ListTile(
                    leading: Text(
                      sadhana.icon ?? '🙏',
                      style: const TextStyle(fontSize: 28),
                    ),

                    title: Text(
                      sadhana.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),

                    trailing: selected
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(sheetContext).colorScheme.primary,
                          )
                        : null,

                    selected: selected,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),

                    onTap: () {
                      _selectSadhana(sadhana);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // TODAY VALUE FOR TYPE
  // ============================================================

  double _getTodayValueForType(SadhanaTypeModel type) {
    final todayKey = _dateKey(DateTime.now());

    for (final record in _allSadhanaRecords) {
      if (record.sadhanaTypeId == type.id && record.date == todayKey) {
        return record.value;
      }
    }

    return 0;
  }

  // ============================================================
  // TODAY AARTI COUNT
  // ============================================================

  int _getTodayAartiCount() {
    final todayKey = _dateKey(DateTime.now());

    return _allAartiRecords.where((record) => record.date == todayKey).length;
  }

  // ============================================================
  // READING GOAL COMPLETION
  // ============================================================

  bool _isTodayReadingGoalCompleted(
    SadhanaTypeModel? reading,
    double value,
    GoalModel? goal,
  ) {
    if (reading == null || reading.id == null) {
      return false;
    }

    if (goal == null || goal.targetValue <= 0) {
      return false;
    }

    final todayKey = _dateKey(DateTime.now());

    final recordKey = '${todayKey}_${reading.id}';

    final record = _monthlySadhanaByDate[recordKey];

    if (record == null) {
      return false;
    }

    final actualUnit = record.unit;

    final goalUnit = goal.unit;

    if (actualUnit == null || goalUnit == null) {
      return false;
    }

    if (actualUnit != goalUnit) {
      return false;
    }

    return value >= goal.targetValue;
  }
  // ============================================================
  // GET TODAY'S RECORD FOR TYPE
  // ============================================================

  DailySadhanaModel? _getTodayRecordForType(SadhanaTypeModel? type) {
    if (type == null || type.id == null) {
      return null;
    }

    final todayKey = _dateKey(DateTime.now());

    for (final record in _allSadhanaRecords) {
      if (record.sadhanaTypeId == type.id && record.date == todayKey) {
        return record;
      }
    }

    return null;
  }
  // ============================================================
  // GET TODAY'S UNIT FOR TYPE
  // ============================================================

  String _getTodayUnitForType(
    SadhanaTypeModel? type, {
    String fallback = 'times',
  }) {
    final record = _getTodayRecordForType(type);

    if (record?.unit != null && record!.unit!.trim().isNotEmpty) {
      return record.unit!;
    }

    return fallback;
  }

  // ============================================================
  // TODAY SADHANA SUMMARY
  // ============================================================

  Widget _buildTodaySadhana(BuildContext context) {
    final theme = Theme.of(context);

    final chanting = _findSadhana('chanting');
    final reading = _findSadhana('reading');
    final hearing = _findSadhana('hearing');
    final aarti = _findSadhana('aarti');

    final chantingValue = chanting == null
        ? 0.0
        : _getTodayValueForType(chanting);

    final readingValue = reading == null ? 0.0 : _getTodayValueForType(reading);

    final hearingValue = hearing == null ? 0.0 : _getTodayValueForType(hearing);

    final aartiValue = _getTodayAartiCount();

    // ----------------------------------------------------------
    // TODAY'S ACTUAL UNITS
    // ----------------------------------------------------------

    final chantingUnit = _getTodayUnitForType(chanting, fallback: 'rounds');

    final readingUnit = _getTodayUnitForType(reading, fallback: 'pages');

    final hearingUnit = _getTodayUnitForType(hearing, fallback: 'minutes');

    // ----------------------------------------------------------
    // GOALS
    // ----------------------------------------------------------

    final chantingGoal = chanting?.id == null ? null : _goals[chanting!.id!];

    final readingGoal = reading?.id == null ? null : _goals[reading!.id!];

    final hearingGoal = hearing?.id == null ? null : _goals[hearing!.id!];

    final aartiGoal = aarti?.id == null ? null : _goals[aarti!.id!];

    // ----------------------------------------------------------
    // COMPLETION
    // ----------------------------------------------------------

    final chantingCompleted = _isTodayGoalCompleted(
      chantingValue,
      chantingGoal,
    );

    final readingCompleted = _isTodayReadingGoalCompleted(
      reading,
      readingValue,
      readingGoal,
    );

    final hearingCompleted = _isTodayGoalCompleted(hearingValue, hearingGoal);

    final aartiCompleted = _isTodayGoalCompleted(
      aartiValue.toDouble(),
      aartiGoal,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Today\'s Sadhana',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Spacer(),

                Text(
                  DateFormat('d MMM').format(DateTime.now()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildTodaySadhanaItem(
                    context,
                    icon: '📿',
                    title: 'Chanting',
                    value: _formatValue(chantingValue),
                    unit: chantingUnit,
                    completed: chantingCompleted,
                    goal: chantingGoal,
                    onTap: chanting == null
                        ? null
                        : () => _showDaySadhanaSheet(
                            DateTime.now(),
                            typeOverride: chanting,
                          ),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: _buildTodaySadhanaItem(
                    context,
                    icon: '📖',
                    title: 'Reading',
                    value: _formatValue(readingValue),
                    unit: readingUnit,
                    completed: readingCompleted,
                    goal: readingGoal,
                    onTap: reading == null
                        ? null
                        : () => _showDaySadhanaSheet(
                            DateTime.now(),
                            typeOverride: reading,
                          ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _buildTodaySadhanaItem(
                    context,
                    icon: '🎧',
                    title: 'Hearing',
                    value: _formatValue(hearingValue),
                    unit: hearingUnit,
                    completed: hearingCompleted,
                    goal: hearingGoal,
                    onTap: hearing == null
                        ? null
                        : () => _showDaySadhanaSheet(
                            DateTime.now(),
                            typeOverride: hearing,
                          ),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: _buildTodaySadhanaItem(
                    context,
                    icon: '🪔',
                    title: 'Aarti',
                    value: '$aartiValue',
                    unit: aartiValue == 1 ? 'aarti' : 'aartis',
                    completed: aartiCompleted,
                    goal: aartiGoal,
                    onTap: aarti == null
                        ? null
                        : () => _showDaySadhanaSheet(
                            DateTime.now(),
                            typeOverride: aarti,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  // ============================================================
  // CHECK IF TODAY'S GOAL IS COMPLETED
  // ============================================================

  bool _isTodayGoalCompleted(double value, GoalModel? goal) {
    // No goal = cannot be considered completed.
    if (goal == null) {
      return false;
    }

    // Invalid goal = cannot be considered completed.
    if (goal.targetValue <= 0) {
      return false;
    }

    return value >= goal.targetValue;
  }

  // ============================================================
  // TODAY SADHANA ITEM
  // ============================================================

  Widget _buildTodaySadhanaItem(
    BuildContext context, {
    required String icon,
    required String title,
    required String value,
    required String unit,
    required bool completed,
    required GoalModel? goal,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    final numericValue = double.tryParse(value) ?? 0;

    // ----------------------------------------------------------
    // PROGRESS
    // ----------------------------------------------------------

    double? progress;

    if (goal != null && goal.targetValue > 0) {
      progress = numericValue / goal.targetValue;
      progress = progress.clamp(0.0, 1.0);
    }

    // ----------------------------------------------------------
    // BACKGROUND
    // ----------------------------------------------------------

    final backgroundColor = completed
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    final checkColor = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------------
              // ICON + CHECK
              // ------------------------------------------------------
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 22)),

                  const Spacer(),

                  if (completed)
                    Icon(Icons.check_circle, size: 18, color: checkColor),
                ],
              ),

              const SizedBox(height: 8),

              // ------------------------------------------------------
              // TITLE
              // ------------------------------------------------------
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 2),

              // ------------------------------------------------------
              // VALUE
              // ------------------------------------------------------
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: completed ? theme.colorScheme.primary : null,
                    ),
                  ),

                  const SizedBox(width: 4),

                  Flexible(
                    child: Text(
                      unit,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              // ------------------------------------------------------
              // GOAL PROGRESS
              // ------------------------------------------------------
              if (goal != null && goal.targetValue > 0) ...[
                const SizedBox(height: 8),

                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '${_formatValue(goal.targetValue)} ${goal.unit ?? unit}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // The Material/InkWell wrapper above preserves the existing card UI while
    // making each Today's Sadhana item tappable.
  }
  // ============================================================
  // CALENDAR DAY CLICK
  // ============================================================

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final today = DateTime.now();

    final selected = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );

    final currentDay = DateTime(today.year, today.month, today.day);

    if (selected.isAfter(currentDay)) {
      return;
    }

    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });

    _showDaySadhanaSheet(selectedDay);
  }

  // ============================================================
  // DAY SADHANA SHEET
  // ============================================================

  Future<void> _showDaySadhanaSheet(
    DateTime day, {
    SadhanaTypeModel? typeOverride,
  }) async {
    if (_userId == null) {
      return;
    }

    // The optional override is used only by the bottom-sheet switcher.
    // It deliberately does NOT change _selectedSadhanaTypeId, so switching
    // inside the sheet does not change the monthly heatmap selection.
    final type = typeOverride ?? _selectedSadhana;

    if (type == null) {
      return;
    }

    if (type.name.toLowerCase() == 'aarti') {
      await _showAartiSheet(day);
      return;
    }

    await _showValueSadhanaSheet(day, type);
  }

  // ============================================================
  // BOTTOM SHEET SADHANA SWITCHER
  // ============================================================

  Widget _buildBottomSheetSadhanaSwitcher(
    BuildContext context,
    DateTime day,
    SadhanaTypeModel currentType,
  ) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: DropdownButtonFormField<int>(
          value: currentType.id,
          decoration: const InputDecoration(
            labelText: 'Sadhana',
            prefixIcon: Icon(Icons.swap_vert),
            border: InputBorder.none,
            isDense: true,
          ),
          items: _sadhanaTypes
              .where((sadhana) => sadhana.id != null)
              .map(
                (sadhana) => DropdownMenuItem<int>(
                  value: sadhana.id!,
                  child: Row(
                    children: [
                      Text(
                        sadhana.icon ?? '🙏',
                        style: const TextStyle(fontSize: 21),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        sadhana.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (id) async {
            if (id == null || id == currentType.id) {
              return;
            }

            SadhanaTypeModel? nextType;

            for (final sadhana in _sadhanaTypes) {
              if (sadhana.id == id) {
                nextType = sadhana;
                break;
              }
            }

            if (nextType == null || !context.mounted) {
              return;
            }

            await _switchSadhanaInBottomSheet(context, day, nextType);
          },
        ),
      ),
    );
  }

  Future<void> _switchSadhanaInBottomSheet(
    BuildContext sheetContext,
    DateTime day,
    SadhanaTypeModel nextType,
  ) async {
    // Close only the current sheet, then immediately open the selected
    // Sadhana's editor. The monthly Sadhana selector remains untouched.
    Navigator.of(sheetContext).pop();

    await Future<void>.delayed(Duration.zero);

    if (!mounted) {
      return;
    }

    await _showDaySadhanaSheet(day, typeOverride: nextType);
  }

  // ============================================================
  // DAY DETAIL HEADER
  // ============================================================

  Widget _buildDayDetailHeader(
    BuildContext context,
    DateTime day,
    SadhanaTypeModel type,
    double value,
    GoalModel? goal,
    String? actualUnit,
  ) {
    final theme = Theme.of(context);

    final isReading = type.name.toLowerCase() == 'reading';

    bool unitMatches = true;

    if (isReading && goal != null) {
      unitMatches =
          actualUnit != null && goal.unit != null && actualUnit == goal.unit;
    }

    final hasGoal = goal != null && goal.targetValue > 0;

    double? progress;

    if (hasGoal && (!isReading || unitMatches)) {
      progress = value / goal!.targetValue;
    }

    final completed = progress != null && progress >= 1.0;

    return Column(
      children: [
        Text(
          DateFormat('EEEE, d MMMM yyyy').format(day),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 8),

        // Row(
        //   mainAxisAlignment: MainAxisAlignment.center,
        //   children: [
        //     Text(type.icon ?? '🙏', style: const TextStyle(fontSize: 30)),

        //     const SizedBox(width: 8),

        //     Text(
        //       type.name,
        //       style: theme.textTheme.headlineSmall?.copyWith(
        //         fontWeight: FontWeight.bold,
        //       ),
        //     ),
        //   ],
        // ),

        // const SizedBox(height: 20),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                // Today's value
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _formatValue(value),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: completed ? theme.colorScheme.primary : null,
                      ),
                    ),

                    if (actualUnit != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        actualUnit,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 8),

                if (!hasGoal)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'No daily goal set',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  )
                else if (isReading && !unitMatches)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.compare_arrows_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Goal: ${goal.unit ?? 'unknown'} • '
                          'Today: ${actualUnit ?? 'unknown'}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  // Goal + percentage
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Goal: ${_formatValue(goal!.targetValue)} '
                        '${goal.unit ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      Text(
                        '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: completed ? theme.colorScheme.primary : null,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0.0, 1.0),
                      minHeight: 7,
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Progress numbers
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_formatValue(value)} / '
                      '${_formatValue(goal.targetValue)} ${goal.unit ?? ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  if (completed) ...[
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Goal completed 🎉',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayTypeSelector({
    required BuildContext context,
    required bool isStarred,
    required bool isSankirtan,
    required bool isEkadashi,
    required bool isFestival,
    required ValueChanged<bool> onStarredChanged,
    required ValueChanged<bool> onSankirtanChanged,
    required ValueChanged<bool> onEkadashiChanged,
    required ValueChanged<bool> onFestivalChanged,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildDayTypeReaction(
            context: context,
            icon: Icons.groups_2_outlined,
            selectedIcon: Icons.groups_2,
            label: 'Sankirtan',
            selected: isSankirtan,
            onSelected: onSankirtanChanged,
          ),

          const SizedBox(width: 8),

          _buildDayTypeReaction(
            context: context,
            icon: Icons.brightness_2_outlined,
            selectedIcon: Icons.brightness_2,
            label: 'Ekadashi',
            selected: isEkadashi,
            onSelected: onEkadashiChanged,
          ),

          const SizedBox(width: 8),

          _buildDayTypeReaction(
            context: context,
            icon: Icons.celebration_outlined,
            selectedIcon: Icons.celebration,
            label: 'Festival',
            selected: isFestival,
            onSelected: onFestivalChanged,
          ),

          const SizedBox(width: 8),

          _buildDayTypeReaction(
            context: context,
            icon: Icons.star_border,
            selectedIcon: Icons.star,
            label: 'Important',
            selected: isStarred,
            onSelected: onStarredChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDayTypeReaction({
    required BuildContext context,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => onSelected(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),

            const SizedBox(width: 5),

            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ============================================================
  // VALUE SADHANA SHEET
  // ============================================================

  Future<void> _showValueSadhanaSheet(
    DateTime day,
    SadhanaTypeModel type,
  ) async {
    final existing = await _repository.getSadhana(
      _userId!,
      _dateKey(day),
      type.id!,
    );

    final existingNote = await _repository.getDayNote(_userId!, _dateKey(day));

    String selectedReadingUnit = 'pages';

    if (type.name.toLowerCase() == 'reading') {
      if (existing != null &&
          existing.unit != null &&
          existing.unit!.isNotEmpty) {
        selectedReadingUnit = existing.unit!;
      } else {
        final settings = await _repository.getReadingSettings(_userId!);

        selectedReadingUnit = settings?.unit ?? 'pages';
      }
    }

    final controller = TextEditingController(
      text: existing != null && existing.value > 0
          ? _formatValue(existing.value)
          : '',
    );

    final noteController = TextEditingController(
      text: existingNote?.note ?? '',
    );

    bool isStarred = existingNote?.isStarred ?? false;
    bool isSankirtan = existingNote?.isSankirtan ?? false;
    bool isEkadashi = existingNote?.isEkadashi ?? false;
    bool isFestival = existingNote?.isFestival ?? false;

    if (!mounted) {
      controller.dispose();
      noteController.dispose();
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);

            final isReading = type.name.toLowerCase() == 'reading';

            final unit = isReading
                ? selectedReadingUnit
                : _getDefaultUnitForType(type);

            final value = existing?.value ?? 0.0;

            final goal = _goals[type.id!] ?? _currentGoal;

            String? actualUnit;

            if (isReading) {
              actualUnit = selectedReadingUnit;
            } else {
              actualUnit = unit;
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBottomSheetSadhanaSwitcher(context, day, type),

                    const SizedBox(height: 12),

                    _buildDayDetailHeader(
                      context,
                      day,
                      type,
                      value,
                      goal,
                      actualUnit,
                    ),

                    const SizedBox(height: 24),

                    if (isReading) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Reading measured in',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),

                      const SizedBox(height: 8),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment<String>(
                              value: 'pages',
                              label: Text('Pages'),
                              icon: Icon(Icons.menu_book),
                            ),
                            ButtonSegment<String>(
                              value: 'shlokas',
                              label: Text('Shlokas'),
                              icon: Icon(Icons.format_quote),
                            ),
                            ButtonSegment<String>(
                              value: 'minutes',
                              label: Text('Minutes'),
                              icon: Icon(Icons.timer_outlined),
                            ),
                          ],
                          selected: {selectedReadingUnit},
                          onSelectionChanged: (values) {
                            if (values.isEmpty) {
                              return;
                            }

                            setSheetState(() {
                              selectedReadingUnit = values.first;
                            });
                          },
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],

                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        suffixText: unit,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildDayTypeSelector(
                      context: context,
                      isStarred: isStarred,
                      isSankirtan: isSankirtan,
                      isEkadashi: isEkadashi,
                      isFestival: isFestival,
                      onStarredChanged: (value) {
                        setSheetState(() {
                          isStarred = value;
                        });
                      },
                      onSankirtanChanged: (value) {
                        setSheetState(() {
                          isSankirtan = value;
                        });
                      },
                      onEkadashiChanged: (value) {
                        setSheetState(() {
                          isEkadashi = value;
                        });
                      },
                      onFestivalChanged: (value) {
                        setSheetState(() {
                          isFestival = value;
                        });
                      },
                    ),

                    const SizedBox(height: 8),

                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Note about this day',
                        hintText: 'Write something you want to remember...',
                        prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final value = double.tryParse(controller.text.trim());

                          if (value == null || value < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid number'),
                              ),
                            );
                            return;
                          }

                          final now = DateTime.now().toIso8601String();

                          final sadhana = DailySadhanaModel(
                            userId: _userId!,
                            date: _dateKey(day),
                            sadhanaTypeId: type.id!,
                            value: value,
                            unit: unit,
                            createdAt: now,
                            updatedAt: now,
                          );

                          await _repository.saveSadhana(sadhana);

                          final note = DayNoteModel(
                            userId: _userId!,
                            date: _dateKey(day),

                            isStarred: isStarred,
                            isSankirtan: isSankirtan,
                            isEkadashi: isEkadashi,
                            isFestival: isFestival,

                            note: noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),

                            createdAt: now,
                            updatedAt: now,
                          );

                          await _repository.saveDayNote(note);

                          await _loadMonthlyData();

                          if (!context.mounted) {
                            return;
                          }

                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check),
                        label: const Text(
                          'SAVE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // AARTI SHEET
  // ============================================================

  Future<void> _showAartiSheet(DateTime day) async {
    if (_userId == null) {
      return;
    }

    final aartiTypes = await _repository.getAartiTypes(_userId!);

    final attendance = await _repository.getAartiAttendance(
      _userId!,
      _dateKey(day),
    );

    final selectedIds = attendance.map((e) => e.aartiTypeId).toSet();

    final existingNote = await _repository.getDayNote(_userId!, _dateKey(day));

    // ============================================================
    // DAY TYPE STATES
    // ============================================================

    bool isStarred = existingNote?.isStarred ?? false;
    bool isSankirtan = existingNote?.isSankirtan ?? false;
    bool isEkadashi = existingNote?.isEkadashi ?? false;
    bool isFestival = existingNote?.isFestival ?? false;

    final noteController = TextEditingController(
      text: existingNote?.note ?? '',
    );

    if (!mounted) {
      noteController.dispose();
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);

            final aartiType = _findSadhana('aarti');

            final goal = aartiType?.id == null ? null : _goals[aartiType!.id!];

            final count = selectedIds.length;

            final goalProgress = goal != null && goal.targetValue > 0
                ? (count / goal.targetValue).clamp(0.0, 1.0)
                : null;

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ========================================================
                    // SADHANA SWITCHER
                    // ========================================================
                    if (aartiType != null)
                      _buildBottomSheetSadhanaSwitcher(context, day, aartiType),

                    const SizedBox(height: 10),

                    // ========================================================
                    // DATE
                    // ========================================================
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(day),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ========================================================
                    // AARTI SUMMARY CARD
                    // ========================================================
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$count',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Aartis',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),

                            if (goalProgress != null) ...[
                              const SizedBox(height: 8),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Goal: ${_formatValue(goal!.targetValue)} '
                                    '${goal.unit ?? 'aartis'}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${((goalProgress) * 100).toStringAsFixed(0)}%',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 5),

                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: goalProgress,
                                  minHeight: 7,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ========================================================
                    // AARTI LIST
                    // ========================================================
                    if (aartiTypes.isEmpty)
                      _buildNoAartiMessage(context)
                    else
                      ...aartiTypes.map((aarti) {
                        final id = aarti.id;

                        if (id == null) {
                          return const SizedBox();
                        }

                        final selected = selectedIds.contains(id);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: CheckboxListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            value: selected,
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selectedIds.add(id);
                                } else {
                                  selectedIds.remove(id);
                                }
                              });
                            },
                            title: Text(
                              aarti.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            secondary: const Text(
                              '🪔',
                              style: TextStyle(fontSize: 22),
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 6),

                    // ========================================================
                    // ADD AARTI
                    // ========================================================
                    OutlinedButton.icon(
                      onPressed: () async {
                        final added = await _showAddAartiDialog();

                        if (added == true) {
                          if (!context.mounted) {
                            return;
                          }

                          Navigator.pop(context);

                          await _showAartiSheet(day);
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('ADD MY AARTI'),
                    ),

                    const SizedBox(height: 14),

                    // ========================================================
                    // DAY TYPE SELECTOR
                    // ========================================================
                    _buildDayTypeSelector(
                      context: context,
                      isStarred: isStarred,
                      isSankirtan: isSankirtan,
                      isEkadashi: isEkadashi,
                      isFestival: isFestival,
                      onStarredChanged: (value) {
                        setSheetState(() {
                          isStarred = value;
                        });
                      },
                      onSankirtanChanged: (value) {
                        setSheetState(() {
                          isSankirtan = value;
                        });
                      },
                      onEkadashiChanged: (value) {
                        setSheetState(() {
                          isEkadashi = value;
                        });
                      },
                      onFestivalChanged: (value) {
                        setSheetState(() {
                          isFestival = value;
                        });
                      },
                    ),

                    const SizedBox(height: 8),

                    // ========================================================
                    // NOTE
                    // ========================================================
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Note about this day',
                        hintText: 'Write something to remember...',
                        prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ========================================================
                    // SAVE BUTTON
                    // ========================================================
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final now = DateTime.now().toIso8601String();

                          // ------------------------------------------------
                          // SAVE AARTI ATTENDANCE
                          // ------------------------------------------------

                          for (final aarti in aartiTypes) {
                            final id = aarti.id;

                            if (id == null) {
                              continue;
                            }

                            if (selectedIds.contains(id)) {
                              await _repository.saveAartiAttendance(
                                DailyAartiModel(
                                  userId: _userId!,
                                  aartiTypeId: id,
                                  date: _dateKey(day),
                                  createdAt: now,
                                ),
                              );
                            } else {
                              await _repository.removeAartiAttendance(
                                _userId!,
                                id,
                                _dateKey(day),
                              );
                            }
                          }

                          // ------------------------------------------------
                          // SAVE DAY NOTE + DAY TYPES
                          // ------------------------------------------------

                          final noteText = noteController.text.trim();

                          final note = DayNoteModel(
                            userId: _userId!,
                            date: _dateKey(day),

                            // Important Day
                            isStarred: isStarred,

                            // Day Types
                            isSankirtan: isSankirtan,
                            isEkadashi: isEkadashi,
                            isFestival: isFestival,

                            // Note
                            note: noteText.isEmpty ? null : noteText,

                            createdAt: existingNote?.createdAt ?? now,
                            updatedAt: now,
                          );

                          await _repository.saveDayNote(note);

                          // ------------------------------------------------
                          // REFRESH CALENDAR DATA
                          // ------------------------------------------------

                          await _loadMonthlyData();

                          if (!context.mounted) {
                            return;
                          }

                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check),
                        label: const Text(
                          'SAVE',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await _loadMonthlyData();
  }
  // ============================================================
  // NO AARTI MESSAGE
  // ============================================================

  Widget _buildNoAartiMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Text('🪔', style: TextStyle(fontSize: 40)),

          SizedBox(height: 8),

          Text(
            'No Aarti added yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),

          SizedBox(height: 4),

          Text('Add your regular Aartis below.', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ============================================================
  // ADD AARTI
  // ============================================================

  Future<bool?> _showAddAartiDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Aarti'),

          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Aarti name',
              hintText: 'Example: Mangal Aarti',
              prefixIcon: Icon(Icons.auto_awesome),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CANCEL'),
            ),

            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();

                if (name.isEmpty) {
                  return;
                }

                if (_userId == null) {
                  return;
                }

                try {
                  final now = DateTime.now().toIso8601String();

                  await _repository.addAarti(
                    AartiTypeModel(
                      userId: _userId!,
                      name: name,
                      sortOrder: 0,
                      createdAt: now,
                    ),
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('This Aarti may already exist.'),
                    ),
                  );
                }
              },
              child: const Text('ADD'),
            ),
          ],
        );
      },
    );

    return result;
  }

  // ============================================================
  // SELECTED SADHANA RECORDS
  //
  // IMPORTANT:
  // _allSadhanaRecords contains ALL types.
  //
  // These helper methods filter it to the currently selected
  // type whenever the statistic is supposed to be type-specific.
  // ============================================================

  List<DailySadhanaModel> _getSelectedSadhanaRecords() {
    final selectedId = _selectedSadhanaTypeId;

    if (selectedId == null) {
      return [];
    }

    return _allSadhanaRecords
        .where((record) => record.sadhanaTypeId == selectedId)
        .toList();
  }

  // ============================================================
  // HIGHEST STREAK
  // ============================================================

  int _calculateHighestStreak() {
    // Aarti has its own attendance records.
    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      if (_allAartiRecords.isEmpty) {
        return 0;
      }

      final dates =
          _allAartiRecords
              .map((record) => record.date)
              .toSet()
              .map(DateTime.parse)
              .toList()
            ..sort();

      return _findHighestConsecutiveDays(dates);
    }

    // IMPORTANT:
    // Only calculate streak for the selected Sadhana.
    //
    // Previously _allSadhanaRecords could contain one selected
    // type only. Now it contains ALL types, so we must filter it.
    final selectedRecords = _getSelectedSadhanaRecords();

    if (selectedRecords.isEmpty) {
      return 0;
    }

    final dates =
        selectedRecords
            .where((record) => record.value > 0)
            .map((record) => record.date)
            .toSet()
            .map(DateTime.parse)
            .toList()
          ..sort();

    return _findHighestConsecutiveDays(dates);
  }

  // ============================================================
  // CURRENT STREAK
  // ============================================================

  int _calculateCurrentStreak() {
    // Aarti streak.
    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      if (_allAartiRecords.isEmpty) {
        return 0;
      }

      final dates = _allAartiRecords
          .map((record) => record.date)
          .toSet()
          .map(DateTime.parse)
          .toSet();

      DateTime date = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      int streak = 0;

      while (dates.contains(date)) {
        streak++;

        date = date.subtract(const Duration(days: 1));

        if (streak > 3650) {
          break;
        }
      }

      return streak;
    }

    // IMPORTANT:
    // Only selected Sadhana records should contribute to
    // the selected Sadhana streak.
    final selectedRecords = _getSelectedSadhanaRecords();

    if (selectedRecords.isEmpty) {
      return 0;
    }

    final dates = selectedRecords
        .where((record) => record.value > 0)
        .map((record) => record.date)
        .toSet()
        .map(DateTime.parse)
        .toSet();

    DateTime date = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    int streak = 0;

    while (dates.contains(date)) {
      streak++;

      date = date.subtract(const Duration(days: 1));

      if (streak > 3650) {
        break;
      }
    }

    return streak;
  }

  // ============================================================
  // FIND HIGHEST CONSECUTIVE DAYS
  // ============================================================

  int _findHighestConsecutiveDays(List<DateTime> dates) {
    if (dates.isEmpty) {
      return 0;
    }

    if (dates.length == 1) {
      return 1;
    }

    int highestStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < dates.length; i++) {
      final difference = dates[i].difference(dates[i - 1]).inDays;

      if (difference == 1) {
        currentStreak++;

        if (currentStreak > highestStreak) {
          highestStreak = currentStreak;
        }
      } else {
        currentStreak = 1;
      }
    }

    return highestStreak;
  }

  // ============================================================
  // STREAK CARD
  // ============================================================

  Widget _buildStreakCard(BuildContext context) {
    final theme = Theme.of(context);

    final streak = _calculateCurrentStreak();

    final highestStreak = _calculateHighestStreak();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🔥', style: TextStyle(fontSize: 26)),
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current Streak', style: TextStyle(fontSize: 14)),

                  const SizedBox(height: 2),

                  Text(
                    '$streak ${streak == 1 ? 'Day' : 'Days'}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '🏆 Highest: $highestStreak '
                    '${highestStreak == 1 ? 'Day' : 'Days'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.local_fire_department),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SADHANA SELECTOR CARD
  // ============================================================

  Widget _buildSadhanaSelector(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _showSadhanaSelector,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(_getSadhanaIcon(), style: const TextStyle(fontSize: 26)),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly heatmap', style: theme.textTheme.bodySmall),

                    Text(
                      _selectedSadhana?.name ?? 'Sadhana',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.keyboard_arrow_down),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CALENDAR
  // ============================================================

  Widget _buildCalendar(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: TableCalendar(
          firstDay: DateTime(2020),

          lastDay: DateTime(2100),

          focusedDay: _focusedDay,

          selectedDayPredicate: (day) {
            return isSameDay(_selectedDay, day);
          },

          enabledDayPredicate: (day) {
            final today = DateTime.now();

            final currentDay = DateTime(today.year, today.month, today.day);

            final calendarDay = DateTime(day.year, day.month, day.day);

            return !calendarDay.isAfter(currentDay);
          },

          onDaySelected: _onDaySelected,

          onPageChanged: (focusedDay) async {
            setState(() {
              _focusedDay = focusedDay;
            });

            await _loadMonthlyData();
          },

          calendarFormat: CalendarFormat.month,
          availableGestures: AvailableGestures.horizontalSwipe,
          rowHeight: 64,

          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            leftChevronIcon: Icon(Icons.chevron_left),
            rightChevronIcon: Icon(Icons.chevron_right),
          ),

          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            weekendStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          calendarStyle: const CalendarStyle(
            outsideDaysVisible: false,
            isTodayHighlighted: false,
            markersMaxCount: 0,
          ),

          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) {
              return _buildCalendarCell(context, day);
            },

            todayBuilder: (context, day, focusedDay) {
              return _buildCalendarCell(context, day, isToday: true);
            },

            selectedBuilder: (context, day, focusedDay) {
              return _buildCalendarCell(context, day, isSelected: true);
            },
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CALENDAR CELL
  // ============================================================

  Widget _buildCalendarCell(
    BuildContext context,
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    final theme = Theme.of(context);

    final isAarti = _selectedSadhana?.name.toLowerCase() == 'aarti';

    final double value = isAarti
        ? (_monthlyAarti[_dateKey(day)] ?? 0).toDouble()
        : _getValueForDay(day);

    final double? progress = isAarti
        ? _getAartiGoalProgress(day)
        : _getGoalProgressForDay(day);

    final heatColor = _getHeatColor(context, progress);

    final hasValue = value > 0;

    final reachedGoal = progress != null && progress >= 1.0;

    final valueTextColor = reachedGoal
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    final dayNote = _getDayNote(day);

    final isImportant = dayNote?.isStarred ?? false;
    final isSankirtan = dayNote?.isSankirtan ?? false;
    final isEkadashi = dayNote?.isEkadashi ?? false;
    final isFestival = dayNote?.isFestival ?? false;

    final hasNote = dayNote?.note != null && dayNote!.note!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: heatColor,
        borderRadius: BorderRadius.circular(10),
        border: isSelected
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : isToday
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Stack(
        children: [
          // ============================================================
          // DATE - TOP LEFT
          // ============================================================
          // ============================================================
          // TOP ROW — DATE + EKADASHI
          // ============================================================
          // ============================================================
          // DATE - TOP LEFT
          // ============================================================
          Positioned(
            top: 4,
            left: 5,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday || isSelected
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),

          // ============================================================
          // EKADASHI - TOP RIGHT
          // ============================================================
          if (isEkadashi)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.nights_stay, size: 13, color: Colors.white),
            ),

          // ============================================================
          // CENTER VALUE
          // ============================================================
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              child: Center(
                child: hasValue
                    ? Text(
                        _formatValue(value),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: valueTextColor,
                        ),
                      )
                    : null,
              ),
            ),
          ),

          // ============================================================
          // BOTTOM INDICATORS
          // ============================================================
          if (isSankirtan || isFestival || isImportant || hasNote)
            Positioned(
              left: 3,
              right: 3,
              bottom: 2,
              child: SizedBox(
                height: 17,
                child: Row(
                  children: [
                    // SANKIRTAN
                    Expanded(
                      child: isSankirtan
                          ? _buildCalendarIndicator(
                              icon: Icons.music_note_rounded,
                              color: Colors.green.shade600,
                              size: 11,
                            )
                          : const SizedBox(),
                    ),

                    // FESTIVAL
                    Expanded(
                      child: isFestival
                          ? _buildCalendarIndicator(
                              icon: Icons.celebration_rounded,
                              color: Colors.orange.shade700,
                              size: 11,
                            )
                          : const SizedBox(),
                    ),

                    // IMPORTANT
                    Expanded(
                      child: isImportant
                          ? _buildCalendarIndicator(
                              icon: Icons.star_rounded,
                              color: Colors.amber.shade700,
                              size: 11,
                            )
                          : const SizedBox(),
                    ),

                    // NOTE
                    Expanded(
                      child: hasNote
                          ? _buildCalendarIndicator(
                              icon: Icons.note_alt_rounded,
                              color: Colors.blue.shade600,
                              size: 11,
                            )
                          : const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCalendarIndicator({
    required IconData icon,
    required Color color,
    double size = 11,
  }) {
    return Center(
      child: Icon(icon, size: size, color: color),
    );
  }
  // ============================================================
  // AARTI GOAL PROGRESS
  // ============================================================

  double? _getAartiGoalProgress(DateTime day) {
    final selected = _selectedSadhana;

    if (selected == null || selected.id == null) {
      return null;
    }

    final goal = _goals[selected.id!];

    if (goal == null || goal.targetValue <= 0) {
      return null;
    }

    final count = (_monthlyAarti[_dateKey(day)] ?? 0).toDouble();

    return count / goal.targetValue;
  }

  // ============================================================
  // GOAL PROGRESS NORMAL SADHANA
  // ============================================================

  double? _getGoalProgressForDay(DateTime day) {
    final selected = _selectedSadhana;

    if (selected == null || selected.id == null) {
      return null;
    }

    final goal = _goals[selected.id!];

    if (goal == null || goal.targetValue <= 0) {
      return null;
    }

    final value = _getValueForDay(day);

    if (value <= 0) {
      return 0;
    }

    if (selected.name.toLowerCase() == 'reading') {
      final dailyUnit = _getUnitForDay(day);

      final goalUnit = goal.unit;

      if (dailyUnit == null || goalUnit == null || dailyUnit != goalUnit) {
        return null;
      }
    }

    return value / goal.targetValue;
  }

  // ============================================================
  // GET UNIT FOR DAY
  // ============================================================

  String? _getUnitForDay(DateTime day) {
    final selected = _selectedSadhana;

    if (selected == null || selected.id == null) {
      return null;
    }

    final key = '${_dateKey(day)}_${selected.id}';

    return _monthlySadhanaByDate[key]?.unit;
  }

  // ============================================================
  // MONTHLY QUICK STATS
  //
  // IMPORTANT:
  // These stats intentionally use _allSadhanaRecords.
  //
  // Therefore they remain unchanged when the user switches
  // between Chanting / Reading / Hearing in the selector.
  // ============================================================
  Widget _buildMonthlyQuickStats(BuildContext context) {
    final theme = Theme.of(context);

    final monthStart = AppDateUtils.monthStart(_focusedDay);
    final monthEnd = AppDateUtils.monthEnd(_focusedDay);

    final start = DateTime.parse(monthStart);
    final end = DateTime.parse(monthEnd);

    final monthRecords = _allSadhanaRecords.where((record) {
      final date = DateTime.parse(record.date);

      return !date.isBefore(start) && !date.isAfter(end);
    }).toList();

    final monthAarti = _allAartiRecords.where((record) {
      final date = DateTime.parse(record.date);

      return !date.isBefore(start) && !date.isAfter(end);
    }).toList();

    // ----------------------------------------------------------
    // PRACTICED DAYS
    // ----------------------------------------------------------

    final practicedDates = <String>{};

    for (final record in monthRecords) {
      if (record.value > 0) {
        practicedDates.add(record.date);
      }
    }

    for (final record in monthAarti) {
      practicedDates.add(record.date);
    }

    // ----------------------------------------------------------
    // SADHANA TYPES
    // ----------------------------------------------------------

    final chanting = _findSadhana('chanting');
    final reading = _findSadhana('reading');
    final hearing = _findSadhana('hearing');

    // ----------------------------------------------------------
    // TOTALS
    // ----------------------------------------------------------

    double chantingTotal = 0;
    double readingTotal = 0;
    double hearingTotal = 0;

    // ----------------------------------------------------------
    // READING GOAL
    // ----------------------------------------------------------

    final readingGoal = reading?.id == null ? null : _goals[reading!.id!];

    // Current Reading unit.

    final readingUnit = readingGoal?.unit?.trim().isNotEmpty == true
        ? readingGoal!.unit!
        : 'pages';

    // ----------------------------------------------------------
    // CALCULATE TOTALS
    // ----------------------------------------------------------

    for (final record in monthRecords) {
      if (record.value <= 0) {
        continue;
      }

      // --------------------------------------------------------
      // CHANTING
      // --------------------------------------------------------

      if (chanting != null && record.sadhanaTypeId == chanting.id) {
        chantingTotal += record.value;
      }

      // --------------------------------------------------------
      // READING
      // --------------------------------------------------------

      if (reading != null && record.sadhanaTypeId == reading.id) {
        final recordUnit = record.unit?.trim().isNotEmpty == true
            ? record.unit!.trim()
            : 'pages';

        // Only count records using the current Reading unit.
        if (recordUnit == readingUnit) {
          readingTotal += record.value;
        }
      }

      // --------------------------------------------------------
      // HEARING
      // --------------------------------------------------------

      if (hearing != null && record.sadhanaTypeId == hearing.id) {
        hearingTotal += record.value;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------------------------------------------
            // HEADER
            // ----------------------------------------------------
            Row(
              children: [
                const Text(
                  'Monthly Quick Stats',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const Spacer(),

                Text(
                  DateFormat('MMMM yyyy').format(_focusedDay),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ----------------------------------------------------
            // ROW 1
            // ----------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.calendar_today_outlined,
                    value: '${practicedDates.length}',
                    label: 'Days practiced',
                  ),
                ),

                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.self_improvement,
                    value: _formatValue(chantingTotal),
                    label: 'Rounds',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ----------------------------------------------------
            // ROW 2
            // ----------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.menu_book_outlined,
                    value: _formatValue(readingTotal),
                    label: _formatReadingUnitLabel(readingUnit),
                  ),
                ),

                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.headphones_outlined,
                    value: _formatValue(hearingTotal),
                    label: 'Hearing min',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ----------------------------------------------------
            // ROW 3
            // ----------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.local_fire_department_outlined,
                    value: '${monthAarti.length}',
                    label: 'Aarti attendance',
                  ),
                ),

                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // READING UNIT LABEL
  // ============================================================

  String _formatReadingUnitLabel(String unit) {
    switch (unit.toLowerCase()) {
      case 'page':
      case 'pages':
        return 'Pages';

      case 'shloka':
      case 'shlokas':
        return 'Shlokas';

      case 'minute':
      case 'minutes':
        return 'Reading min';

      default:
        return unit;
    }
  }
  // ============================================================
  // STAT ITEM
  // ============================================================

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MONTHLY INSIGHTS CARD
  // ============================================================

  Widget _buildMonthlyInsightsCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MonthlyInsightsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.insights_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Insights',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      'See your progress, patterns and devotional consistency.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FIXED TODAY BUTTON
  // ============================================================

  Widget _buildFixedTodayButton(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DayInsightsScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text(
              "UPDATE TODAY'S SADHANA",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // RELOAD GOALS
  // ============================================================

  Future<void> _reloadGoals() async {
    if (_userId == null) {
      return;
    }

    try {
      final Map<int, GoalModel?> loadedGoals = {};

      for (final type in _sadhanaTypes) {
        if (type.id == null) {
          continue;
        }

        loadedGoals[type.id!] = await _repository.getGoal(_userId!, type.id!);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _goals.clear();

        _goals.addAll(loadedGoals);

        _currentGoal = _selectedSadhanaTypeId == null
            ? null
            : _goals[_selectedSadhanaTypeId!];
      });

      await _loadMonthlyData();
    } catch (e) {
      debugPrint('Error reloading goals: $e');
    }
  }

  // ------------------------------------------------------------------
  // PENDING ROUNDS DIALOG
  // ------------------------------------------------------------------
  Future<void> _showPendingRoundsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentRounds = prefs.getInt('pending_rounds') ?? 0;
    final controller = TextEditingController(text: currentRounds.toString());

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Update Pending Rounds'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pending Rounds',
              hintText: 'Enter total pending rounds',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () async {
                final newRounds = int.tryParse(controller.text) ?? 0;
                await prefs.setInt('pending_rounds', newRounds);

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                setState(() {});
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // YOUTUBE LINKS MANAGER DIALOG
  // ------------------------------------------------------------------
  Future<void> _showManageLinksDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> links = prefs.getStringList('saved_links') ?? [];

    final titleController = TextEditingController();
    final urlController = TextEditingController();

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Saved Links'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (links.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No links added yet.'),
                        )
                      else
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: links.length,
                          onReorder: (int oldIndex, int newIndex) async {
                            if (oldIndex < newIndex) {
                              newIndex -= 1;
                            }
                            final String item = links.removeAt(oldIndex);
                            links.insert(newIndex, item);

                            await prefs.setStringList('saved_links', links);
                            setDialogState(() {});
                            setState(() {});
                          },
                          itemBuilder: (context, index) {
                            final parts = links[index].split('|');
                            final title = parts[0];
                            final url = parts.length > 1 ? parts[1] : parts[0];

                            return ListTile(
                              key: ValueKey(links[index]),
                              contentPadding: EdgeInsets.zero,
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.drag_handle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  const SizedBox(width: 8),
                                  _getLinkIcon(url),
                                ],
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  links.removeAt(index);
                                  await prefs.setStringList(
                                    'saved_links',
                                    links,
                                  );
                                  setDialogState(() {});
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      const Divider(),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Add New Link',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Name (e.g. SB Classes / Resource Doc)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'URL (e.g. https://...)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CLOSE'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    var url = urlController.text.trim();

                    if (url.isNotEmpty) {
                      // Prepend https:// if user didn't include protocol
                      if (!url.startsWith('http://') &&
                          !url.startsWith('https://')) {
                        url = 'https://$url';
                      }

                      final entry = title.isNotEmpty ? '$title|$url' : url;
                      links.add(entry);
                      await prefs.setStringList('saved_links', links);

                      titleController.clear();
                      urlController.clear();

                      setDialogState(() {});
                      setState(() {});
                    }
                  },
                  child: const Text('ADD'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _getChipAvatar(String url) {
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be')) {
      return Container(
        width: 20,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
        ),
      );
    }

    // Standard Web Icon Avatar
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.language, color: Colors.blue.shade800, size: 12),
    );
  }

  // Helper method to dynamically swap icons based on destination URL
  Widget _getLinkIcon(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be')) {
      return const Icon(Icons.play_circle_fill, color: Colors.red);
    }
    return const Icon(Icons.language, color: Colors.blue);
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      // ============================================================
      // NAVIGATION DRAWER (HAMBURGER MENU)
      // ============================================================
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'BhaktiChart',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (_name.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Hare Krishna, $_name 🙏',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ============================================================
            // HORIZONTAL LINKS ROW (VEDABASE + YOUTUBE LINKS + ADD BUTTON)
            // ============================================================
            SizedBox(
              height: 48,
              child: FutureBuilder<List<String>>(
                future: SharedPreferences.getInstance().then((prefs) {
                  // Fetches saved_links, with fallback to youtube_links for backward compatibility
                  return prefs.getStringList('saved_links') ??
                      prefs.getStringList('youtube_links') ??
                      [];
                }),
                builder: (context, snapshot) {
                  final savedLinks = snapshot.data ?? [];
                  final theme = Theme.of(context);

                  return ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      // Vedabase Link Badge
                      ActionChip(
                        avatar: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color:
                                Colors.amber, // Golden/orange book cover tone
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Text(
                              'V',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                fontFamily: 'Roboto',
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                        label: const Text('Vedabase'),
                        backgroundColor: theme.colorScheme.surface,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          final uri = Uri.parse('https://vedabase.io/');

                          try {
                            final launched = await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!launched && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open browser link'),
                                ),
                              );
                            }
                          } catch (e) {
                            debugPrint('Error launching URL: $e');
                          }
                        },
                      ),
                      const SizedBox(width: 8),

                      // Stored Link Badges (YouTube & General Websites)
                      ...savedLinks.map((entry) {
                        final parts = entry.split('|');
                        final title = parts[0];
                        final url = parts.length > 1 ? parts[1] : parts[0];

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            avatar: _getChipAvatar(url),
                            label: Text(title),
                            backgroundColor: theme.colorScheme.surface,
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                        );
                      }),

                      // Add Link Badge (At the end of the horizontal row)
                      ActionChip(
                        avatar: Icon(
                          Icons.add,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                        label: Text(
                          'Add Link',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: theme.colorScheme.primaryContainer
                            .withOpacity(0.4),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withOpacity(0.5),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await _showManageLinksDialog(context);
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 4.0,
              ),
              child: FutureBuilder<int>(
                future: SharedPreferences.getInstance().then(
                  (prefs) => prefs.getInt('pending_rounds') ?? 0,
                ),
                builder: (context, snapshot) {
                  final rounds = snapshot.data ?? 0;
                  final hasPending = rounds > 0;

                  return Material(
                    color: hasPending
                        ? theme.colorScheme.errorContainer.withOpacity(0.7)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.autorenew,
                        color: hasPending
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        'Pending Rounds',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: hasPending
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        '$rounds rounds',
                        style: TextStyle(
                          color: hasPending
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hasPending
                              ? theme.colorScheme.error
                              : theme.colorScheme.outline,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$rounds',
                          style: TextStyle(
                            color: hasPending
                                ? theme.colorScheme.errorContainer.withOpacity(
                                    0.7,
                                  )
                                : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await _showPendingRoundsDialog(context);
                      },
                    ),
                  );
                },
              ),
            ),

            const Divider(),
            // Daily Routine
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Daily Routine'),
              onTap: () async {
                Navigator.pop(context); // Close Drawer
                if (_userId == null) return;

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyRoutineScreen(userId: _userId!),
                  ),
                );
              },
            ),

            // Daily Diary
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Daily Diary'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DailyDiaryScreen()),
                );
              },
            ),

            // Sadhana Reminders
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Sadhana Reminders'),
              onTap: () {
                Navigator.pop(context);
                _openReminders();
              },
            ),

            const Divider(),

            // Statistics
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Statistics'),
              onTap: () async {
                Navigator.pop(context);
                if (_userId == null) return;

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StatisticsScreen(userId: _userId!),
                  ),
                );
              },
            ),

            // Day Insights
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Day Insights'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DayInsightsScreen()),
                );
              },
            ),

            // Monthly Insights
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Monthly Insights'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MonthlyInsightsScreen(),
                  ),
                );
              },
            ),

            const Divider(),

            // Settings / Goals
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GoalsScreen()),
                );

                if (mounted) {
                  await _reloadGoals();
                  await _loadHomeData();
                }
              },
            ),
          ],
        ),
      ),
      // ============================================================
      // APP BAR
      // ============================================================
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BhaktiChart',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_name.isNotEmpty)
              Text('Hare Krishna, $_name 🙏', style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          // ============================================================
          // LEARNING TRACKER - STANDALONE
          // ============================================================
          IconButton(
            tooltip: 'Learning Tracker',
            icon: const Icon(Icons.auto_stories_rounded),
            onPressed: () async {
              if (_userId == null) return;

              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LearningTrackerScreen(userId: _userId!),
                ),
              );
            },
          ),

          // ============================================================
          // DAILY CHECKLIST - STANDALONE
          // ============================================================
          IconButton(
            tooltip: 'Daily Checklist',
            icon: const Icon(Icons.checklist_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DailyTodoScreen()),
              );
            },
          ),
          // ============================================================
          // HAMBURGER MENU AT THE RIGHT END
          // ============================================================
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.segment),
                tooltip: 'Menu',
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
              );
            },
          ),
        ],
      ),
      // ========================================================
      // FIXED BOTTOM BUTTON
      // ========================================================
      bottomNavigationBar: _buildFixedTodayButton(context),

      // ========================================================
      // BODY
      // ========================================================
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMonthlyData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------
                // TODAY'S SADHANA
                // ------------------------------------------------
                _buildTodaySadhana(context),

                const SizedBox(height: 16),

                // ------------------------------------------------
                // STREAK
                // ------------------------------------------------
                _buildStreakCard(context),

                const SizedBox(height: 16),

                // ------------------------------------------------
                // SADHANA SELECTOR
                // ------------------------------------------------
                _buildSadhanaSelector(context),

                const SizedBox(height: 12),

                // ------------------------------------------------
                // MONTHLY CALENDAR
                // ------------------------------------------------
                _buildCalendar(context),

                const SizedBox(height: 16),

                // ------------------------------------------------
                // MONTHLY QUICK STATS
                // ------------------------------------------------
                _buildMonthlyQuickStats(context),

                const SizedBox(height: 16),

                // ------------------------------------------------
                // MONTHLY INSIGHTS
                // ------------------------------------------------
                _buildMonthlyInsightsCard(context),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
