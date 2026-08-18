import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_utils.dart';
import '../../models/daily_aarti_model.dart';
import '../../models/daily_sadhana_model.dart';
import '../../models/day_note_model.dart';
import '../../models/goal_model.dart';
import '../../models/sadhana_type_model.dart';
import '../../repositories/sadhana_repository.dart';

class DayInsightsScreen extends StatefulWidget {
  const DayInsightsScreen({super.key});

  @override
  State<DayInsightsScreen> createState() => _DayInsightsScreenState();
}

class _DayInsightsScreenState extends State<DayInsightsScreen> {
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
  // DATE / PAGE
  // ============================================================

  DateTime _selectedDate = DateTime.now();

  static const int _initialPage = 10000;

  late final PageController _pageController;

  // ============================================================
  // SADHANA TYPES
  // ============================================================

  List<SadhanaTypeModel> _sadhanaTypes = [];

  // ============================================================
  // DATA
  // ============================================================

  List<DailySadhanaModel> _sadhanaRecords = [];

  List<DailyAartiModel> _aartiRecords = [];

  List<dynamic> _aartiTypes = [];

  DayNoteModel? _dayNote;

  final Map<int, GoalModel?> _goals = {};

  // ============================================================
  // LOADING
  // ============================================================

  bool _isLoading = true;

