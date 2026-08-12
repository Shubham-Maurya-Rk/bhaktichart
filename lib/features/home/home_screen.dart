import 'package:bhaktichart/core/utils/date_utils.dart';
import 'package:bhaktichart/features/goals/goals_screen.dart';
import 'package:bhaktichart/models/aarti_type_model.dart';
import 'package:bhaktichart/models/daily_aarti_model.dart';
import 'package:bhaktichart/models/daily_sadhana_model.dart';
import 'package:bhaktichart/models/day_note_model.dart';
import 'package:bhaktichart/models/goal_model.dart';
import 'package:bhaktichart/models/sadhana_type_model.dart';
import 'package:bhaktichart/repositories/sadhana_repository.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

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
    _loadHomeData();
  }

  // ============================================================
  // LOAD HOME DATA
  // ============================================================

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

      SadhanaTypeModel? defaultType;

      if (types.isNotEmpty) {
        try {
          defaultType = types.firstWhere(
            (type) => type.name.toLowerCase() == 'chanting',
          );
        } catch (_) {
          defaultType = types.first;
        }
      }

      setState(() {
        _userId = user.id;
        _name = user.name;
        _sadhanaTypes = types;

        _goals.clear();
        _goals.addAll(loadedGoals);

        _selectedSadhanaTypeId = defaultType?.id;
        _currentGoal = defaultType?.id == null
            ? null
            : loadedGoals[defaultType!.id!];
      });

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

      final records = await _repository.getSadhanaForMonth(
        _userId!,
        startDate,
        endDate,
      );

      final aartiRecords = await _repository.getAartiAttendanceForMonth(
        _userId!,
        startDate,
        endDate,
      );

      // ----------------------------------------------------------
      // AARTI COUNT
      // ----------------------------------------------------------

      final Map<String, int> aartiData = {};

      for (final record in aartiRecords) {
        aartiData[record.date] = (aartiData[record.date] ?? 0) + 1;
      }

      // ----------------------------------------------------------
      // SELECTED SADHANA VALUES
      // ----------------------------------------------------------

      final Map<String, double> data = {};

      for (final record in records) {
        if (record.sadhanaTypeId == _selectedSadhanaTypeId) {
          data[record.date] = record.value;
        }
      }

      // ----------------------------------------------------------
      // CURRENT GOAL
      // ----------------------------------------------------------

      final goal = await _repository.getGoal(_userId!, _selectedSadhanaTypeId!);

      if (!mounted) {
        return;
      }

      setState(() {
        _monthlySadhanaByDate = {
          for (final item in records)
            '${item.date}_${item.sadhanaTypeId}': item,
        };

        _monthlySadhana = data;

        _monthlyAarti = aartiData;

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
  // SADHANA ICON
  // ============================================================

  String _getSadhanaIcon() {
    return _selectedSadhana?.icon ?? '🙏';
  }

  // ============================================================
  // DEFAULT UNIT
  // ============================================================

  String _getDefaultUnit() {
    final name = _selectedSadhana?.name.toLowerCase();

    switch (name) {
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

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedSadhanaTypeId = type.id;
      _monthlySadhana = {};
      _monthlySadhanaByDate = {};
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

  Future<void> _showDaySadhanaSheet(DateTime day) async {
    if (_userId == null) {
      return;
    }

    final type = _selectedSadhana;

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

    // ----------------------------------------------------------
    // READING UNIT
    // ----------------------------------------------------------

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

    // ----------------------------------------------------------
    // CONTROLLERS
    // ----------------------------------------------------------

    final controller = TextEditingController(
      text: existing != null && existing.value > 0
          ? _formatValue(existing.value)
          : '',
    );

    final noteController = TextEditingController(
      text: existingNote?.note ?? '',
    );

    bool isStarred = existingNote?.isStarred ?? false;

    if (!mounted) {
      return;
    }

    // ----------------------------------------------------------
    // OPEN SHEET
    // ----------------------------------------------------------

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);

            final isReading = type.name.toLowerCase() == 'reading';

            final unit = isReading ? selectedReadingUnit : _getDefaultUnit();

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
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(day),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          type.icon ?? '🙏',
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ------------------------------------------------
                    // READING UNIT
                    // ------------------------------------------------
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

                    // ------------------------------------------------
                    // VALUE
                    // ------------------------------------------------
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

                    // ------------------------------------------------
                    // STAR
                    // ------------------------------------------------
                    Card(
                      child: SwitchListTile(
                        value: isStarred,
                        onChanged: (value) {
                          setSheetState(() {
                            isStarred = value;
                          });
                        },
                        secondary: Icon(
                          isStarred ? Icons.star : Icons.star_border,
                          color: isStarred ? Colors.amber : null,
                        ),
                        title: const Text(
                          'Important day',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Star this day so you remember it',
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ------------------------------------------------
                    // NOTE
                    // ------------------------------------------------
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

                    // ------------------------------------------------
                    // SAVE
                    // ------------------------------------------------
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
                            note: noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                            createdAt: now,
                            updatedAt: now,
                          );

                          await _repository.saveDayNote(note);

                          if (!context.mounted) {
                            return;
                          }

                          // IMPORTANT:
                          // Close the sheet first.
                          // Do not reload while TextFields are
                          // still inside the active sheet.
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

    // Reload only AFTER the bottom sheet is completely closed.
    if (mounted) {
      await _loadMonthlyData();
    }

    // IMPORTANT:
    // Do NOT manually dispose these controllers here.
    //
    // They are owned by this temporary modal flow.
    // Manual disposal here can race with Flutter's route/widget
    // teardown, especially when nested dialogs/sheets are involved.
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

    bool isStarred = existingNote?.isStarred ?? false;

    final noteController = TextEditingController(
      text: existingNote?.note ?? '',
    );

    if (!mounted) {
      return;
    }

    // ----------------------------------------------------------
    // OPEN SHEET
    // ----------------------------------------------------------

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(day),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🪔', style: TextStyle(fontSize: 30)),
                        SizedBox(width: 8),
                        Text(
                          'Aarti Attendance',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ------------------------------------------------
                    // AARTI LIST
                    // ------------------------------------------------
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
                          margin: const EdgeInsets.only(bottom: 8),
                          child: CheckboxListTile(
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
                              style: TextStyle(fontSize: 24),
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 8),

                    // ------------------------------------------------
                    // ADD AARTI
                    // ------------------------------------------------
                    OutlinedButton.icon(
                      onPressed: () async {
                        final added = await _showAddAartiDialog();

                        if (added != true) {
                          return;
                        }

                        if (!context.mounted) {
                          return;
                        }

                        // Close current sheet.
                        Navigator.pop(context);

                        // Open fresh sheet after the current
                        // sheet is completely closed.
                        Future.microtask(() {
                          if (mounted) {
                            _showAartiSheet(day);
                          }
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('ADD MY AARTI'),
                    ),

                    const SizedBox(height: 12),

                    // ------------------------------------------------
                    // STAR
                    // ------------------------------------------------
                    Card(
                      child: SwitchListTile(
                        value: isStarred,
                        onChanged: (value) {
                          setSheetState(() {
                            isStarred = value;
                          });
                        },
                        secondary: Icon(
                          isStarred ? Icons.star : Icons.star_border,
                          color: isStarred ? Colors.amber : null,
                        ),
                        title: const Text(
                          'Important day',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Star this day'),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ------------------------------------------------
                    // NOTE
                    // ------------------------------------------------
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Note about this day',
                        hintText: 'Write something to remember...',
                        prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ------------------------------------------------
                    // SAVE
                    // ------------------------------------------------
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final now = DateTime.now().toIso8601String();

                          // Save / remove attendance.
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

                          final note = DayNoteModel(
                            userId: _userId!,
                            date: _dateKey(day),
                            isStarred: isStarred,
                            note: noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                            createdAt: now,
                            updatedAt: now,
                          );

                          await _repository.saveDayNote(note);

                          if (!context.mounted) {
                            return;
                          }

                          // Close first.
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

    // Reload only after the sheet is closed.
    if (mounted) {
      await _loadMonthlyData();
    }

    // IMPORTANT:
    // No noteController.dispose() here.
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

    // Deliberately not disposing here.
    //
    // This controller belongs to the temporary dialog
    // and disposing it manually can race with Flutter's
    // dialog teardown when asynchronous callbacks are involved.

    return result;
  }

  // ============================================================
  // STREAK
  // ============================================================

  int _calculateCurrentStreak() {
    if (_monthlySadhana.isEmpty) {
      return 0;
    }

    DateTime date = DateTime.now();

    int streak = 0;

    while (true) {
      final value = _getValueForDay(date);

      if (value <= 0) {
        break;
      }

      streak++;

      date = date.subtract(const Duration(days: 1));

      if (streak > 3650) {
        break;
      }
    }

    return streak;
  }

  // ============================================================
  // STREAK CARD
  // ============================================================

  Widget _buildStreakCard(BuildContext context) {
    final theme = Theme.of(context);

    final streak = _calculateCurrentStreak();

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
                    Text('Showing', style: theme.textTheme.bodySmall),

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

    final bool reachedGoal = progress != null && progress >= 1.0;

    final valueTextColor = reachedGoal
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

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
          Positioned(
            top: 5,
            right: 6,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday || isSelected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),

          Center(
            child: hasValue
                ? Text(
                    _formatValue(value),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: valueTextColor,
                    ),
                  )
                : null,
          ),
        ],
      ),
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
  // TODAY BUTTON
  // ============================================================

  Widget _buildTodayButton(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton.icon(
      onPressed: () {
        final today = DateTime.now();

        setState(() {
          _selectedDay = today;
          _focusedDay = today;
        });

        _showDaySadhanaSheet(today);
      },
      icon: const Icon(Icons.add),
      label: const Text(
        "UPDATE TODAY'S SADHANA",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: theme.colorScheme.primary,
      ),
    );
  }

  // ============================================================
  // GOAL PROGRESS
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

    // ----------------------------------------------------------
    // READING
    // ----------------------------------------------------------

    if (selected.name.toLowerCase() == 'reading') {
      final dailyUnit = _getUnitForDay(day);

      final goalUnit = goal.unit;

      // Never compare different units.
      //
      // pages vs shlokas
      // pages vs minutes
      // shlokas vs minutes
      //
      // These return null so the calendar does
      // not show an incorrect percentage.

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
              'BhaktiChart',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            if (_name.isNotEmpty)
              Text('Hare Krishna, $_name 🙏', style: theme.textTheme.bodySmall),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Goals',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GoalsScreen()),
              );

              if (!mounted) {
                return;
              }

              await _reloadGoals();
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStreakCard(context),

              const SizedBox(height: 16),

              _buildSadhanaSelector(context),

              const SizedBox(height: 16),

              _buildCalendar(context),

              const SizedBox(height: 16),

              _buildTodayButton(context),
            ],
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
}
