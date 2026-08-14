import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/aarti_type_model.dart';
import '../../models/daily_aarti_model.dart';
import '../../models/daily_sadhana_model.dart';
import '../../models/goal_model.dart';
import '../../models/sadhana_type_model.dart';
import '../../repositories/sadhana_repository.dart';

class StatisticsScreen extends StatefulWidget {
  final int userId;

  const StatisticsScreen({super.key, required this.userId});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final SadhanaRepository _repository = SadhanaRepository();

  List<SadhanaTypeModel> _sadhanaTypes = [];
  List<AartiTypeModel> _aartiTypes = [];

  List<DailySadhanaModel> _sadhanaRecords = [];
  List<DailyAartiModel> _aartiRecords = [];

  GoalModel? _goal;

  int? _selectedSadhanaTypeId;

  int _selectedDays = 30;

  bool _isLoading = true;
  String? _error;

  DateTime get _today {
    final now = DateTime.now();

    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _startDate {
    return _today.subtract(Duration(days: _selectedDays - 1));
  }

  SadhanaTypeModel? get _selectedType {
    if (_selectedSadhanaTypeId == null) {
      return null;
    }

    for (final type in _sadhanaTypes) {
      if (type.id == _selectedSadhanaTypeId) {
        return type;
      }
    }

    return null;
  }

  bool get _isAarti {
    return _selectedType?.name.toLowerCase() == 'aarti';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final types = await _repository.getSadhanaTypes();

      final activeTypes = types
          .where((type) => type.isActive && type.id != null)
          .toList();

      if (activeTypes.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _sadhanaTypes = [];
          _isLoading = false;
        });

        return;
      }

      int? selectedId = _selectedSadhanaTypeId;

      final selectedStillExists = activeTypes.any(
        (type) => type.id == selectedId,
      );

      if (!selectedStillExists) {
        selectedId = activeTypes.first.id;
      }

      final aartiTypes = await _repository.getAartiTypes(widget.userId);

      final allSadhana = await _repository.getAllSadhana(
        widget.userId,
        selectedId!,
      );

      final allAarti = await _repository.getAllAartiAttendance(widget.userId);

      final goal = await _repository.getGoal(widget.userId, selectedId);

      if (!mounted) {
        return;
      }

      setState(() {
        _sadhanaTypes = activeTypes;
        _aartiTypes = aartiTypes;

        _selectedSadhanaTypeId = selectedId;

        _sadhanaRecords = allSadhana;
        _aartiRecords = allAarti;

        _goal = goal;

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Unable to load statistics.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _changeSadhana(int? id) async {
    if (id == null || id == _selectedSadhanaTypeId) {
      return;
    }

    setState(() {
      _selectedSadhanaTypeId = id;
      _isLoading = true;
      _error = null;
    });

    try {
      final records = await _repository.getAllSadhana(widget.userId, id);

      final goal = await _repository.getGoal(widget.userId, id);

      if (!mounted) {
        return;
      }

      setState(() {
        _sadhanaRecords = records;
        _goal = goal;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Unable to load this Sadhana.';
        _isLoading = false;
      });
    }
  }

  String _dateKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);

    return DateFormat('yyyy-MM-dd').format(d);
  }

