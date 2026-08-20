enum LearningStatus { notLearned, learning, needRevision, memorized }

extension LearningStatusExtension on LearningStatus {
  String get value {
    switch (this) {
      case LearningStatus.notLearned:
        return 'not_learned';

      case LearningStatus.learning:
        return 'learning';

      case LearningStatus.needRevision:
        return 'need_revision';

      case LearningStatus.memorized:
        return 'memorized';
    }
  }

  String get label {
    switch (this) {
      case LearningStatus.notLearned:
        return 'Not Learned';

      case LearningStatus.learning:
        return 'Learning';

      case LearningStatus.needRevision:
        return 'Need Revision';

      case LearningStatus.memorized:
        return 'Memorized';
    }
  }

  String get icon {
    switch (this) {
      case LearningStatus.notLearned:
        return '⭕';

      case LearningStatus.learning:
        return '📖';

      case LearningStatus.needRevision:
        return '🔄';

      case LearningStatus.memorized:
        return '✅';
    }
  }

  static LearningStatus fromValue(String? value) {
    switch (value) {
      case 'learning':
        return LearningStatus.learning;

      case 'need_revision':
        return LearningStatus.needRevision;

      case 'memorized':
        return LearningStatus.memorized;

      case 'not_learned':
      default:
        return LearningStatus.notLearned;
    }
  }
}

class LearningShloka {
  final int? id;
  final int userId;
  final int bookId;
  final String reference;
  final String shloka;
  final String? translation;
  final String? url;
  final LearningStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const LearningShloka({
    this.id,
    required this.userId,
    required this.bookId,
    required this.reference,
    required this.shloka,
    this.translation,
    this.url,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory LearningShloka.fromMap(Map<String, dynamic> map) {
    return LearningShloka(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      bookId: map['book_id'] as int,
      reference: map['reference'] as String,
      shloka: map['shloka'] as String,
      translation: map['translation'] as String?,
      url: map['url'] as String?,
      status: LearningStatusExtension.fromValue(map['status'] as String?),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'book_id': bookId,
      'reference': reference,
      'shloka': shloka,
      'translation': translation,
      'url': url,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  LearningShloka copyWith({
    int? id,
    int? userId,
    int? bookId,
    String? reference,
    String? shloka,
    String? translation,
    String? url,
    LearningStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LearningShloka(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      bookId: bookId ?? this.bookId,
      reference: reference ?? this.reference,
      shloka: shloka ?? this.shloka,
      translation: translation ?? this.translation,
      url: url ?? this.url,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
