class DailyRoutineGoal {
  final int? id;
  final int userId;

  /// Example: 05:30
  final int wakeUpHour;
  final int wakeUpMinute;

  /// Example: 22:30
  final int sleepHour;
  final int sleepMinute;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const DailyRoutineGoal({
    this.id,
    required this.userId,
    required this.wakeUpHour,
    required this.wakeUpMinute,
    required this.sleepHour,
    required this.sleepMinute,
    required this.createdAt,
    this.updatedAt,
  });

  String get wakeUpTimeText {
    return _formatTime(wakeUpHour, wakeUpMinute);
  }

  String get sleepTimeText {
    return _formatTime(sleepHour, sleepMinute);
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'wake_up_hour': wakeUpHour,
      'wake_up_minute': wakeUpMinute,
      'sleep_hour': sleepHour,
      'sleep_minute': sleepMinute,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory DailyRoutineGoal.fromMap(Map<String, dynamic> map) {
    return DailyRoutineGoal(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      wakeUpHour: map['wake_up_hour'] as int,
      wakeUpMinute: map['wake_up_minute'] as int,
      sleepHour: map['sleep_hour'] as int,
      sleepMinute: map['sleep_minute'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(map['updated_at'] as String),
    );
  }

  static String _formatTime(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';

    return '$h:$m $period';
  }
}
