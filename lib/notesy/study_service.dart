import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services.dart';
import 'study_models.dart';

/// Turns a note or topic into a structured study set.
///
/// The dedicated edge action keeps chat out of the generation path and gives
/// us validated JSON. If the action is unavailable (for example an older
/// deployment), the same request falls back to a normal Notesy turn so the
/// feature still works while the backend catches up.
class StudyService {
  Future<StudyPack> generate({
    required String title,
    required String source,
    int cardCount = 8,
    int quizCount = 5,
  }) async {
    final text = source.trim();
    if (text.length < 20) {
      throw const StudyException(
        'This source is too short to make a useful study set.',
      );
    }

    final session = Supabase.instance.client.auth.currentSession;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'notesy',
        headers: {
          if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'action': 'study_pack',
          'title': title.trim(),
          'content': text.length > 12000 ? text.substring(0, 12000) : text,
          'cardCount': cardCount,
          'quizCount': quizCount,
        },
      ).timeout(const Duration(seconds: 90));

      final pack = _parsePack(response.data, fallbackTitle: title);
      if (pack != null) return pack;
      throw const StudyException(
        'Notesy returned an unreadable study set. Try again.',
      );
    } catch (e) {
      debugPrint('StudyService.generate error: $e');
      if (e is StudyException) rethrow;

      // Older deployments do not know the study_pack action. A normal chat
      // turn still gives us a usable pack, and the prompt asks for JSON only.
      try {
        return await _generateThroughChat(
          title: title,
          source: text,
          cardCount: cardCount,
          quizCount: quizCount,
        );
      } catch (fallbackError) {
        debugPrint('StudyService chat fallback error: $fallbackError');
        throw const StudyException(
          'Could not build this study set. Check your connection and try again.',
        );
      }
    }
  }

  Future<StudyPack> _generateThroughChat({
    required String title,
    required String source,
    required int cardCount,
    required int quizCount,
  }) async {
    final prompt = '''Make a study set from the material below.
Return ONLY valid JSON, with no markdown and no commentary:
{
  "title": "short title",
  "cards": [{"front": "prompt", "back": "answer"}],
  "quiz": [{"question": "question", "options": ["a", "b", "c", "d"], "answer": 0, "explanation": "why"}]
}
Create $cardCount cards and $quizCount quiz questions. Base every item on the material.

Title: $title
<source>
${source.length > 9000 ? source.substring(0, 9000) : source}
</source>''';

    final raw = await AiChatService().getResponse(prompt, const []);
    final pack = _parsePack(raw, fallbackTitle: title);
    if (pack == null) {
      throw const StudyException('Notesy returned an unreadable study set.');
    }
    return pack;
  }

  StudyPack? _parsePack(dynamic raw, {required String fallbackTitle}) {
    dynamic data = raw;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    if (map['error'] != null && map['error'].toString().trim().isNotEmpty) {
      throw StudyException(map['error'].toString());
    }

    final cardRows = map['cards'];
    if (cardRows is! List) return null;

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final cards = <StudyCard>[];
    for (var i = 0; i < cardRows.length && cards.length < 20; i++) {
      final row = cardRows[i];
      if (row is! Map) continue;
      final front = row['front']?.toString().trim() ?? '';
      final back = row['back']?.toString().trim() ?? '';
      if (front.isEmpty || back.isEmpty) continue;
      cards.add(StudyCard(
        id: '$stamp-card-$i',
        front: front,
        back: back,
      ));
    }
    if (cards.isEmpty) return null;

    final quizRows = map['quiz'];
    final quiz = <StudyQuestion>[];
    if (quizRows is List) {
      for (var i = 0; i < quizRows.length && quiz.length < 10; i++) {
        final row = quizRows[i];
        if (row is! Map) continue;
        final question = row['question']?.toString().trim() ?? '';
        final rawOptions = row['options'];
        if (question.isEmpty || rawOptions is! List) continue;
        final options = rawOptions
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
        if (options.length != 4) continue;
        final answer = (row['answer'] as num?)?.toInt() ?? 0;
        quiz.add(StudyQuestion(
          question: question,
          options: options,
          answerIndex: answer.clamp(0, 3),
          explanation: row['explanation']?.toString().trim() ?? '',
        ));
      }
    }

    final aiTitle = map['title']?.toString().trim() ?? '';
    return StudyPack(
      title: aiTitle.isEmpty ? fallbackTitle : aiTitle,
      cards: cards,
      quiz: quiz,
    );
  }
}

class StudyException implements Exception {
  final String message;

  const StudyException(this.message);

  @override
  String toString() => message;
}
