import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'notesy_style.dart';
import 'study_models.dart';
import 'study_store.dart';

class StudyDeckPage extends StatefulWidget {
  const StudyDeckPage({
    super.key,
    required this.deck,
    required this.userId,
  });

  final StudyDeck deck;
  final String userId;

  @override
  State<StudyDeckPage> createState() => _StudyDeckPageState();
}

class _StudyDeckPageState extends State<StudyDeckPage> {
  late StudyDeck _deck;
  late List<StudyCard> _queue;

  int _cardIndex = 0;
  bool _flipped = false;
  bool _cardSessionComplete = false;

  int _quizIndex = 0;
  int? _selectedOption;
  bool _quizAnswered = false;
  int _quizCorrect = 0;
  bool _quizComplete = false;

  @override
  void initState() {
    super.initState();
    _deck = widget.deck;
    _restartCardQueue(onlyDue: true);
  }

  void _restartCardQueue({required bool onlyDue}) {
    final due = _deck.cards.where((card) => card.isDue).toList();
    final source = onlyDue && due.isNotEmpty ? due : _deck.cards;
    _queue = List<StudyCard>.from(source);
    _cardIndex = 0;
    _flipped = false;
    _cardSessionComplete = _queue.isEmpty;
  }

  Future<void> _save() async {
    _deck.updatedAt = DateTime.now();
    await StudyStore.upsert(widget.userId, _deck);
  }

  Future<void> _rate(StudyRating rating) async {
    if (_queue.isEmpty || _cardIndex >= _queue.length || !_flipped) return;
    _queue[_cardIndex].review(rating);
    await _save();
    if (!mounted) return;
    setState(() {
      if (_cardIndex + 1 >= _queue.length) {
        _cardSessionComplete = true;
      } else {
        _cardIndex += 1;
        _flipped = false;
      }
    });
  }

  void _restartCards() {
    setState(() => _restartCardQueue(onlyDue: false));
  }

  void _selectOption(int index) {
    if (_quizAnswered) return;
    final question = _deck.quiz[_quizIndex];
    setState(() {
      _selectedOption = index;
      _quizAnswered = true;
      if (index == question.answerIndex) _quizCorrect += 1;
    });
  }

  Future<void> _nextQuestion() async {
    if (_quizIndex + 1 >= _deck.quiz.length) {
      final previousBest = _deck.quizBestScore;
      if (_quizCorrect > previousBest) {
        _deck.quizBestScore = _quizCorrect;
        await _save();
      }
      if (!mounted) return;
      setState(() => _quizComplete = true);
      return;
    }
    setState(() {
      _quizIndex += 1;
      _selectedOption = null;
      _quizAnswered = false;
    });
  }

  void _restartQuiz() {
    setState(() {
      _quizIndex = 0;
      _selectedOption = null;
      _quizAnswered = false;
      _quizCorrect = 0;
      _quizComplete = false;
    });
  }

