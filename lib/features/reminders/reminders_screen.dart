import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sadhana_reminder.dart';
import '../../models/sadhana_type_model.dart';
import '../../repositories/sadhana_repository.dart';
import '../../services/sadhana_reminder_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final SadhanaRepository _repository = SadhanaRepository();
  final SadhanaReminderService _reminderService =
      SadhanaReminderService.instance;

  List<SadhanaReminder> _reminders = [];
  List<SadhanaTypeModel> _sadhanaTypes = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _reminderService.initialize();
      final reminders = await _reminderService.getReminders();
      final types = await _repository.getSadhanaTypes();

      if (!mounted) return;

      setState(() {
        _reminders = reminders;
        _sadhanaTypes = types;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load reminders: $e')));
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _reminderService.requestPermissions();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification and alarm permissions requested.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Permission request failed: $e')));
    }
  }

  Future<void> _addReminder() async {
    if (_sadhanaTypes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No Sadhana types found.')));
      return;
    }

    await _showReminderEditor();
  }

  Future<void> _editReminder(SadhanaReminder reminder) async {
    await _showReminderEditor(existing: reminder);
  }

  Future<void> _showReminderEditor({SadhanaReminder? existing}) async {
    SadhanaTypeModel selectedType;

    if (existing != null) {
      selectedType = _sadhanaTypes.firstWhere(
        (type) => type.id == existing.sadhanaTypeId,
        orElse: () => _sadhanaTypes.first,
      );
    } else {
      selectedType = _sadhanaTypes.first;
    }

    TimeOfDay selectedTime = existing == null
        ? const TimeOfDay(hour: 6, minute: 0)
        : TimeOfDay(hour: existing.hour, minute: existing.minute);

    final selectedWeekdays = <int>{
      ...(existing?.weekdays ?? <int>[1, 2, 3, 4, 5, 6, 7]),
    };

    final customMessageController = TextEditingController(
      text: existing?.customMessage ?? '',
    );

    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          existing == null
                              ? 'Add Sadhana Reminder'
                              : 'Edit Sadhana Reminder',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),

                        DropdownButtonFormField<int>(
                          value: selectedType.id,
                          decoration: const InputDecoration(
                            labelText: 'Sadhana',
                            prefixIcon: Icon(Icons.self_improvement),
                            border: OutlineInputBorder(),
                          ),
                          items: _sadhanaTypes
                              .where((type) => type.id != null)
                              .map(
                                (type) => DropdownMenuItem<int>(
                                  value: type.id!,
                                  child: Row(
                                    children: [
                                      Text(
                                        type.icon ?? '🙏',
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(type.name),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (id) {
                            if (id == null) return;

                            final type = _sadhanaTypes.firstWhere(
                              (item) => item.id == id,
                            );

                            setSheetState(() {
                              selectedType = type;
                            });
                          },
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: customMessageController,
                          decoration: const InputDecoration(
                            labelText: 'Custom Notification Text',
                            hintText: 'e.g., Time for your daily Sadhana 🙏',
                            prefixIcon: Icon(Icons.message_outlined),
                            border: OutlineInputBorder(),
                            helperText:
                                'Leave empty for default: "Time for your Sadhana 🙏"',
                          ),
                        ),

                        const SizedBox(height: 16),

                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.access_time),
                            title: const Text('Reminder time'),
                            subtitle: Text(
                              selectedTime.format(context),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );

                              if (picked == null) return;

                              setSheetState(() {
                                selectedTime = picked;
                              });
                            },
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          'Repeat on',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              const [
                                _DayChipData(1, 'Mon'),
                                _DayChipData(2, 'Tue'),
                                _DayChipData(3, 'Wed'),
                                _DayChipData(4, 'Thu'),
                                _DayChipData(5, 'Fri'),
                                _DayChipData(6, 'Sat'),
                                _DayChipData(7, 'Sun'),
                              ].map((day) {
                                final selected = selectedWeekdays.contains(
                                  day.day,
                                );

                                return FilterChip(
                                  label: Text(day.label),
                                  selected: selected,
                                  onSelected: (value) {
                                    setSheetState(() {
                                      if (value) {
                                        selectedWeekdays.add(day.day);
                                      } else {
                                        selectedWeekdays.remove(day.day);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () async {
                              if (selectedType.id == null) return;

                              if (selectedWeekdays.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Select at least one day.'),
                                  ),
                                );
                                return;
                              }

                              final reminders = await _reminderService
                                  .getReminders();

                              final customMsg = customMessageController.text
                                  .trim();

                              final reminder = SadhanaReminder(
                                id:
                                    existing?.id ??
                                    _reminderService.createId(reminders),
                                sadhanaTypeId: selectedType.id!,
                                title: selectedType.name,
                                icon: selectedType.icon ?? '🙏',
                                hour: selectedTime.hour,
                                minute: selectedTime.minute,
                                weekdays: selectedWeekdays.toList()..sort(),
                                customMessage: customMsg.isEmpty
                                    ? null
                                    : customMsg,
                                enabled: existing?.enabled ?? true,
                              );

                              await _reminderService.saveReminder(reminder);

                              if (!context.mounted) return;

                              Navigator.pop(sheetContext, true);
                            },
                            icon: const Icon(Icons.notifications_active),
                            label: Text(
                              existing == null
                                  ? 'SAVE REMINDER'
                                  : 'UPDATE REMINDER',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      await _load();
    }
  }

  Future<void> _toggle(SadhanaReminder reminder, bool value) async {
    try {
      await _reminderService.setEnabled(reminder.id, value);
      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update reminder: $e')));
    }
  }

  Future<void> _delete(SadhanaReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete reminder?'),
          content: Text(
            '${reminder.icon} ${reminder.title} reminder will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _reminderService.deleteReminder(reminder.id);
    await _load();
  }

  String _formatDays(List<int> weekdays) {
    const names = <int, String>{
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };

    if (weekdays.length == 7) return 'Every day';

    return weekdays.map((day) => names[day] ?? '').join(' • ');
  }

  String _formatTime(SadhanaReminder reminder) {
    return DateFormat(
      'h:mm a',
    ).format(DateTime(2000, 1, 1, reminder.hour, reminder.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sadhana Reminders',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Notification permissions',
            onPressed: _requestPermissions,
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReminder,
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add Reminder'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
          ? _buildEmptyState(context)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: _reminders.length,
                itemBuilder: (context, index) {
                  final reminder = _reminders[index];
                  final displayMessage =
                      (reminder.customMessage != null &&
                          reminder.customMessage!.trim().isNotEmpty)
                      ? reminder.customMessage!
                      : 'Time for your Sadhana 🙏';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        child: Text(
                          reminder.icon,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      title: Text(
                        reminder.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatTime(reminder)}  •  '
                              '${_formatDays(reminder.weekdays)}',
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '"$displayMessage"',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: Switch(
                        value: reminder.enabled,
                        onChanged: (value) => _toggle(reminder, value),
                      ),
                      onTap: () => _editReminder(reminder),
                      onLongPress: () => _delete(reminder),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔔', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              'No Sadhana reminders yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a reminder for chanting, reading, hearing, Aarti, '
              'or any other Sadhana.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('ALLOW NOTIFICATIONS'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChipData {
  final int day;
  final String label;

  const _DayChipData(this.day, this.label);
}