  DateTime _parseDate(String date) {
    final parsed = DateTime.tryParse(date);

    if (parsed == null) {
      return DateTime(2000);
    }

    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  Map<String, double> get _dailyValues {
    final Map<String, double> values = {};

    if (_isAarti) {
      final selectedAartiIds = _aartiTypes.map((e) => e.id).toSet();

      for (final record in _aartiRecords) {
        if (!selectedAartiIds.contains(record.aartiTypeId)) {
          continue;
        }

        final date = _parseDate(record.date);

        if (date.isBefore(_startDate) || date.isAfter(_today)) {
          continue;
        }

        final key = _dateKey(date);

        values[key] = (values[key] ?? 0) + 1;
      }

      return values;
    }

    for (final record in _sadhanaRecords) {
      final date = _parseDate(record.date);

      if (date.isBefore(_startDate) || date.isAfter(_today)) {
        continue;
      }

      final key = _dateKey(date);

      values[key] = (values[key] ?? 0) + record.value;
    }

    return values;
  }

  List<double> get _periodValues {
    final values = _dailyValues;

    return List.generate(_selectedDays, (index) {
      final date = _startDate.add(Duration(days: index));

      return values[_dateKey(date)] ?? 0;
    });
  }

  double get _total {
    return _periodValues.fold(0, (sum, value) => sum + value);
  }

  int get _activeDays {
    return _periodValues.where((value) => value > 0).length;
  }

  double get _average {
    if (_selectedDays == 0) {
      return 0;
    }

    return _total / _selectedDays;
  }

  double get _bestDay {
    if (_periodValues.isEmpty) {
      return 0;
    }

    return _periodValues.reduce(math.max);
  }

  int get _goalDays {
    if (_goal == null || _goal!.targetValue <= 0) {
      return 0;
    }

    return _periodValues.where((value) => value >= _goal!.targetValue).length;
  }

  double get _goalCompletionPercentage {
    if (_selectedDays == 0 || _goal == null || _goal!.targetValue <= 0) {
      return 0;
    }

    return (_goalDays / _selectedDays) * 100;
  }

  int get _currentStreak {
    final values = _dailyValues;

    int streak = 0;

    DateTime date = _today;

    while (true) {
      final value = values[_dateKey(date)] ?? 0;

      if (value <= 0) {
        break;
      }

      streak++;

      if (date.isAtSameMomentAs(_startDate) || date.isBefore(_startDate)) {
        break;
      }

      date = date.subtract(const Duration(days: 1));
    }

    return streak;
  }

  int get _longestStreak {
    final values = _dailyValues;

    int longest = 0;
    int current = 0;

    for (int i = 0; i < _selectedDays; i++) {
      final date = _startDate.add(Duration(days: i));

      final value = values[_dateKey(date)] ?? 0;

      if (value > 0) {
        current++;
        longest = math.max(longest, current);
      } else {
        current = 0;
      }
    }

    return longest;
  }

  String get _unit {
    if (_isAarti) {
      return 'aartis';
    }

    if (_goal?.unit != null && _goal!.unit!.isNotEmpty) {
      return _goal!.unit!;
    }

    final record = _sadhanaRecords
        .where((record) => record.unit != null && record.unit!.isNotEmpty)
        .toList();

    if (record.isNotEmpty) {
      return record.first.unit!;
    }

    final name = _selectedType?.name.toLowerCase() ?? '';

    switch (name) {
      case 'chanting':
        return 'rounds';

      case 'reading':
        return 'pages';

      case 'hearing':
        return 'minutes';

      default:
        return 'units';
    }
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }

  String _formatDateShort(DateTime date) {
    return DateFormat('d MMM').format(date);
  }

  Color _heatColor(BuildContext context, double value) {
    final theme = Theme.of(context);

    if (value <= 0) {
      return theme.colorScheme.surfaceContainerHighest;
    }

    double ratio;

    if (_goal != null && _goal!.targetValue > 0) {
      ratio = value / _goal!.targetValue;
    } else {
      final best = _bestDay;

      ratio = best <= 0 ? 0 : value / best;
    }

    ratio = ratio.clamp(0.0, 1.0);

    return Color.lerp(
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.primary,
          ratio,
        ) ??
        theme.colorScheme.primary;
  }

  String _periodLabel() {
    switch (_selectedDays) {
      case 7:
        return 'Last 7 Days';

      case 30:
        return 'Last 30 Days';

      case 90:
        return 'Last 90 Days';

      case 365:
        return 'Last Year';

      default:
        return 'Last $_selectedDays Days';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Statistics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _sadhanaTypes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _sadhanaTypes.isEmpty) {
      return _buildError();
    }

    if (_sadhanaTypes.isEmpty) {
      return _buildEmptySadhanaTypes();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildSadhanaSelector(),

          const SizedBox(height: 12),

          _buildPeriodSelector(),

          const SizedBox(height: 20),

          if (_error != null) _buildErrorBanner(),

          if (_isAarti)
            ..._buildAartiStatistics()
          else
            ..._buildSadhanaStatistics(),
        ],
      ),
    );
  }

  Widget _buildSadhanaSelector() {
    final type = _selectedType;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DropdownButtonFormField<int>(
          initialValue: _selectedSadhanaTypeId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Sadhana',
            prefixIcon: type?.icon != null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      type!.icon!,
                      style: const TextStyle(fontSize: 22),
                    ),
                  )
                : const Icon(Icons.self_improvement),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          items: _sadhanaTypes.where((type) => type.id != null).map((type) {
            return DropdownMenuItem<int>(
              value: type.id,
              child: Row(
                children: [
                  Text(type.icon ?? '🙏', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Text(type.name),
                ],
              ),
            );
          }).toList(),
          onChanged: _changeSadhana,
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 7, label: Text('7 Days')),
              ButtonSegment<int>(value: 30, label: Text('30 Days')),
              ButtonSegment<int>(value: 90, label: Text('90 Days')),
              ButtonSegment<int>(value: 365, label: Text('1 Year')),
            ],
            selected: {_selectedDays},
            onSelectionChanged: (values) {
              if (values.isEmpty) {
                return;
              }

              setState(() {
                _selectedDays = values.first;
              });
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSadhanaStatistics() {
    return [
      _buildSummaryHeader(),

      const SizedBox(height: 12),

      _buildStatsGrid(),

      const SizedBox(height: 20),

      _buildProgressChart(),

      const SizedBox(height: 20),

      _buildGoalCard(),

      const SizedBox(height: 20),

      _buildConsistencyCard(),

      const SizedBox(height: 20),

      _buildHeatmapCard(),
    ];
  }

  List<Widget> _buildAartiStatistics() {
    return [
      _buildSummaryHeader(),

      const SizedBox(height: 12),

      _buildStatsGrid(),

      const SizedBox(height: 20),

      _buildProgressChart(),

      const SizedBox(height: 20),

      _buildConsistencyCard(),

      const SizedBox(height: 20),

      _buildAartiBreakdown(),

      const SizedBox(height: 20),

      _buildHeatmapCard(),
    ];
  }

  Widget _buildSummaryHeader() {
    final type = _selectedType;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Text(type?.icon ?? '🙏', style: const TextStyle(fontSize: 38)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type?.name ?? 'Sadhana',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _periodLabel(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final cardWidth = width >= 600 ? (width - 12) / 2 : (width - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                icon: Icons.functions,
                title: 'Total',
                value: _formatNumber(_total),
                subtitle: _unit,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                icon: Icons.show_chart,
                title: 'Average',
                value: _formatNumber(_average),
                subtitle: 'per day',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                icon: Icons.emoji_events_outlined,
                title: 'Best Day',
                value: _formatNumber(_bestDay),
                subtitle: _unit,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                icon: Icons.calendar_month,
                title: 'Active Days',
                value: '$_activeDays',
                subtitle: 'of $_selectedDays',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(title, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressChart() {
    final values = _periodValues;

    if (values.every((value) => value <= 0)) {
      return _buildNoDataCard(
        icon: Icons.show_chart,
        title: 'No progress data',
        message:
            'Start recording your ${_selectedType?.name.toLowerCase() ?? 'Sadhana'} to see your graph here.',
      );
    }

    double maximum = values.isEmpty ? 1 : values.reduce(math.max);

    if (_goal != null && _goal!.targetValue > maximum) {
      maximum = _goal!.targetValue;
    }

    maximum = math.max(maximum, 1);

    maximum *= 1.2;

    final spots = <FlSpot>[];

    for (int i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Progress',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _unit,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(1, values.length - 1).toDouble(),
                  minY: 0,
                  maxY: maximum,
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots
                            .map((spot) {
                              final index = spot.x.round();

                              if (index < 0 || index >= values.length) {
                                return null;
                              }

                              final date = _startDate.add(
                                Duration(days: index),
                              );

                              return LineTooltipItem(
                                '${_formatDateShort(date)}\n'
                                '${_formatNumber(spot.y)} $_unit',
                                TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            })
                            .whereType<LineTooltipItem>()
                            .toList();
                      },
                    ),
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
                        getTitlesWidget: (value, meta) {
                          return Text(
                            _formatNumber(value),
                            style: Theme.of(context).textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: _bottomTitleInterval(),
                        getTitlesWidget: (value, meta) {
                          final index = value.round();

                          if (index < 0 || index >= values.length) {
                            return const SizedBox.shrink();
                          }

                          final date = _startDate.add(Duration(days: index));

                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _chartDateLabel(date),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: _goal == null || _goal!.targetValue <= 0
                      ? const ExtraLinesData()
                      : ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: _goal!.targetValue,
                              strokeWidth: 1.5,
                              dashArray: [6, 4],
                              color: Theme.of(context).colorScheme.secondary,
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                                labelResolver: (_) =>
                                    'Goal ${_formatNumber(_goal!.targetValue)}',
                              ),
                            ),
                          ],
                        ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      isStrokeJoinRound: true,
                      color: Theme.of(context).colorScheme.primary,
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.10),
                      ),
                      dotData: FlDotData(show: _selectedDays <= 30),
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

  double _bottomTitleInterval() {
    if (_selectedDays <= 7) {
      return 1;
    }

    if (_selectedDays <= 30) {
      return 5;
    }

    if (_selectedDays <= 90) {
      return 15;
    }

    return 60;
  }

  String _chartDateLabel(DateTime date) {
    if (_selectedDays <= 30) {
      return DateFormat('d/M').format(date);
    }

    if (date.day == 1) {
      return DateFormat('MMM').format(date);
    }

    return '';
  }

  Widget _buildGoalCard() {
    if (_goal == null || _goal!.targetValue <= 0) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                Icons.flag_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('No daily goal is configured for this Sadhana.'),
              ),
            ],
          ),
        ),
      );
    }

    final percentage = _goalCompletionPercentage.clamp(0, 100);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Goal Achievement',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_goalDays days completed'),
                Text(
                  'Goal: ${_formatNumber(_goal!.targetValue)} '
                  '${_goal!.unit ?? ''}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsistencyCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consistency',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildConsistencyItem(
                    Icons.local_fire_department,
                    'Current streak',
                    '$_currentStreak days',
                  ),
                ),
                Expanded(
                  child: _buildConsistencyItem(
                    Icons.emoji_events,
                    'Longest streak',
                    '$_longestStreak days',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildConsistencyItem(
                    Icons.calendar_today,
                    'Active days',
                    '$_activeDays / $_selectedDays',
                  ),
                ),
                Expanded(
                  child: _buildConsistencyItem(
                    Icons.percent,
                    'Consistency',
                    '${((_activeDays / _selectedDays) * 100).toStringAsFixed(0)}%',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsistencyItem(IconData icon, String title, String value) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
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
              const SizedBox(height: 2),
              Text(
                title,
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

  Widget _buildHeatmapCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Consistency',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Darker means more progress.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _buildHeatmap(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 6),
                ...List.generate(5, (index) {
                  return Container(
                    width: 15,
                    height: 15,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                      color: _heatColor(context, _bestDay * (index + 1) / 5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
                const SizedBox(width: 6),
                Text('More', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmap() {
    final values = _dailyValues;

    final firstDay = _startDate;

    final weekdayOffset = firstDay.weekday - 1;

    final totalCells = weekdayOffset + _selectedDays;

    final weeks = (totalCells / 7).ceil();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SizedBox(width: 30),
              Text('Mon'),
              SizedBox(width: 26),
              Text('Wed'),
              SizedBox(width: 26),
              Text('Fri'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Column(
                  children: List.generate(7, (index) {
                    final names = ['M', '', 'W', '', 'F', '', 'S'];

                    return SizedBox(
                      height: 20,
                      child: Text(
                        names[index],
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  }),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(weeks, (weekIndex) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Column(
                      children: List.generate(7, (dayIndex) {
                        final index = weekIndex * 7 + dayIndex - weekdayOffset;

                        if (index < 0 || index >= _selectedDays) {
                          return const SizedBox(width: 18, height: 18);
                        }

                        final date = _startDate.add(Duration(days: index));

                        final value = values[_dateKey(date)] ?? 0;

                        return Tooltip(
                          message:
                              '${DateFormat('EEE, d MMM').format(date)}\n'
                              '${_formatNumber(value)} $_unit',
                          child: Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: _heatColor(context, value),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAartiBreakdown() {
    if (_aartiTypes.isEmpty) {
      return _buildNoDataCard(
        icon: Icons.event_available,
        title: 'No Aarti types',
        message: 'No active Aarti types are configured yet.',
      );
    }

    final counts = <int, int>{};

    for (final type in _aartiTypes) {
      if (type.id != null) {
        counts[type.id!] = 0;
      }
    }

    for (final record in _aartiRecords) {
      final date = _parseDate(record.date);

      if (date.isBefore(_startDate) || date.isAfter(_today)) {
        continue;
      }

      if (counts.containsKey(record.aartiTypeId)) {
        counts[record.aartiTypeId] = (counts[record.aartiTypeId] ?? 0) + 1;
      }
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aarti Breakdown',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ..._aartiTypes.map((type) {
              final count = counts[type.id] ?? 0;

              final percentage = _selectedDays == 0
                  ? 0.0
                  : (count / _selectedDays).clamp(0.0, 1.0);

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('🪔', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            type.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '$count',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: percentage,
                        minHeight: 7,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 52),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySadhanaTypes() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.self_improvement, size: 56),
            const SizedBox(height: 16),
            const Text(
              'No Sadhana types found.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add an active Sadhana type to start viewing statistics.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
