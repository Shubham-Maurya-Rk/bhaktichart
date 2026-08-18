import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_utils.dart';
import '../../models/daily_aarti_model.dart';
import '../../models/daily_routine.dart';
import '../../models/daily_routine_goal.dart';
import '../../models/daily_sadhana_model.dart';
import '../../models/day_note_model.dart';
import '../../models/goal_model.dart';
import '../../models/sadhana_type_model.dart';
import '../../repositories/daily_routine_repository.dart';
import '../../repositories/sadhana_repository.dart';

class DayInsightsScreen extends StatefulWidget {
  const DayInsightsScreen({super.key});

  @override
  State<DayInsightsScreen> createState() => _DayInsightsScreenState();
}

class _DayInsightsScreenState extends State<DayInsightsScreen> {
  // ============================================================
  // REPOSITORIES
  // ============================================================

  final SadhanaRepository _repository = SadhanaRepository();
  final DailyRoutineRepository _routineRepository = DailyRoutineRepository();

  // ============================================================
  // USER
  // ============================================================

  int? _userId;
  String _name = '';

  // ============================================================
  // DATE
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
  // DAILY ROUTINE
  // ============================================================

  DailyRoutine? _dailyRoutine;

  DailyRoutineGoal? _routineGoal;

  // ============================================================
  // LOADING
  // ============================================================

  bool _isLoading = true;

  bool _isChangingDate = false;

  // ============================================================
  // EDIT MODE
  // ============================================================

  bool _isEditing = false;

  bool _isSaving = false;

  // ============================================================
  // EDIT CONTROLLERS
  // ============================================================

  final Map<int, TextEditingController> _sadhanaControllers = {};

  final Map<int, String> _sadhanaUnits = {};

  final TextEditingController _noteController = TextEditingController();

  // ============================================================
  // ROUTINE EDIT VALUES
  // ============================================================

  TimeOfDay? _editWakeTime;

  TimeOfDay? _editSleepTime;

  // ============================================================
  // DAY TYPE EDIT VALUES
  // ============================================================

  bool _editIsStarred = false;

  bool _editIsSankirtan = false;

  bool _editIsEkadashi = false;

  bool _editIsFestival = false;

  // ============================================================
  // AARTI EDIT VALUES
  // ============================================================

  final Set<int> _selectedAartiTypeIds = {};

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

    for (final controller in _sadhanaControllers.values) {
      controller.dispose();
    }

    _noteController.dispose();

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

      try {
        _routineGoal = await _routineRepository.getGoal(_userId!);
      } catch (e) {
        debugPrint('Could not load routine goal: $e');
        _routineGoal = null;
      }

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

      // ========================================================
      // SADHANA
      // ========================================================

      final allSadhanaRecords = await _repository.getSadhanaForMonth(
        _userId!,
        monthStart,
        monthEnd,
      );

      final daySadhanaRecords = allSadhanaRecords.where((record) {
        return _normalizeDate(record.date) == key;
      }).toList();

      // ========================================================
      // AARTI
      // ========================================================

      final allAartiRecords = await _repository.getAartiAttendanceForMonth(
        _userId!,
        monthStart,
        monthEnd,
      );

      final dayAartiRecords = allAartiRecords.where((record) {
        return _normalizeDate(record.date) == key;
      }).toList();

      // ========================================================
      // NOTE
      // ========================================================

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

      // ========================================================
      // AARTI TYPES
      // ========================================================

      final aartiTypes = await _repository.getAartiTypes(_userId!);

      // ========================================================
      // GOALS
      // ========================================================

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

      // ========================================================
      // DAILY ROUTINE
      // ========================================================

      DailyRoutine? dailyRoutine;

      try {
        dailyRoutine = await _routineRepository.getByDate(_userId!, date);
      } catch (e) {
        debugPrint('Could not load daily routine: $e');
      }

      // ========================================================
      // ROUTINE GOAL
      // ========================================================

      DailyRoutineGoal? routineGoal = _routineGoal;

      try {
        routineGoal = await _routineRepository.getGoal(_userId!);
      } catch (e) {
        debugPrint('Could not load routine goal: $e');
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

        _dailyRoutine = dailyRoutine;

        _routineGoal = routineGoal;

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
    if (_isEditing) {
      return;
    }

    await _loadDayData(date);
  }

