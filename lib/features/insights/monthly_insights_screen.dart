import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_utils.dart';
import '../../models/daily_aarti_model.dart';
import '../../models/daily_sadhana_model.dart';
import '../../models/day_note_model.dart';
import '../../models/goal_model.dart';
import '../../models/sadhana_type_model.dart';
import '../../repositories/sadhana_repository.dart';

class MonthlyInsightsScreen extends StatefulWidget {
  const MonthlyInsightsScreen({super.key});

  @override
  State<MonthlyInsightsScreen> createState() => _MonthlyInsightsScreenState();
}

class _MonthlyInsightsScreenState extends State<MonthlyInsightsScreen> {
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
  // MONTH
  // ============================================================

  DateTime _focusedMonth = DateTime.now();

  // ============================================================
  // SADHANA TYPES
  // ============================================================

  List<SadhanaTypeModel> _sadhanaTypes = [];

  int? _selectedSadhanaTypeId;

  // ============================================================
  // DATA
  // ============================================================

  List<DailySadhanaModel> _sadhanaRecords = [];

  List<DailyAartiModel> _aartiRecords = [];

  final Map<String, DayNoteModel> _notesByDate = {};

  GoalModel? _goal;

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
    _loadData();
  }

  // ============================================================
  // DATE KEY
  // ============================================================

  String _dateKey(DateTime date) {
    return AppDateUtils.formatDate(date);
  }

  // ============================================================
  // NORMALIZE DATE
  // ============================================================

  String _normalizeDate(String date) {
    if (date.length >= 10) {
      return date.substring(0, 10);
    }

    return date;
  }

  // ============================================================
  // MONTH START
  // ============================================================

  String get _monthStart {
    return AppDateUtils.monthStart(_focusedMonth);
  }

  // ============================================================
  // MONTH END
  // ============================================================

  String get _monthEnd {
    return AppDateUtils.monthEnd(_focusedMonth);
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
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    try {
      final user = await _repository.getUser();

      if (user == null || user.id == null) {
        return;
      }

      final types = await _repository.getSadhanaTypes();

      if (!mounted) {
        return;
      }

      _userId = user.id;
      _name = user.name;
      _sadhanaTypes = types;

      // ----------------------------------------------------------
      // SELECT CHANTING BY DEFAULT
      // ----------------------------------------------------------

      if (_selectedSadhanaTypeId == null && types.isNotEmpty) {
        SadhanaTypeModel? selected;

        try {
          selected = types.firstWhere(
            (type) => type.name.toLowerCase() == 'chanting',
          );
        } catch (_) {
          selected = types.first;
        }

        _selectedSadhanaTypeId = selected.id;
      }

      await _loadMonthData();
    } catch (e) {
      debugPrint('Error loading insights: $e');
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

  Future<void> _loadMonthData() async {
    if (_userId == null || _selectedSadhanaTypeId == null) {
      return;
    }

    try {
      debugPrint('====================================');
      debugPrint('MONTH: $_monthStart -> $_monthEnd');
      debugPrint('USER ID: $_userId');
      debugPrint('SELECTED TYPE: $_selectedSadhanaTypeId');

      // ----------------------------------------------------------
      // LOAD SADHANA
      // ----------------------------------------------------------

      final records = await _repository.getSadhanaForMonth(
        _userId!,
        _monthStart,
        _monthEnd,
      );

      // ----------------------------------------------------------
      // LOAD AARTI
      // ----------------------------------------------------------

      final aartiRecords = await _repository.getAartiAttendanceForMonth(
        _userId!,
        _monthStart,
        _monthEnd,
      );

      // ----------------------------------------------------------
      // LOAD NOTES / DAY TYPES
      // ----------------------------------------------------------

      final monthNotes = await _repository.getDayNotesForMonth(
        _userId!,
        _monthStart,
        _monthEnd,
      );

      final notes = <String, DayNoteModel>{
        for (final note in monthNotes) note.date: note,
      };

      // ----------------------------------------------------------
      // LOAD GOAL
      // ----------------------------------------------------------

      final goal = await _repository.getGoal(_userId!, _selectedSadhanaTypeId!);

      // ----------------------------------------------------------
      // DEBUG
      // ----------------------------------------------------------

      debugPrint('SADHANA RECORDS: ${records.length}');
      debugPrint('AARTI RECORDS: ${aartiRecords.length}');
      debugPrint('NOTES: ${monthNotes.length}');
      debugPrint('GOAL: ${goal?.targetValue} ${goal?.unit}');

      for (final record in records) {
        debugPrint(
          'SADHANA: '
          'date=${record.date}, '
          'type=${record.sadhanaTypeId}, '
          'value=${record.value}, '
          'unit=${record.unit}',
        );
      }

      for (final record in aartiRecords) {
        debugPrint(
          'AARTI: '
          'date=${record.date}, '
          'type=${record.aartiTypeId}',
        );
      }

      for (final note in monthNotes) {
        debugPrint(
          'NOTE: '
          'date=${note.date}, '
          'starred=${note.isStarred}, '
          'sankirtan=${note.isSankirtan}, '
          'ekadashi=${note.isEkadashi}, '
          'festival=${note.isFestival}, '
          'note=${note.note}',
        );
      }

      debugPrint('====================================');

      if (!mounted) {
        return;
      }

      setState(() {
        _sadhanaRecords = records;
        _aartiRecords = aartiRecords;

        _notesByDate
          ..clear()
          ..addAll(notes);

        _goal = goal;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading monthly insights: $e');
      debugPrint('$stackTrace');
    }
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
    });

    await _loadMonthData();
  }

  // ============================================================
  // MONTH NAVIGATION
  // ============================================================

  Future<void> _changeMonth(int amount) async {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + amount,
        1,
      );

      _isLoading = true;
    });

    await _loadMonthData();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // CURRENT MONTH
  // ============================================================

  bool get _isCurrentMonth {
    final now = DateTime.now();

    return _focusedMonth.year == now.year && _focusedMonth.month == now.month;
  }

  // ============================================================
  // SELECTED RECORDS
  // ============================================================

  List<DailySadhanaModel> get _selectedRecords {
    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      return [];
    }

    return _sadhanaRecords
        .where((record) => record.sadhanaTypeId == _selectedSadhanaTypeId)
        .toList();
  }

  // ============================================================
  // TOTAL VALUE
  // ============================================================

  double get _totalValue {
    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      return _aartiRecords.length.toDouble();
    }

    return _selectedRecords.fold(0.0, (sum, record) => sum + record.value);
  }

  // ============================================================
  // DAYS PRACTICED
  // ============================================================

  int get _daysPracticed {
    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      return _aartiRecords
          .map((record) => _normalizeDate(record.date))
          .toSet()
          .length;
    }

    return _selectedRecords
        .where((record) => record.value > 0)
        .map((record) => _normalizeDate(record.date))
        .toSet()
        .length;
  }

  // ============================================================
  // DAYS IN MONTH
  // ============================================================

  int get _daysInMonth {
    return DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
  }

  // ============================================================
  // DAY TYPE COUNTS
  // ============================================================

  int get _sankirtanDays {
    return _notesByDate.values.where((note) => note.isSankirtan).length;
  }

  int get _ekadashiDays {
    return _notesByDate.values.where((note) => note.isEkadashi).length;
  }

  int get _festivalDays {
    return _notesByDate.values.where((note) => note.isFestival).length;
  }

  int get _importantDaysCount {
    return _notesByDate.values.where((note) => note.isStarred).length;
  }

  // ============================================================
  // GOAL COMPLETED DAYS
  // ============================================================

  int get _goalCompletedDays {
    if (_goal == null || _goal!.targetValue <= 0) {
      return 0;
    }

    // ------------------------------------------------------------
    // AARTI
    // ------------------------------------------------------------

    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      final countByDate = <String, int>{};

      for (final record in _aartiRecords) {
        final date = _normalizeDate(record.date);

        countByDate[date] = (countByDate[date] ?? 0) + 1;
      }

      return countByDate.values
          .where((count) => count >= _goal!.targetValue)
          .length;
    }

    // ------------------------------------------------------------
    // NORMAL SADHANA
    // ------------------------------------------------------------

    final completedDates = <String>{};

    for (final record in _selectedRecords) {
      if (record.value <= 0) {
        continue;
      }

      if (_selectedSadhana?.name.toLowerCase() == 'reading') {
        if (record.unit == null || _goal!.unit == null) {
          continue;
        }

        if (record.unit != _goal!.unit) {
          continue;
        }
      }

      if (record.value >= _goal!.targetValue) {
        completedDates.add(_normalizeDate(record.date));
      }
    }

    return completedDates.length;
  }

  // ============================================================
  // GOAL COMPLETION %
  // ============================================================

  double get _goalCompletionPercentage {
    if (_daysPracticed <= 0 || _goal == null || _goal!.targetValue <= 0) {
      return 0;
    }

    return (_goalCompletedDays / _daysPracticed) * 100;
  }

  // ============================================================
  // BEST DAY
  // ============================================================

  DailySadhanaModel? get _bestDay {
    // ------------------------------------------------------------
    // AARTI
    // ------------------------------------------------------------

    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      if (_aartiRecords.isEmpty) {
        return null;
      }

      final countByDate = <String, int>{};

      for (final record in _aartiRecords) {
        final date = _normalizeDate(record.date);

        countByDate[date] = (countByDate[date] ?? 0) + 1;
      }

      String? bestDate;
      int bestCount = 0;

      for (final entry in countByDate.entries) {
        if (entry.value > bestCount) {
          bestDate = entry.key;
          bestCount = entry.value;
        }
      }

      if (bestDate == null) {
        return null;
      }

      return DailySadhanaModel(
        userId: _userId!,
        date: bestDate,
        sadhanaTypeId: _selectedSadhanaTypeId!,
        value: bestCount.toDouble(),
        unit: 'aartis',
        createdAt: '',
      );
    }

    // ------------------------------------------------------------
    // NORMAL SADHANA
    // ------------------------------------------------------------

    if (_selectedRecords.isEmpty) {
      return null;
    }

    DailySadhanaModel? best;

    for (final record in _selectedRecords) {
      if (record.value <= 0) {
        continue;
      }

      if (best == null || record.value > best.value) {
        best = record;
      }
    }

    return best;
  }

  // ============================================================
  // AARTI DAYS
  // ============================================================

  int get _aartiDays {
    return _aartiRecords
        .map((record) => _normalizeDate(record.date))
        .toSet()
        .length;
  }

  // ============================================================
  // TOTAL AARTI
  // ============================================================

  int get _totalAarti {
    return _aartiRecords.length;
  }

  // ============================================================
  // AARTI AVERAGE PER DAY
  // ============================================================

  double get _averageAartiPerDay {
    if (_aartiDays == 0) {
      return 0;
    }

    return _totalAarti / _aartiDays;
  }

  // ============================================================
  // IMPORTANT DAYS
  // ============================================================

  List<DayNoteModel> get _importantDays {
    final result = _notesByDate.values.where((note) => note.isStarred).toList();

    result.sort((a, b) => a.date.compareTo(b.date));

    return result;
  }

  // ============================================================
  // NOTES COUNT
  // ============================================================

  int get _notesCount {
    return _notesByDate.values
        .where((note) => note.note != null && note.note!.trim().isNotEmpty)
        .length;
  }

  // ============================================================
  // CURRENT STREAK
  // ============================================================

  int get _currentStreak {
    // ------------------------------------------------------------
    // AARTI
    // ------------------------------------------------------------

    if (_selectedSadhana?.name.toLowerCase() == 'aarti') {
      if (_aartiRecords.isEmpty) {
        return 0;
      }

      final attendedDates = _aartiRecords
          .map((record) => _normalizeDate(record.date))
          .toSet();

      DateTime date;

      if (_isCurrentMonth) {
        date = DateTime.now();
      } else {
        date = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
      }

      int streak = 0;

      while (true) {
        final key = _dateKey(date);

        if (!attendedDates.contains(key)) {
          break;
        }

        streak++;

        date = date.subtract(const Duration(days: 1));

        if (date.month != _focusedMonth.month ||
            date.year != _focusedMonth.year) {
          break;
        }
      }

      return streak;
    }

    // ------------------------------------------------------------
    // NORMAL SADHANA
    // ------------------------------------------------------------

    if (_selectedRecords.isEmpty) {
      return 0;
    }

    final valueByDate = <String, double>{};

    for (final record in _selectedRecords) {
      final date = _normalizeDate(record.date);

      valueByDate[date] = record.value;
    }

    DateTime date;

    if (_isCurrentMonth) {
      date = DateTime.now();
    } else {
      date = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    }

    int streak = 0;

    while (true) {
      final key = _dateKey(date);

      final value = valueByDate[key] ?? 0;

      if (value <= 0) {
        break;
      }

      streak++;

      date = date.subtract(const Duration(days: 1));

      if (date.month != _focusedMonth.month ||
          date.year != _focusedMonth.year) {
        break;
      }
    }

    return streak;
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
  // UNIT
  // ============================================================

  String get _unit {
    if (_goal?.unit != null && _goal!.unit!.isNotEmpty) {
      return _goal!.unit!;
    }

    switch (_selectedSadhana?.name.toLowerCase()) {
      case 'chanting':
        return 'rounds';

      case 'hearing':
        return 'minutes';

      case 'reading':
        return 'pages';

      case 'aarti':
        return 'aartis';

      default:
        return 'times';
    }
  }

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (subtitle != null) ...[
                    const SizedBox(height: 2),

                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MONTH HEADER
  // ============================================================

  Widget _buildMonthHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: _isLoading ? null : () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),

            Expanded(
              child: Column(
                children: [
                  Text(
                    DateFormat('MMMM yyyy').format(_focusedMonth),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (_isCurrentMonth)
                    Text(
                      'Current month',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),

            IconButton(
              tooltip: 'Next month',
              onPressed: _isLoading ? null : () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SADHANA SELECTOR
  // ============================================================

  Widget _buildSadhanaSelector(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _showSadhanaSelector,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                _selectedSadhana?.icon ?? '🙏',
                style: const TextStyle(fontSize: 28),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Insights for', style: theme.textTheme.bodySmall),

                    const SizedBox(height: 2),

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
  // SADHANA SELECTOR SHEET
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
                  'Choose Sadhana',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                ..._sadhanaTypes.map((type) {
                  final selected = type.id == _selectedSadhanaTypeId;

                  return ListTile(
                    leading: Text(
                      type.icon ?? '🙏',
                      style: const TextStyle(fontSize: 28),
                    ),

                    title: Text(
                      type.name,
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

                    onTap: () async {
                      Navigator.pop(sheetContext);

                      await _selectSadhana(type);
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
  // SUMMARY HEADER
  // ============================================================

  Widget _buildSummaryHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              _selectedSadhana?.icon ?? '🙏',
              style: const TextStyle(fontSize: 42),
            ),

            const SizedBox(height: 8),

            Text(
              '${_formatValue(_totalValue)} $_unit',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Total ${_selectedSadhana?.name ?? 'Sadhana'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // GOAL CARD
  // ============================================================

  Widget _buildGoalCard(BuildContext context) {
    final theme = Theme.of(context);

    if (_goal == null || _goal!.targetValue <= 0) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('No daily goal set'),
          subtitle: const Text('Set a goal to track monthly goal completion.'),
        ),
      );
    }

    final progress = (_goalCompletionPercentage / 100).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: theme.colorScheme.primary),

                const SizedBox(width: 8),

                const Text(
                  'Goal Achievement',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Daily goal'),

                Text(
                  '${_formatValue(_goal!.targetValue)} '
                  '${_goal!.unit ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(value: progress, minHeight: 10),
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_goalCompletedDays / $_daysPracticed days'),

                Text(
                  '${_goalCompletionPercentage.clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
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
  // BEST DAY CARD
  // ============================================================

  Widget _buildBestDayCard(BuildContext context) {
    final best = _bestDay;

    if (best == null) {
      return _buildStatCard(
        context,
        icon: Icons.emoji_events_outlined,
        title: 'Best Day',
        value: '—',
        subtitle: 'No data yet',
      );
    }

    DateTime? date;

    try {
      date = DateTime.parse(best.date);
    } catch (_) {}

    final dateText = date == null
        ? best.date
        : DateFormat('EEE, d MMM').format(date);

    return _buildStatCard(
      context,
      icon: Icons.emoji_events_outlined,
      title: 'Best Day',
      value: '${_formatValue(best.value)} $_unit',
      subtitle: dateText,
    );
  }

  // ============================================================
  // DAY TYPE SUMMARY
  // ============================================================

  Widget _buildDayTypeSummary(BuildContext context) {
    final theme = Theme.of(context);

    final hasAnyDayType =
        _sankirtanDays > 0 ||
        _ekadashiDays > 0 ||
        _festivalDays > 0 ||
        _importantDaysCount > 0;

    if (!hasAnyDayType) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(
                Icons.event_note_outlined,
                size: 38,
                color: theme.colorScheme.onSurfaceVariant,
              ),

              const SizedBox(height: 8),

              const Text(
                'No marked days',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 4),

              Text(
                'Sankirtan, Ekadashi, festivals and important days will appear here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_note_outlined,
                  color: theme.colorScheme.primary,
                ),

                const SizedBox(width: 8),

                const Text(
                  'Day Types',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_sankirtanDays > 0)
                  _buildDayTypeInsightChip(
                    context,
                    icon: Icons.groups_2,
                    label: 'Sankirtan',
                    count: _sankirtanDays,
                  ),

                if (_ekadashiDays > 0)
                  _buildDayTypeInsightChip(
                    context,
                    icon: Icons.brightness_2,
                    label: 'Ekadashi',
                    count: _ekadashiDays,
                  ),

                if (_festivalDays > 0)
                  _buildDayTypeInsightChip(
                    context,
                    icon: Icons.celebration,
                    label: 'Festival',
                    count: _festivalDays,
                  ),

                if (_importantDaysCount > 0)
                  _buildDayTypeInsightChip(
                    context,
                    icon: Icons.star,
                    label: 'Important',
                    count: _importantDaysCount,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DAY TYPE CHIP
  // ============================================================

  Widget _buildDayTypeInsightChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),

          const SizedBox(width: 6),

          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),

          const SizedBox(width: 5),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // IMPORTANT DAYS
  // ============================================================

  Widget _buildImportantDays(BuildContext context) {
    final theme = Theme.of(context);

    if (_importantDays.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.star_border,
                size: 42,
                color: theme.colorScheme.onSurfaceVariant,
              ),

              const SizedBox(height: 8),

              const Text(
                'No important days',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 4),

              Text(
                'Star important days from the calendar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.star, color: Colors.amber),

                SizedBox(width: 8),

                Text(
                  'Important Days',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ..._importantDays.map((note) {
              DateTime? date;

              try {
                date = DateTime.parse(note.date);
              } catch (_) {}

              final dateText = date == null
                  ? note.date
                  : DateFormat('EEE, d MMM yyyy').format(date);

              return ListTile(
                contentPadding: EdgeInsets.zero,

                leading: const CircleAvatar(
                  child: Icon(Icons.star, color: Colors.amber),
                ),

                title: Text(
                  dateText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                subtitle: note.note == null || note.note!.trim().isEmpty
                    ? const Text('No note')
                    : Text(
                        note.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // AARTI SUMMARY
  // ============================================================

  Widget _buildAartiSummary(BuildContext context) {
    final average = _averageAartiPerDay;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_fire_department_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aarti Attendance',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '$_totalAarti',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        '$_aartiDays days with Aarti',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_aartiDays > 0) ...[
              const SizedBox(height: 14),

              const Divider(),

              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Average per Aarti day'),

                  Text(
                    average == average ? average.toStringAsFixed(1) : '0',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
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
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Insights',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            if (_name.isNotEmpty)
              Text('Hare Krishna, $_name 🙏', style: theme.textTheme.bodySmall),
          ],
        ),
      ),

      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMonthData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // =================================================
                // MONTH
                // =================================================
                _buildMonthHeader(context),

                const SizedBox(height: 12),

                // =================================================
                // SADHANA
                // =================================================
                _buildSadhanaSelector(context),

                const SizedBox(height: 16),

                // =================================================
                // MAIN SUMMARY
                // =================================================
                _buildSummaryHeader(context),

                const SizedBox(height: 12),

                // =================================================
                // STAT GRID
                // =================================================
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        icon: Icons.calendar_month,
                        title: 'Days Practiced',
                        value: '$_daysPracticed',
                        subtitle: 'of $_daysInMonth days',
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _buildStatCard(
                        context,
                        icon: Icons.local_fire_department,
                        title: 'Current Streak',
                        value: '$_currentStreak',
                        subtitle: 'days',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // =================================================
                // BEST DAY
                // =================================================
                _buildBestDayCard(context),

                const SizedBox(height: 12),

                // =================================================
                // GOAL
                // =================================================
                _buildGoalCard(context),

                const SizedBox(height: 12),

                // =================================================
                // DAY TYPES
                // =================================================
                _buildDayTypeSummary(context),

                const SizedBox(height: 12),

                // =================================================
                // AARTI
                // =================================================
                _buildAartiSummary(context),

                const SizedBox(height: 12),

                // =================================================
                // NOTES / IMPORTANT
                // =================================================
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        icon: Icons.star,
                        title: 'Important',
                        value: '$_importantDaysCount',
                        subtitle: 'starred days',
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _buildStatCard(
                        context,
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Notes',
                        value: '$_notesCount',
                        subtitle: 'days with notes',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // =================================================
                // IMPORTANT DAYS
                // =================================================
                _buildImportantDays(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
