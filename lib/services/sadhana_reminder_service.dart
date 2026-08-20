import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/sadhana_reminder.dart';

class SadhanaReminderService {
  SadhanaReminderService._();

  static final SadhanaReminderService instance = SadhanaReminderService._();

  static const String _storageKey = 'sadhana_reminders_v1';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    final timezoneInfo = await FlutterTimezone.getLocalTimezone();

    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final settings = const InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _notifications.initialize(settings: settings);

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    await initialize();

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<List<SadhanaReminder>> getReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_storageKey) ?? <String>[];

    final reminders = <SadhanaReminder>[];

    for (final value in values) {
      try {
        reminders.add(SadhanaReminder.fromJson(value));
      } catch (_) {
        // Ignore a corrupted individual reminder instead of breaking
        // the entire reminder screen.
      }
    }

    reminders.sort((a, b) {
      final aMinutes = a.hour * 60 + a.minute;
      final bMinutes = b.hour * 60 + b.minute;
      return aMinutes.compareTo(bMinutes);
    });

    return reminders;
  }

  Future<void> saveReminder(SadhanaReminder reminder) async {
    final reminders = await getReminders();

    final index = reminders.indexWhere((item) => item.id == reminder.id);

    if (index == -1) {
      reminders.add(reminder);
    } else {
      reminders[index] = reminder;
    }

    await _saveReminders(reminders);
    await rescheduleAll();
  }

  Future<void> deleteReminder(int id) async {
    final reminders = await getReminders()
      ..removeWhere((item) => item.id == id);

    await _saveReminders(reminders);
    await rescheduleAll();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    final reminders = await getReminders();

    final index = reminders.indexWhere((item) => item.id == id);

    if (index == -1) return;

    reminders[index] = reminders[index].copyWith(enabled: enabled);

    await _saveReminders(reminders);
    await rescheduleAll();
  }

  Future<void> rescheduleAll() async {
    await initialize();

    await _notifications.cancelAll();

    final reminders = await getReminders();

    for (final reminder in reminders) {
      if (!reminder.enabled || reminder.weekdays.isEmpty) continue;

      for (final weekday in reminder.weekdays) {
        final notificationId = _notificationId(reminder.id, weekday);

        final scheduledDate = _nextInstance(
          weekday: weekday,
          hour: reminder.hour,
          minute: reminder.minute,
        );

        // Fallback to default message if custom message is empty or null
        final notificationBody =
            (reminder.customMessage != null &&
                reminder.customMessage!.trim().isNotEmpty)
            ? reminder.customMessage!.trim()
            : 'Time for your Sadhana 🙏';

        await _notifications.zonedSchedule(
          id: notificationId,
          title: '${reminder.icon} ${reminder.title}',
          body: notificationBody,
          scheduledDate: scheduledDate,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'sadhana_reminders',
              'Sadhana Reminders',
              channelDescription: 'Reminders for your daily Sadhana',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: reminder.id.toString(),
        );
      }
    }
  }

  int _notificationId(int reminderId, int weekday) {
    return (reminderId % 100000000) * 10 + weekday;
  }

  tz.TZDateTime _nextInstance({
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  Future<void> _saveReminders(List<SadhanaReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _storageKey,
      reminders.map((item) => item.toJson()).toList(),
    );
  }

  int createId(Iterable<SadhanaReminder> reminders) {
    final used = reminders.map((item) => item.id).toSet();

    var id = DateTime.now().millisecondsSinceEpoch % 100000000;

    while (used.contains(id)) {
      id = (id + 1) % 100000000;
    }

    return id;
  }
}
