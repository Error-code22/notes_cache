import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'study_models.dart';

/// Local-first storage for Notesy study sets.
///
/// One JSON file per account keeps decks private on a shared device and means
/// flashcards still work with no connection. Nothing here is uploaded.
class StudyStore {
  static Future<File> _fileFor(String userId) async {
    final dir = await getApplicationSupportDirectory();
    final safeUser = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(dir.path, 'notesy', 'study_$safeUser.json'));
  }

  static Future<List<StudyDeck>> load(String userId) async {
    try {
      final file = await _fileFor(userId);
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      final rows = decoded is Map ? decoded['decks'] : decoded;
      if (rows is! List) return [];
      return rows
          .whereType<Map>()
          .map((e) => StudyDeck.fromJson(Map<String, dynamic>.from(e)))
          .where((d) => d.cards.isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('StudyStore.load error: $e');
      return [];
    }
  }

  static Future<void> _write(String userId, List<StudyDeck> decks) async {
    final file = await _fileFor(userId);
    await file.parent.create(recursive: true);
    final payload = jsonEncode({
      'version': 1,
      'decks': decks.map((d) => d.toJson()).toList(),
    });
    await file.writeAsString(payload, flush: true);
  }

  static Future<void> upsert(String userId, StudyDeck deck) async {
    final decks = await load(userId);
    final index = decks.indexWhere((d) => d.id == deck.id);
    if (index >= 0) {
      decks[index] = deck;
    } else {
      decks.add(deck);
    }
    decks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _write(userId, decks);
  }

  static Future<void> delete(String userId, String deckId) async {
    final decks = await load(userId);
    decks.removeWhere((d) => d.id == deckId);
    await _write(userId, decks);
  }

  static Future<void> clear(String userId) async {
    final file = await _fileFor(userId);
    if (await file.exists()) await file.delete();
  }
}