  bool _isChangingDate = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: _initialPage);

    _loadInitialData();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
  // LOAD INITIAL DATA
  // ============================================================

  Future<void> _loadInitialData() async {
    try {
      final user = await _repository.getUser();

      if (user == null || user.id == null) {
        return;
      }

      final types = await _repository.getSadhanaTypes();

      if (!mounted) {
        return;
      }

      setState(() {
        _userId = user.id;
        _name = user.name;
        _sadhanaTypes = types;
      });

      await _loadDayData(_selectedDate);
    } catch (e, stackTrace) {
      debugPrint('Error loading day insights: $e');
      debugPrint('$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // FUTURE DATE CHECK
  // ============================================================

  bool _isFutureDate(DateTime date) {
    final today = DateTime.now();

    final normalizedToday = DateTime(today.year, today.month, today.day);

    final normalizedDate = DateTime(date.year, date.month, date.day);

    return normalizedDate.isAfter(normalizedToday);
  }

  // ============================================================
  // LOAD DAY DATA
  // ============================================================

  Future<void> _loadDayData(DateTime date, {bool showLoader = true}) async {
    if (_userId == null) {
      return;
    }

    if (showLoader && mounted) {
      setState(() {
        _isChangingDate = true;
      });
    }

    try {
      final key = _dateKey(date);

      final monthStart = AppDateUtils.monthStart(date);
      final monthEnd = AppDateUtils.monthEnd(date);

      // ----------------------------------------------------------
      // LOAD ALL SADHANA RECORDS FOR MONTH
      // ----------------------------------------------------------

      final allSadhanaRecords = await _repository.getSadhanaForMonth(
        _userId!,
        monthStart,
        monthEnd,
      );

      // ----------------------------------------------------------
      // FILTER SELECTED DAY
      // ----------------------------------------------------------

      final daySadhanaRecords = allSadhanaRecords.where((record) {
        return _normalizeDate(record.date) == key;
      }).toList();

      // ----------------------------------------------------------
      // LOAD AARTI
      // ----------------------------------------------------------

      final allAartiRecords = await _repository.getAartiAttendanceForMonth(
        _userId!,
        monthStart,
        monthEnd,
      );

      final dayAartiRecords = allAartiRecords.where((record) {
        return _normalizeDate(record.date) == key;
      }).toList();

      // ----------------------------------------------------------
      // LOAD NOTE
      // ----------------------------------------------------------

      final notes = await _repository.getDayNotesForMonth(
        _userId!,
        monthStart,
        monthEnd,
      );

      DayNoteModel? dayNote;

      for (final note in notes) {
        if (_normalizeDate(note.date) == key) {
          dayNote = note;
          break;
        }
      }

      // ----------------------------------------------------------
      // LOAD AARTI TYPES
      // ----------------------------------------------------------

      final aartiTypes = await _repository.getAartiTypes(_userId!);

      // ----------------------------------------------------------
      // LOAD GOALS
      // ----------------------------------------------------------

      final goals = <int, GoalModel?>{};

      for (final type in _sadhanaTypes) {
        if (type.id == null) {
          continue;
        }

        try {
          goals[type.id!] = await _repository.getGoal(_userId!, type.id!);
        } catch (e) {
          debugPrint('Could not load goal for ${type.name}: $e');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDate = date;

        _sadhanaRecords = daySadhanaRecords;

        _aartiRecords = dayAartiRecords;

        _dayNote = dayNote;

        _aartiTypes = aartiTypes;

        _goals
          ..clear()
          ..addAll(goals);
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading day data: $e');
      debugPrint('$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _isChangingDate = false;
        });
      }
    }
  }

  // ============================================================
  // CHANGE DAY
  // ============================================================

  Future<void> _changeDay(DateTime date) async {
    await _loadDayData(date);
  }

  // ============================================================
  // PAGE CHANGED
  // ============================================================

  Future<void> _onPageChanged(int page) async {
    final difference = page - _initialPage;

    final today = DateTime.now();

    final todayDate = DateTime(today.year, today.month, today.day);

    final date = todayDate.add(Duration(days: difference));

    // ----------------------------------------------------------
    // DO NOT ALLOW FUTURE DATES
    // ----------------------------------------------------------

    if (_isFutureDate(date)) {
      // Move back to today's page.
      if (mounted) {
        await _pageController.animateToPage(
          _initialPage,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }

      return;
    }

    await _changeDay(date);
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

  Future<void> _pickDate() async {
    final today = DateTime.now();

    final normalizedToday = DateTime(today.year, today.month, today.day);

    final selected = await showDatePicker(
      context: context,
      initialDate: _isFutureDate(_selectedDate)
          ? normalizedToday
          : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: normalizedToday,
      helpText: 'Select a day',
    );

    if (selected == null) {
      return;
    }

    // Extra safety check.
    if (_isFutureDate(selected)) {
      return;
    }

    final difference = selected.difference(normalizedToday).inDays;

    final targetPage = _initialPage + difference;

    if (!_pageController.hasClients) {
      await _changeDay(selected);
      return;
    }

    await _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ============================================================
  // TODAY
  // ============================================================

  bool get _isToday {
    final now = DateTime.now();

    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  // ============================================================
  // FIND SADHANA TYPE
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
  // FIND RECORD
  // ============================================================

  DailySadhanaModel? _findRecord(int? typeId) {
    if (typeId == null) {
      return null;
    }

    try {
      return _sadhanaRecords.firstWhere(
        (record) => record.sadhanaTypeId == typeId,
      );
    } catch (_) {
      return null;
    }
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
  // DEFAULT UNIT
  // ============================================================

  String _getDefaultUnit(SadhanaTypeModel type) {
    switch (type.name.toLowerCase()) {
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
  // DISPLAY UNIT
  // ============================================================

  String _getDisplayUnit(SadhanaTypeModel type, DailySadhanaModel? record) {
    if (record?.unit != null && record!.unit!.trim().isNotEmpty) {
      return record.unit!;
    }

    return _getDefaultUnit(type);
  }

  // ============================================================
  // GET AARTI NAME
  // ============================================================

  String _getAartiName(int? aartiTypeId) {
    if (aartiTypeId == null) {
      return 'Aarti';
    }

    for (final type in _aartiTypes) {
      try {
        if (type.id == aartiTypeId) {
          return type.name.toString();
        }
      } catch (_) {}
    }

    return 'Aarti';
  }

  // ============================================================
  // TOTAL AARTI
  // ============================================================

  int get _aartiCount {
    return _aartiRecords.length;
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
              'Day Insights',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_name.isNotEmpty)
              Text('Hare Krishna, $_name 🙏', style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Select date',
            onPressed: _isChangingDate ? null : _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),

      body: Column(
        children: [
          // ======================================================
          // DATE HEADER
          // ======================================================
          _buildDateHeader(context),

          // ======================================================
          // SWIPE AREA
          // ======================================================
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _initialPage + 1,
              itemBuilder: (context, index) {
                return RefreshIndicator(
                  onRefresh: () =>
                      _loadDayData(_selectedDate, showLoader: false),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: _buildDayContent(context),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DATE HEADER
  // ============================================================

  Widget _buildDateHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          // Previous
          IconButton(
            tooltip: 'Previous day',
            onPressed: _isChangingDate
                ? null
                : () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    );
                  },
            icon: const Icon(Icons.chevron_left),
          ),

          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      DateFormat('EEEE').format(_selectedDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      DateFormat('d MMMM yyyy').format(_selectedDate),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    if (_isToday)
                      Text(
                        'Today',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Next
          IconButton(
            tooltip: _isToday ? 'Already at today' : 'Next day',
            onPressed: (_isChangingDate || _isToday)
                ? null
                : () {
                    final nextDate = _selectedDate.add(const Duration(days: 1));

                    if (_isFutureDate(nextDate)) {
                      return;
                    }

                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    );
                  },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DAY CONTENT
  // ============================================================

  Widget _buildDayContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ========================================================
        // DAY TYPE
        // ========================================================
        _buildDayTypeCard(context),

        const SizedBox(height: 12),

        // ========================================================
        // SADHANA
        // ========================================================
        _buildSadhanaSection(context),

        const SizedBox(height: 12),

        // ========================================================
        // AARTI
        // ========================================================
        _buildAartiCard(context),

        const SizedBox(height: 12),

        // ========================================================
        // NOTE
        // ========================================================
        _buildNoteCard(context),
      ],
    );
  }

  // ============================================================
  // DAY TYPE CARD
  // ============================================================

  Widget _buildDayTypeCard(BuildContext context) {
    final theme = Theme.of(context);

    final note = _dayNote;

    final isImportant = note?.isStarred ?? false;
    final isSankirtan = note?.isSankirtan ?? false;
    final isEkadashi = note?.isEkadashi ?? false;
    final isFestival = note?.isFestival ?? false;

    final hasAny = isImportant || isSankirtan || isEkadashi || isFestival;

    if (!hasAny) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.label_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No day type marked',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.label_outline, color: theme.colorScheme.primary),

            const SizedBox(width: 10),

            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (isSankirtan)
                      _buildDayTypeBadge(
                        context,
                        icon: Icons.groups_2,
                        label: 'Sankirtan',
                      ),

                    if (isEkadashi)
                      _buildDayTypeBadge(
                        context,
                        icon: Icons.brightness_2,
                        label: 'Ekadashi',
                      ),

                    if (isFestival)
                      _buildDayTypeBadge(
                        context,
                        icon: Icons.celebration,
                        label: 'Festival',
                      ),

                    if (isImportant)
                      _buildDayTypeBadge(
                        context,
                        icon: Icons.star,
                        label: 'Important',
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

  // ============================================================
  // DAY TYPE BADGE
  // ============================================================

  Widget _buildDayTypeBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SADHANA SECTION
  // ============================================================

  Widget _buildSadhanaSection(BuildContext context) {
    if (_sadhanaTypes.isEmpty) {
      return const SizedBox();
    }

    final normalTypes = _sadhanaTypes.where(
      (type) => type.name.toLowerCase() != 'aarti',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          context,
          icon: Icons.auto_awesome_outlined,
          title: 'Sadhana',
        ),

        const SizedBox(height: 8),

        ...normalTypes.map(
          (type) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildSadhanaCard(context, type),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SADHANA CARD
  // ============================================================

  Widget _buildSadhanaCard(BuildContext context, SadhanaTypeModel type) {
    final theme = Theme.of(context);

    final record = _findRecord(type.id);

    final value = record?.value ?? 0;

    final unit = _getDisplayUnit(type, record);

    final goal = type.id == null ? null : _goals[type.id!];

    final hasGoal = goal != null && goal!.targetValue > 0;

    bool unitMatches = true;

    if (record != null && goal?.unit != null && record.unit != null) {
      unitMatches = record.unit == goal!.unit;
    }

    final applicableGoal = hasGoal && unitMatches;

    double progress = 0;

    if (applicableGoal) {
      progress = (value / goal!.targetValue).clamp(0.0, 1.0);
    }

    final completed = applicableGoal && value >= goal!.targetValue;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // ----------------------------------------------------
            // TOP
            // ----------------------------------------------------
            Row(
              children: [
                Text(type.icon ?? '🙏', style: const TextStyle(fontSize: 26)),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        unit,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  _formatValue(value),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: value > 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            // ----------------------------------------------------
            // GOAL
            // ----------------------------------------------------
            if (applicableGoal) ...[
              const SizedBox(height: 12),

              Row(
                children: [
                  Text(
                    'Goal',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    '${_formatValue(goal!.targetValue)} '
                    '${goal.unit ?? unit}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: completed ? theme.colorScheme.primary : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),

              if (completed) ...[
                const SizedBox(height: 7),

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
                      'Daily goal completed 🎉',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ],

            // ----------------------------------------------------
            // UNIT MISMATCH
            // ----------------------------------------------------
            if (hasGoal && !unitMatches) ...[
              const SizedBox(height: 8),

              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),

                  const SizedBox(width: 6),

                  Expanded(
                    child: Text(
                      'Goal uses ${goal!.unit ?? 'another unit'}, '
                      'but this entry uses $unit.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
  // AARTI CARD
  // ============================================================

  Widget _buildAartiCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Text('🪔', style: TextStyle(fontSize: 26)),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aarti',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        '$_aartiCount attended',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  '$_aartiCount',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _aartiCount > 0 ? theme.colorScheme.primary : null,
                  ),
                ),
              ],
            ),

            if (_aartiRecords.isNotEmpty) ...[
              const SizedBox(height: 10),

              const Divider(height: 1),

              const SizedBox(height: 8),

              ..._aartiRecords.map((attendance) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: Text(
                          _getAartiName(attendance.aartiTypeId),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const Icon(Icons.check, size: 18),
                    ],
                  ),
                );
              }),
            ] else ...[
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No Aarti attended',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // NOTE CARD
  // ============================================================

  Widget _buildNoteCard(BuildContext context) {
    final theme = Theme.of(context);

    final note = _dayNote;

    final text = note?.note?.trim();

    if (text == null || text.isEmpty) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: ListTile(
          leading: Icon(
            Icons.sticky_note_2_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: const Text('No note for this day'),
          subtitle: const Text('Nothing was added to remember.'),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  color: theme.colorScheme.primary,
                ),

                const SizedBox(width: 8),

                Text(
                  'Day Note',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (note?.isStarred == true) ...[
                  const SizedBox(width: 8),

                  const Icon(Icons.star, size: 18, color: Colors.amber),
                ],
              ],
            ),

            const SizedBox(height: 10),

            Text(text, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),

        const SizedBox(width: 7),

        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