  // ============================================================
  // PAGE CHANGED
  // ============================================================

  Future<void> _onPageChanged(int page) async {
    if (_isEditing) {
      return;
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final date = todayDate.add(Duration(days: page - _initialPage));

    if (_isFutureDate(date)) {
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
    if (_isEditing || _isChangingDate) {
      return;
    }

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

    if (_isFutureDate(selected)) {
      return;
    }

    final targetPage = _pageForDate(selected);

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
  // PAGE FOR DATE
  // ============================================================

  int _pageForDate(DateTime date) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    return _initialPage + dateOnly.difference(todayDate).inDays;
  }

  // ============================================================
  // SYNC PAGE WITH SELECTED DATE
  // ============================================================

  void _syncPageWithSelectedDate({bool animate = false}) {
    if (!_pageController.hasClients) {
      return;
    }

    final targetPage = _pageForDate(_selectedDate);
    final currentPage = _pageController.page?.round();

    if (currentPage == targetPage) {
      return;
    }

    if (animate) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.jumpToPage(targetPage);
    }
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
          if (!_isEditing)
            IconButton(
              tooltip: 'Edit day',
              onPressed: _isChangingDate ? null : _startEditing,
              icon: const Icon(Icons.edit_outlined),
            )
          else
            IconButton(
              tooltip: 'Cancel',
              onPressed: _isSaving ? null : _cancelEditing,
              icon: const Icon(Icons.close),
            ),

          IconButton(
            tooltip: 'Select date',
            onPressed: (_isChangingDate || _isEditing) ? null : _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),

      body: Column(
        children: [
          _buildDateHeader(context),

          Expanded(
            child: _isEditing
                ? _buildEditContent(context)
                : PageView.builder(
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

      // ========================================================
      // SAVE BUTTON
      // ========================================================
      bottomNavigationBar: _isEditing
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAll,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                  ),
                ),
              ),
            )
          : null,
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
          IconButton(
            tooltip: 'Previous day',
            onPressed: (_isChangingDate || _isEditing)
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
              onTap: _isEditing ? null : _pickDate,
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

          IconButton(
            tooltip: _isToday ? 'Already at today' : 'Next day',
            onPressed: (_isChangingDate || _isToday || _isEditing)
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
  // START EDITING
  // ============================================================

  void _startEditing() {
    if (_isSaving) {
      return;
    }

    // ----------------------------------------------------------
    // Clear old controllers
    // ----------------------------------------------------------

    for (final controller in _sadhanaControllers.values) {
      controller.dispose();
    }

    _sadhanaControllers.clear();

    _sadhanaUnits.clear();

    // ----------------------------------------------------------
    // Sadhana
    // ----------------------------------------------------------

    for (final type in _sadhanaTypes) {
      if (type.id == null) {
        continue;
      }

      if (type.name.toLowerCase() == 'aarti') {
        continue;
      }

      final record = _findRecord(type.id);

      final controller = TextEditingController(
        text: record == null ? '' : _formatValue(record.value),
      );

      _sadhanaControllers[type.id!] = controller;

      // --------------------------------------------------------
      // Units
      // --------------------------------------------------------

      final typeName = type.name.toLowerCase();

      if (typeName == 'chanting') {
        _sadhanaUnits[type.id!] = 'rounds';
      } else if (typeName == 'hearing') {
        _sadhanaUnits[type.id!] = 'minutes';
      } else if (typeName == 'reading') {
        final existingUnit = record?.unit?.toLowerCase();

        const allowedUnits = ['pages', 'shloka', 'minutes'];

        _sadhanaUnits[type.id!] = allowedUnits.contains(existingUnit)
            ? existingUnit!
            : 'pages';
      } else {
        _sadhanaUnits[type.id!] = _getDisplayUnit(type, record);
      }
    }

    // ----------------------------------------------------------
    // Routine
    // ----------------------------------------------------------

    final wake = _dailyRoutine?.wakeUpTime;

    final sleep = _dailyRoutine?.sleepTime;

    _editWakeTime = wake == null
        ? null
        : TimeOfDay(hour: wake.hour, minute: wake.minute);

    _editSleepTime = sleep == null
        ? null
        : TimeOfDay(hour: sleep.hour, minute: sleep.minute);

    // ----------------------------------------------------------
    // Note
    // ----------------------------------------------------------

    _noteController.text = _dayNote?.note ?? '';

    _editIsStarred = _dayNote?.isStarred ?? false;

    _editIsSankirtan = _dayNote?.isSankirtan ?? false;

    _editIsEkadashi = _dayNote?.isEkadashi ?? false;

    _editIsFestival = _dayNote?.isFestival ?? false;

    // ----------------------------------------------------------
    // Aarti
    // ----------------------------------------------------------

    _selectedAartiTypeIds.clear();

    for (final attendance in _aartiRecords) {
      _selectedAartiTypeIds.add(attendance.aartiTypeId);
    }

    setState(() {
      _isEditing = true;
    });
  }

  // ============================================================
  // CANCEL EDITING
  // ============================================================

  void _cancelEditing() {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isEditing = false;
    });
  }

  // ============================================================
  // SAVE ALL
  // ============================================================

  Future<void> _saveAll() async {
    if (_userId == null || _isSaving) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();

      final dateOnly = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      final dateKey = _dateKey(dateOnly);

      // ========================================================
      // 1. SAVE DAILY ROUTINE
      // ========================================================

      final existingRoutine = await _routineRepository.getByDate(
        _userId!,
        dateOnly,
      );

      final wakeDateTime = _combineDateAndTime(dateOnly, _editWakeTime);

      final sleepDateTime = _combineDateAndTime(dateOnly, _editSleepTime);

      if (wakeDateTime != null ||
          sleepDateTime != null ||
          existingRoutine != null) {
        final routine = DailyRoutine(
          id: existingRoutine?.id,
          userId: _userId!,
          date: dateOnly,
          wakeUpTime: wakeDateTime,
          sleepTime: sleepDateTime,
          createdAt: existingRoutine?.createdAt ?? now,
          updatedAt: now,
        );

        await _routineRepository.save(routine);
      }

      // ========================================================
      // 2. SAVE SADHANA
      // ========================================================

      for (final type in _sadhanaTypes) {
        final typeId = type.id;

        if (typeId == null) {
          continue;
        }

        if (type.name.toLowerCase() == 'aarti') {
          continue;
        }

        final controller = _sadhanaControllers[typeId];

        if (controller == null) {
          continue;
        }

        final text = controller.text.trim();

        // ------------------------------------------------------
        // Empty value
        // ------------------------------------------------------

        final value = double.tryParse(text) ?? 0;

        // ------------------------------------------------------
        // Unit
        // ------------------------------------------------------

        final typeName = type.name.toLowerCase();

        String unit;

        switch (typeName) {
          case 'chanting':
            // LOCKED
            unit = 'rounds';
            break;

          case 'hearing':
            // LOCKED
            unit = 'minutes';
            break;

          case 'reading':
            // DROPDOWN
            const allowedUnits = ['pages', 'shloka', 'minutes'];

            final selectedUnit = _sadhanaUnits[typeId];

            unit = allowedUnits.contains(selectedUnit)
                ? selectedUnit!
                : 'pages';

            break;

          default:
            unit = _sadhanaUnits[typeId] ?? _getDefaultUnit(type);
        }

        // ------------------------------------------------------
        // Existing record
        // ------------------------------------------------------

        final existing = _findRecord(typeId);

        final sadhana = DailySadhanaModel(
          id: existing?.id,
          userId: _userId!,
          date: dateKey,
          sadhanaTypeId: typeId,
          value: value,
          unit: unit,
          createdAt: existing?.createdAt ?? now.toIso8601String(),
          updatedAt: now.toIso8601String(),
        );

        await _repository.saveSadhana(sadhana);
      }

      // ========================================================
      // 3. SAVE AARTI
      // ========================================================

      final existingAartiIds = _aartiRecords
          .map((item) => item.aartiTypeId)
          .toSet();

      // --------------------------------------------------------
      // Add newly selected Aartis
      // --------------------------------------------------------

      for (final aartiTypeId in _selectedAartiTypeIds) {
        if (!existingAartiIds.contains(aartiTypeId)) {
          final attendance = DailyAartiModel(
            userId: _userId!,
            aartiTypeId: aartiTypeId,
            date: dateKey,
            createdAt: now.toIso8601String(),
          );

          await _repository.saveAartiAttendance(attendance);
        }
      }

      // --------------------------------------------------------
      // Remove unchecked Aartis
      // --------------------------------------------------------

      for (final existingId in existingAartiIds) {
        if (!_selectedAartiTypeIds.contains(existingId)) {
          await _repository.removeAartiAttendance(
            _userId!,
            existingId,
            dateKey,
          );
        }
      }

      // ========================================================
      // 4. SAVE DAY NOTE
      // ========================================================

      final existingNote = _dayNote;

      final note = DayNoteModel(
        id: existingNote?.id,
        userId: _userId!,
        date: dateKey,
        isStarred: _editIsStarred,
        isSankirtan: _editIsSankirtan,
        isEkadashi: _editIsEkadashi,
        isFestival: _editIsFestival,
        note: _noteController.text.trim(),
        createdAt: existingNote?.createdAt ?? now.toIso8601String(),
        updatedAt: now.toIso8601String(),
      );

      await _repository.saveDayNote(note);

      // ========================================================
      // 5. RELOAD EVERYTHING
      // ========================================================

      // Keep the PageController synchronized with the date being edited.
      // When the PageView is temporarily replaced by the edit screen, its
      // visual page position can become out of sync with _selectedDate.
      // Re-syncing here guarantees that the next/previous swipe continues
      // from the correct day after saving.
      final savedDate = _selectedDate;

      await _loadDayData(savedDate, showLoader: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isEditing) {
          return;
        }

        _syncPageWithSelectedDate();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Day details saved successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Error saving day insights: $e');

      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // COMBINE DATE + TIME
  // ============================================================

  DateTime? _combineDateAndTime(DateTime date, TimeOfDay? time) {
    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // ============================================================
  // PICK WAKE TIME
  // ============================================================

  Future<void> _pickWakeTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _editWakeTime ?? const TimeOfDay(hour: 6, minute: 0),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _editWakeTime = selected;
    });
  }

  // ============================================================
  // PICK SLEEP TIME
  // ============================================================

  Future<void> _pickSleepTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _editSleepTime ?? const TimeOfDay(hour: 22, minute: 0),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _editSleepTime = selected;
    });
  }

  // ============================================================
  // CLEAR WAKE TIME
  // ============================================================

  void _clearWakeTime() {
    setState(() {
      _editWakeTime = null;
    });
  }

  // ============================================================
  // CLEAR SLEEP TIME
  // ============================================================

  void _clearSleepTime() {
    setState(() {
      _editSleepTime = null;
    });
  }

  // ============================================================
  // EDIT CONTENT
  // ============================================================

  Widget _buildEditContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEditRoutineSection(context),

          const SizedBox(height: 14),

          _buildEditSadhanaSection(context),

          const SizedBox(height: 14),

          _buildEditAartiSection(context),

          const SizedBox(height: 14),

          _buildEditDayTypeSection(context),

          const SizedBox(height: 14),

          _buildEditNoteSection(context),
        ],
      ),
    );
  }

  // ============================================================
  // EDIT ROUTINE SECTION
  // ============================================================

  Widget _buildEditRoutineSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditSectionHeader(
              context,
              icon: Icons.schedule_rounded,
              title: 'Daily Routine',
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: _buildTimeEditCard(
                    context,
                    title: 'Wake up',
                    icon: Icons.wb_sunny_rounded,
                    iconColor: Colors.orange,
                    time: _editWakeTime,
                    onTap: _pickWakeTime,
                    onClear: _editWakeTime == null ? null : _clearWakeTime,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: _buildTimeEditCard(
                    context,
                    title: 'Sleep',
                    icon: Icons.nightlight_round,
                    iconColor: Colors.indigo,
                    time: _editSleepTime,
                    onTap: _pickSleepTime,
                    onClear: _editSleepTime == null ? null : _clearSleepTime,
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
  // TIME EDIT CARD
  // ============================================================

  Widget _buildTimeEditCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required TimeOfDay? time,
    required VoidCallback onTap,
    required VoidCallback? onClear,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _isSaving ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),

                const SizedBox(width: 7),

                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                if (onClear != null)
                  InkWell(
                    onTap: _isSaving ? null : onClear,
                    child: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            Text(
              time == null ? 'Not set' : _formatTimeOfDay(time),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: time == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Tap to change',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FORMAT TIME OF DAY
  // ============================================================

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;

    final minute = time.minute.toString().padLeft(2, '0');

    final period = time.period == DayPeriod.am ? 'AM' : 'PM';

    return '$hour:$minute $period';
  }

  // ============================================================
  // EDIT SADHANA SECTION
  // ============================================================

  Widget _buildEditSadhanaSection(BuildContext context) {
    final normalTypes = _sadhanaTypes.where(
      (type) => type.name.toLowerCase() != 'aarti',
    );

    if (normalTypes.isEmpty) {
      return const SizedBox();
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditSectionHeader(
              context,
              icon: Icons.auto_awesome_outlined,
              title: 'Sadhana',
            ),

            const SizedBox(height: 14),

            ...normalTypes.map(
              (type) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildEditableSadhanaField(context, type),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EDITABLE SADHANA FIELD
  // ============================================================

  Widget _buildEditableSadhanaField(
    BuildContext context,
    SadhanaTypeModel type,
  ) {
    final theme = Theme.of(context);

    final controller = _sadhanaControllers[type.id!];

    if (controller == null) {
      return const SizedBox();
    }

    final name = type.name.toLowerCase();

    final isChanting = name == 'chanting';

    final isHearing = name == 'hearing';

    final isReading = name == 'reading';

    // ----------------------------------------------------------
    // Fixed units
    // ----------------------------------------------------------

    if (isChanting) {
      _sadhanaUnits[type.id!] = 'rounds';
    }

    if (isHearing) {
      _sadhanaUnits[type.id!] = 'minutes';
    }

    final unit = _sadhanaUnits[type.id!] ?? _getDefaultUnit(type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(type.icon ?? '🙏', style: const TextStyle(fontSize: 24)),

              const SizedBox(width: 9),

              Expanded(
                child: Text(
                  type.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Value',
                    hintText: 'Enter ${type.name.toLowerCase()}',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ==================================================
              // CHANTING
              // ==================================================
              if (isChanting)
                Expanded(child: _buildLockedUnitField(context, unit: 'rounds'))
              // ==================================================
              // HEARING
              // ==================================================
              else if (isHearing)
                Expanded(child: _buildLockedUnitField(context, unit: 'minutes'))
              // ==================================================
              // READING
              // ==================================================
              else if (isReading)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _readingUnitValue(type.id!),
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pages', child: Text('Pages')),
                      DropdownMenuItem(value: 'shloka', child: Text('Shloka')),
                      DropdownMenuItem(
                        value: 'minutes',
                        child: Text('Minutes'),
                      ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _sadhanaUnits[type.id!] = value;
                            });
                          },
                  ),
                )
              // ==================================================
              // OTHER
              // ==================================================
              else
                Expanded(child: _buildLockedUnitField(context, unit: unit)),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // READING UNIT
  // ============================================================

  String _readingUnitValue(int typeId) {
    final value = _sadhanaUnits[typeId];

    const allowed = ['pages', 'shloka', 'minutes'];

    if (value == null || !allowed.contains(value)) {
      return 'pages';
    }

    return value;
  }

  // ============================================================
  // LOCKED UNIT FIELD
  // ============================================================

  Widget _buildLockedUnitField(BuildContext context, {required String unit}) {
    return TextFormField(
      initialValue: unit,
      enabled: false,
      decoration: const InputDecoration(
        labelText: 'Unit',
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.lock_outline),
      ),
    );
  }

  // ============================================================
  // EDIT AARTI SECTION
  // ============================================================

  Widget _buildEditAartiSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditSectionHeader(
              context,
              icon: Icons.local_fire_department_outlined,
              title: 'Aarti',
            ),

            const SizedBox(height: 8),

            Text(
              'Select all Aartis you attended.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 10),

            if (_aartiTypes.isEmpty)
              Text(
                'No Aarti types added yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._aartiTypes.map((type) {
                final int? id = type.id;

                if (id == null) {
                  return const SizedBox();
                }

                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selectedAartiTypeIds.contains(id),
                  title: Text(type.name.toString()),
                  secondary: const Text('🪔', style: TextStyle(fontSize: 22)),
                  onChanged: _isSaving
                      ? null
                      : (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedAartiTypeIds.add(id);
                            } else {
                              _selectedAartiTypeIds.remove(id);
                            }
                          });
                        },
                );
              }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EDIT DAY TYPE SECTION
  // ============================================================

  Widget _buildEditDayTypeSection(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditSectionHeader(
              context,
              icon: Icons.label_outline,
              title: 'Day Type',
            ),

            const SizedBox(height: 8),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Important day'),
              secondary: const Icon(Icons.star_outline),
              value: _editIsStarred,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _editIsStarred = value;
                      });
                    },
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sankirtan'),
              secondary: const Icon(Icons.groups_2_outlined),
              value: _editIsSankirtan,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _editIsSankirtan = value;
                      });
                    },
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ekadashi'),
              secondary: const Icon(Icons.brightness_2_outlined),
              value: _editIsEkadashi,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _editIsEkadashi = value;
                      });
                    },
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Festival'),
              secondary: const Icon(Icons.celebration_outlined),
              value: _editIsFestival,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _editIsFestival = value;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EDIT NOTE SECTION
  // ============================================================

  Widget _buildEditNoteSection(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditSectionHeader(
              context,
              icon: Icons.sticky_note_2_outlined,
              title: 'Day Note',
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _noteController,
              enabled: !_isSaving,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'Write something you want to remember about this day...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'You can leave the note empty.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EDIT SECTION HEADER
  // ============================================================

  Widget _buildEditSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 21, color: theme.colorScheme.primary),

        const SizedBox(width: 8),

        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DAY CONTENT
  // ============================================================

  Widget _buildDayContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDayTypeCard(context),

        const SizedBox(height: 12),

        _buildDailyRoutineCard(context),

        const SizedBox(height: 12),

        _buildSadhanaSection(context),

        const SizedBox(height: 12),

        _buildAartiCard(context),

        const SizedBox(height: 12),

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
  // DAILY ROUTINE CARD
  // ============================================================

  Widget _buildDailyRoutineCard(BuildContext context) {
    final theme = Theme.of(context);

    final routine = _dailyRoutine;

    final wake = routine?.wakeUpTime;

    final sleep = routine?.sleepTime;

    final duration = routine?.sleepDuration;

    final wakeGoal = _routineGoal?.wakeUpTimeText;

    final sleepGoal = _routineGoal?.sleepTimeText;

    final hasRoutineData = wake != null || sleep != null || duration != null;

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
                  Icons.schedule_rounded,
                  size: 21,
                  color: theme.colorScheme.primary,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    'Daily Routine',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (!hasRoutineData)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        'No routine recorded for this day.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildRoutineTimeCard(
                      context,
                      icon: Icons.wb_sunny_rounded,
                      iconColor: Colors.orange,
                      title: 'Wake up',
                      value: wake == null
                          ? '--'
                          : DailyRoutine.formatTime(wake),
                      goal: wakeGoal,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _buildRoutineTimeCard(
                      context,
                      icon: Icons.nightlight_round,
                      iconColor: Colors.indigo,
                      title: 'Sleep',
                      value: sleep == null
                          ? '--'
                          : DailyRoutine.formatTime(sleep),
                      goal: sleepGoal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: theme.colorScheme.primary.withOpacity(0.07),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bedtime_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),

                    const SizedBox(width: 9),

                    Expanded(
                      child: Text(
                        'Sleep duration',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    Text(
                      duration == null
                          ? '--'
                          : _formatRoutineDuration(duration),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
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

  // ============================================================
  // ROUTINE TIME DISPLAY
  // ============================================================

  Widget _buildRoutineTimeCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String? goal,
  }) {
    final theme = Theme.of(context);

    final hasValue = value != '--';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),

              const SizedBox(width: 7),

              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: hasValue
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),

          if (goal != null) ...[
            const SizedBox(height: 3),

            Text(
              'Goal: $goal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // FORMAT ROUTINE DURATION
  // ============================================================

  String _formatRoutineDuration(Duration duration) {
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