  Future<void> _deleteDeck() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete study set?'),
        content: Text('“${_deck.title}” and its progress will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await StudyStore.delete(widget.userId, _deck.id);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _shareDeck() async {
    final buffer = StringBuffer()
      ..writeln(_deck.title)
      ..writeln(_deck.sourceLabel)
      ..writeln();
    for (var i = 0; i < _deck.cards.length; i++) {
      buffer.writeln('${i + 1}. ${_deck.cards[i].front}');
      buffer.writeln('   ${_deck.cards[i].back}');
      buffer.writeln();
    }
    if (_deck.quiz.isNotEmpty) {
      buffer.writeln('QUIZ');
      for (var i = 0; i < _deck.quiz.length; i++) {
        final q = _deck.quiz[i];
        buffer.writeln('${i + 1}. ${q.question}');
        for (var o = 0; o < q.options.length; o++) {
          buffer.writeln('   ${String.fromCharCode(65 + o)}. ${q.options[o]}');
        }
        buffer.writeln('   Answer: ${String.fromCharCode(65 + q.answerIndex)}');
        buffer.writeln();
      }
    }
    try {
      await Share.share(buffer.toString().trim(), subject: _deck.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share this set: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _deck.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (_deck.sourceLabel.isNotEmpty)
                Text(
                  _deck.sourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'share') _shareDeck();
                if (value == 'delete') _deleteDeck();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.ios_share_rounded),
                    title: Text('Share set'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            indicatorColor: kNotesyLuma,
            labelColor: theme.colorScheme.onSurface,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            tabs: [
              Tab(text: 'Flashcards (${_deck.cards.length})'),
              Tab(text: 'Quiz (${_deck.quiz.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFlashcards(theme),
            _buildQuiz(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcards(ThemeData theme) {
    if (_deck.cards.isEmpty) {
      return const Center(child: Text('This set has no cards.'));
    }
    if (_cardSessionComplete) {
      return _buildCardComplete(theme);
    }

    final card = _queue[_cardIndex];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          children: [
            _buildProgressHeader(
              theme,
              current: _cardIndex + 1,
              total: _queue.length,
              label: 'Flashcard',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _flipped = !_flipped),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Container(
                    key: ValueKey('${card.id}-$_flipped'),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _flipped ? theme.cardColor : kNotesyInk,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _flipped
                            ? kNotesyLuma.withValues(alpha: 0.7)
                            : kNotesyLuma.withValues(alpha: 0.28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _flipped ? 'ANSWER' : 'PROMPT',
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w800,
                                  color: _flipped ? kNotesyLuma : Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _flipped ? card.back : card.front,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: _flipped ? 21 : 24,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                  color: _flipped ? theme.colorScheme.onSurface : Colors.white,
                                ),
                              ),
                              if (!_flipped) ...[
                                const SizedBox(height: 26),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.touch_app_outlined, size: 16, color: Colors.white54),
                                    SizedBox(width: 6),
                                    Text(
                                      'Tap to reveal',
                                      style: TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_flipped)
              _buildRatingButtons(theme)
            else
              SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    'Recall the answer, then tap the card.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButtons(ThemeData theme) {
    return Row(
      children: [
        _ratingButton(theme, 'Again', const Color(0xFFEF5350), StudyRating.again),
        const SizedBox(width: 8),
        _ratingButton(theme, 'Hard', const Color(0xFFFFA726), StudyRating.hard),
        const SizedBox(width: 8),
        _ratingButton(theme, 'Good', const Color(0xFF66BB6A), StudyRating.good),
        const SizedBox(width: 8),
        _ratingButton(theme, 'Easy', kNotesyLuma, StudyRating.easy),
      ],
    );
  }

  Widget _ratingButton(
    ThemeData theme,
    String label,
    Color color,
    StudyRating rating,
  ) {
    final darkText = color == kNotesyLuma || color == const Color(0xFF66BB6A);
    return Expanded(
      child: FilledButton(
        onPressed: () => _rate(rating),
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.18),
          foregroundColor: darkText ? theme.colorScheme.onSurface : color,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withValues(alpha: 0.45)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildCardComplete(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: kNotesyLuma.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, size: 46, color: kNotesyInk),
            ),
            const SizedBox(height: 20),
            const Text(
              'Session complete',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'You reviewed ${_queue.length} ${_queue.length == 1 ? 'card' : 'cards'}. Difficult cards will come back sooner.',
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _restartCards,
              style: FilledButton.styleFrom(
                backgroundColor: kNotesyLuma,
                foregroundColor: kNotesyInk,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Review all cards again'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Study Lab'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuiz(ThemeData theme) {
    if (_deck.quiz.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.quiz_outlined, size: 48, color: kNotesyLuma),
              const SizedBox(height: 12),
              const Text(
                'This set has no quiz yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Create another set with quiz questions to test yourself.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
              ),
            ],
          ),
        ),
      );
    }

    if (_quizComplete) return _buildQuizComplete(theme);

    final question = _deck.quiz[_quizIndex];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressHeader(
              theme,
              current: _quizIndex + 1,
              total: _deck.quiz.length,
              label: 'Question',
            ),
            const SizedBox(height: 20),
            Text(
              question.question,
              style: const TextStyle(fontSize: 22, height: 1.35, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < question.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildOption(theme, question, i),
              ),
            if (_quizAnswered) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (_selectedOption == question.answerIndex
                          ? Colors.green
                          : Colors.red)
                      .withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedOption == question.answerIndex
                          ? 'Correct'
                          : 'Not quite',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _selectedOption == question.answerIndex
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                    if (question.explanation.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        question.explanation,
                        style: const TextStyle(height: 1.45, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _nextQuestion,
                  style: FilledButton.styleFrom(
                    backgroundColor: kNotesyLuma,
                    foregroundColor: kNotesyInk,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    _quizIndex + 1 >= _deck.quiz.length ? 'See result' : 'Next question',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOption(ThemeData theme, StudyQuestion question, int index) {
    final isSelected = _selectedOption == index;
    final isCorrect = question.answerIndex == index;
    Color? border;
    Color? fill;

    if (_quizAnswered) {
      if (isCorrect) {
        border = Colors.green;
        fill = Colors.green.withValues(alpha: 0.1);
      } else if (isSelected) {
        border = Colors.red;
        fill = Colors.red.withValues(alpha: 0.08);
      }
    } else if (isSelected) {
      border = kNotesyLuma;
      fill = kNotesyLuma.withValues(alpha: 0.12);
    }

    return InkWell(
      onTap: _quizAnswered ? null : () => _selectOption(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: fill ?? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: border ?? theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: border == null ? 1 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: border?.withValues(alpha: 0.16) ??
                    theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Text(
                String.fromCharCode(65 + index),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                question.options[index],
                style: const TextStyle(height: 1.35),
              ),
            ),
            if (_quizAnswered && isCorrect)
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 21),
            if (_quizAnswered && isSelected && !isCorrect)
              const Icon(Icons.cancel_rounded, color: Colors.red, size: 21),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizComplete(ThemeData theme) {
    final total = _deck.quiz.length;
    final percent = total == 0 ? 0 : ((_quizCorrect / total) * 100).round();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percent%',
              style: const TextStyle(
                fontSize: 58,
                height: 1,
                fontWeight: FontWeight.w900,
                color: kNotesyLuma,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_quizCorrect of $total correct',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _deck.quizBestScore > 0
                  ? 'Best so far: ${_deck.quizBestScore}/$total'
                  : 'Your result is saved on this device.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _restartQuiz,
              style: FilledButton.styleFrom(
                backgroundColor: kNotesyLuma,
                foregroundColor: kNotesyInk,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Try the quiz again'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Study Lab'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader(
    ThemeData theme, {
    required int current,
    required int total,
    required String label,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              '$label $current of $total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (_deck.dueCount > 0)
              Text(
                '${_deck.dueCount} due',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : current / total,
            minHeight: 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: kNotesyLuma,
          ),
        ),
      ],
    );
  }
}
