import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../onboarding/onboarding_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OnboardingRepository _repository = OnboardingRepository();

  String _name = '';

  DateTime _focusedDay = DateTime.now();

  DateTime? _selectedDay = DateTime.now();

  String _selectedSadhana = 'Chanting';

  final List<Map<String, dynamic>> _sadhanaTypes = [
    {'name': 'Chanting', 'icon': '📿', 'unit': 'rounds'},
    {'name': 'Reading', 'icon': '📖', 'unit': 'minutes'},
    {'name': 'Hearing', 'icon': '🎧', 'unit': 'minutes'},
    {'name': 'Aarti', 'icon': '🪔', 'unit': 'count'},
  ];

  // Temporary data.
  //
  // Later this will come directly from SQLite.
  final Map<String, Map<String, double>> _demoData = {
    '2026-08-01': {'Chanting': 8},
    '2026-08-02': {'Chanting': 12},
    '2026-08-03': {'Chanting': 16},
    '2026-08-04': {'Chanting': 10},
    '2026-08-05': {'Chanting': 20},
    '2026-08-06': {'Chanting': 4},
    '2026-08-07': {'Chanting': 16},
    '2026-08-08': {'Chanting': 12},
    '2026-08-09': {'Chanting': 16},
    '2026-08-10': {'Chanting': 8},
    '2026-08-11': {'Chanting': 20},
  };

  @override
  void initState() {
    super.initState();

    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _repository.getUser();

    if (!mounted) return;

    setState(() {
      _name = user?.name ?? '';
    });
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  double _getValueForDay(DateTime day) {
    final data = _demoData[_dateKey(day)];

    if (data == null) {
      return 0;
    }

    return data[_selectedSadhana] ?? 0;
  }

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  Color _getHeatColor(BuildContext context, double value) {
    final colorScheme = Theme.of(context).colorScheme;

    if (value <= 0) {
      return Colors.transparent;
    }

    if (value < 4) {
      return colorScheme.primary.withValues(alpha: 0.15);
    }

    if (value < 8) {
      return colorScheme.primary.withValues(alpha: 0.30);
    }

    if (value < 12) {
      return colorScheme.primary.withValues(alpha: 0.45);
    }

    if (value < 16) {
      return colorScheme.primary.withValues(alpha: 0.65);
    }

    return colorScheme.primary;
  }

  String _getSadhanaIcon() {
    final result = _sadhanaTypes.firstWhere(
      (item) => item['name'] == _selectedSadhana,
    );

    return result['icon'] as String;
  }

  String _getSadhanaUnit() {
    final result = _sadhanaTypes.firstWhere(
      (item) => item['name'] == _selectedSadhana,
    );

    return result['unit'] as String;
  }

  void _showSadhanaSelector() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
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
                  final name = sadhana['name'] as String;

                  final icon = sadhana['icon'] as String;

                  final selected = name == _selectedSadhana;

                  return ListTile(
                    leading: Text(icon, style: const TextStyle(fontSize: 28)),

                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),

                    trailing: selected
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),

                    selected: selected,

                    onTap: () {
                      setState(() {
                        _selectedSadhana = name;
                      });

                      Navigator.pop(context);
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

  void _showSadhanaEntry(DateTime day) {
    final currentValue = _getValueForDay(day);

    final controller = TextEditingController(
      text: currentValue > 0 ? _formatValue(currentValue) : '',
    );

    final formattedDate = DateFormat('EEEE, d MMMM').format(day);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,

      builder: (context) {
        return Padding(
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
                formattedDate,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                '${_getSadhanaIcon()} $_selectedSadhana',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

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
                  suffixText: _getSadhanaUnit(),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,

                child: FilledButton(
                  onPressed: () {
                    final value = double.tryParse(controller.text.trim());

                    if (value == null || value < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid number'),
                        ),
                      );

                      return;
                    }

                    setState(() {
                      _demoData[_dateKey(day)] ??= {};

                      _demoData[_dateKey(day)]![_selectedSadhana] = value;
                    });

                    Navigator.pop(context);
                  },

                  child: const Text(
                    'SAVE',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            tooltip: 'Settings',
            onPressed: () {},
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

  Widget _buildStreakCard(BuildContext context) {
    final theme = Theme.of(context);

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

            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Streak', style: TextStyle(fontSize: 14)),

                  SizedBox(height: 2),

                  Text(
                    '7 Days',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

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
                      _selectedSadhana,
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

          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;

              _focusedDay = focusedDay;
            });

            _showSadhanaEntry(selectedDay);
          },

          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
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
            isTodayHighlighted: true,
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

  Widget _buildCalendarCell(
    BuildContext context,
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    final theme = Theme.of(context);

    final value = _getValueForDay(day);

    final heatColor = _getHeatColor(context, value);

    final hasValue = value > 0;

    return Container(
      margin: const EdgeInsets.all(2),

      decoration: BoxDecoration(
        color: heatColor,

        borderRadius: BorderRadius.circular(10),

        border: isSelected
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : isToday
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              )
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
                      color: value >= 16
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTodayButton(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton.icon(
      onPressed: () {
        final today = DateTime.now();

        setState(() {
          _selectedDay = today;
          _focusedDay = today;
        });

        _showSadhanaEntry(today);
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
}
