import 'dart:math';

/// How well a student remembered a flashcard.
enum StudyRating { again, hard, good, easy }

/// One flashcard plus the small amount of scheduling state needed to make
/// repeated review useful without a server.
class StudyCard {
  final String id;
  final String front;
  final String back;
  int repetitions;
  int intervalDays;
  double ease;
  DateTime dueAt;
  DateTime? lastReviewedAt;

  StudyCard({
    required this.id,
    required this.front,
    required this.back,
    this.repetitions = 0,
    this.intervalDays = 0,
    this.ease = 2.5,
    DateTime? dueAt,
    this.lastReviewedAt,
  }) : dueAt = dueAt ?? DateTime.now();

  bool get isDue => !dueAt.isAfter(DateTime.now());

  /// A deliberately simple SM-2 style update. The goal is a calm daily queue,
  /// not a perfect memory model: "again" brings the card back in ten minutes,
  /// while the other ratings push it out by days.
  void review(StudyRating rating) {
    final now = DateTime.now();
    lastReviewedAt = now;

    switch (rating) {
      case StudyRating.again:
        repetitions = 0;
        intervalDays = 0;
        ease = max(1.3, ease - 0.2);
        dueAt = now.add(const Duration(minutes: 10));
        break;
      case StudyRating.hard:
        repetitions += 1;
        intervalDays = max(1, (intervalDays * 1.2).round());
        ease = max(1.3, ease - 0.15);
        dueAt = now.add(Duration(days: intervalDays));
        break;
      case StudyRating.good:
        repetitions += 1;
        if (repetitions == 1) {
          intervalDays = 1;
        } else if (repetitions == 2) {
          intervalDays = 3;
        } else {
          intervalDays = max(1, (intervalDays * ease).round());
        }
        dueAt = now.add(Duration(days: intervalDays));
        break;
      case StudyRating.easy:
        repetitions += 1;
        if (repetitions == 1) {
          intervalDays = 2;
        } else if (repetitions == 2) {
          intervalDays = 5;
        } else {
          intervalDays = max(1, (intervalDays * ease * 1.3).round());
        }
        ease += 0.15;
        dueAt = now.add(Duration(days: intervalDays));
        break;
    }
  }

  factory StudyCard.fromJson(Map<String, dynamic> json) {
    return StudyCard(
      id: json['id']?.toString() ?? _newId(),
      front: json['front']?.toString() ?? '',
      back: json['back']?.toString() ?? '',
      repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
      intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 0,
      ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
      dueAt: DateTime.tryParse(json['dueAt']?.toString() ?? ''),
      lastReviewedAt: DateTime.tryParse(json['lastReviewedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        'repetitions': repetitions,
        'intervalDays': intervalDays,
        'ease': ease,
        'dueAt': dueAt.toIso8601String(),
        if (lastReviewedAt != null)
          'lastReviewedAt': lastReviewedAt!.toIso8601String(),
      };
}

/// One multiple-choice question. Options are always four entries in decks
/// created by Notesy, but the model tolerates older/invalid rows defensively.
class StudyQuestion {
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;

  const StudyQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
    this.explanation = '',
  });

  String get answer => options.isEmpty
      ? ''
      : options[answerIndex.clamp(0, options.length - 1)];

  factory StudyQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = rawOptions is List
        ? rawOptions
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    final answer = (json['answer'] as num?)?.toInt() ?? 0;
    return StudyQuestion(
      question: json['question']?.toString() ?? '',
      options: options,
      answerIndex: options.isEmpty ? 0 : answer.clamp(0, options.length - 1),
      explanation: json['explanation']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'answer': answerIndex,
        'explanation': explanation,
      };
}

/// A locally saved study set: flashcards, an optional quiz, and progress.
class StudyDeck {
  final String id;
  final String title;
  final String sourceLabel;
  final String sourceKind;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<StudyCard> cards;
  final List<StudyQuestion> quiz;
  int quizBestScore;

  StudyDeck({
    required this.id,
    required this.title,
    required this.sourceLabel,
    required this.sourceKind,
    required this.createdAt,
    required this.updatedAt,
    required this.cards,
    required this.quiz,
    this.quizBestScore = 0,
  });

  int get dueCount => cards.where((c) => c.isDue).length;

  int get reviewedCount => cards.where((c) => c.repetitions > 0).length;

  factory StudyDeck.fromJson(Map<String, dynamic> json) {
    final cardRows = json['cards'];
    final quizRows = json['quiz'];
    return StudyDeck(
      id: json['id']?.toString() ?? _newId(),
      title: json['title']?.toString() ?? 'Study set',
      sourceLabel: json['sourceLabel']?.toString() ?? '',
      sourceKind: json['sourceKind']?.toString() ?? 'topic',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      cards: cardRows is List
          ? cardRows
              .whereType<Map>()
              .map((e) => StudyCard.fromJson(Map<String, dynamic>.from(e)))
              .where((c) => c.front.isNotEmpty && c.back.isNotEmpty)
              .toList()
          : <StudyCard>[],
      quiz: quizRows is List
          ? quizRows
              .whereType<Map>()
              .map((e) => StudyQuestion.fromJson(Map<String, dynamic>.from(e)))
              .where((q) => q.question.isNotEmpty && q.options.length == 4)
              .toList()
          : <StudyQuestion>[],
      quizBestScore: (json['quizBestScore'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceLabel': sourceLabel,
        'sourceKind': sourceKind,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
        'quiz': quiz.map((q) => q.toJson()).toList(),
        'quizBestScore': quizBestScore,
      };
}

/// Raw result from the edge function, before it is saved as a [StudyDeck].
class StudyPack {
  final String title;
  final List<StudyCard> cards;
  final List<StudyQuestion> quiz;

  const StudyPack({
    required this.title,
    required this.cards,
    required this.quiz,
  });
}

String _newId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return '$now-${Random().nextInt(999999)}';
}
