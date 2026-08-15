class DailyRoutine {
  final int? id;
  final int userId;
  final DateTime date;

  /// Actual wake-up time.
  final DateTime? wakeUpTime;

  /// Actual sleep time.
  final DateTime? sleepTime;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const DailyRoutine({
    this.id,
    required this.userId,
    required this.date,
    this.wakeUpTime,
    this.sleepTime,
    required this.createdAt,
    this.updatedAt,
  });

  // ============================================================
  // SLEEP DURATION
  // ============================================================

  Duration? get sleepDuration {
    if (sleepTime == null || wakeUpTime == null) {
      return null;
    }

    DateTime sleep = sleepTime!;
    DateTime wake = wakeUpTime!;

    // ----------------------------------------------------------
    // IMPORTANT:
    //
    // Example:
    // Sleep: 13 Aug 2026 11:00 PM
    // Wake : 14 Aug 2026 07:00 AM
    //
    // If your stored dates accidentally have the same date,
    // we treat wake-up as the following day.
    // ----------------------------------------------------------

    if (!wake.isAfter(sleep)) {
      wake = wake.add(const Duration(days: 1));
    }

    final duration = wake.difference(sleep);

    // Ignore obviously invalid values.
    if (duration.isNegative || duration > const Duration(hours: 24)) {
      return null;
    }

    return duration;
  }

  // ============================================================
  // FORMATTED DURATION
  // ============================================================

  String get formattedSleepDuration {
    final duration = sleepDuration;

    if (duration == null) {
      return '--';
    }

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
  // COPY WITH
  // ============================================================

  DailyRoutine copyWith({
    int? id,
    int? userId,
    DateTime? date,
    DateTime? wakeUpTime,
    DateTime? sleepTime,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearWakeUpTime = false,
    bool clearSleepTime = false,
  }) {
    return DailyRoutine(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      wakeUpTime: clearWakeUpTime ? null : (wakeUpTime ?? this.wakeUpTime),
      sleepTime: clearSleepTime ? null : (sleepTime ?? this.sleepTime),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ============================================================
  // MAP
  // ============================================================

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'date': _dateOnly(date),
      'wake_up_time': wakeUpTime?.toIso8601String(),
      'sleep_time': sleepTime?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // ============================================================
  // FROM MAP
  // ============================================================

  factory DailyRoutine.fromMap(Map<String, dynamic> map) {
    return DailyRoutine(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      date: DateTime.parse(map['date'] as String),
      wakeUpTime: map['wake_up_time'] == null
          ? null
          : DateTime.parse(map['wake_up_time'] as String),
      sleepTime: map['sleep_time'] == null
          ? null
          : DateTime.parse(map['sleep_time'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
    );
  }

  // ============================================================
  // DATE HELPERS
  // ============================================================

  static String _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day).toIso8601String();
  }

  static DateTime dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  // ============================================================
  // TIME FORMAT
  // ============================================================

  static String formatTime(DateTime? time) {
    if (time == null) {
      return '--';
    }

    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;

    final minute = time.minute.toString().padLeft(2, '0');

    final period = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }
}
