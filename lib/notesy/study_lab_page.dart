import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services.dart';
import 'notesy_style.dart';
import 'study_deck_page.dart';
import 'study_generator_page.dart';
import 'study_models.dart';
import 'study_store.dart';

/// The saved-study dashboard. Decks are local, so this page is useful even
/// when Notesy itself is offline.
class StudyLabPage extends StatefulWidget {
  const StudyLabPage({super.key});

  @override
  State<StudyLabPage> createState() => _StudyLabPageState();
}

class _StudyLabPageState extends State<StudyLabPage> {
  String _userId = 'guest_user';
  List<StudyDeck> _decks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _userId = context.read<AuthService>().currentUser?.id ?? 'guest_user';
    _load();
  }

  Future<void> _load() async {
    final decks = await StudyStore.load(_userId);
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _loading = false;
    });
  }

  Future<void> _newStudySet() async {
    final deck = await Navigator.push<StudyDeck>(
      context,
      MaterialPageRoute(builder: (_) => const StudyGeneratorPage()),
    );
    if (deck == null || !mounted) return;
    await _load();
    if (mounted) await _openDeck(deck);
  }

  Future<void> _openDeck(StudyDeck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyDeckPage(deck: deck, userId: _userId),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCards = _decks.fold<int>(0, (sum, d) => sum + d.cards.length);
    final dueCards = _decks.fold<int>(0, (sum, d) => sum + d.dueCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notesy Study Lab'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'How Study Lab works',
            onPressed: _showHowItWorks,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newStudySet,
        backgroundColor: kNotesyLuma,
        foregroundColor: kNotesyInk,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New study set',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kNotesyInk,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
          children: [
            _buildHero(theme, totalCards, dueCards),
            const SizedBox(height: 26),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your study sets',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_decks.isNotEmpty)
                  Text(
                    '${_decks.length} saved',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator(color: kNotesyLuma)),
              )
            else if (_decks.isEmpty)
              _buildEmpty(theme)
            else
              ..._decks.map((deck) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DeckCard(
                      deck: deck,
                      onTap: () => _openDeck(deck),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme, int totalCards, int dueCards) {
    return Container(
      decoration: notesyInkPanel(context),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              notesyMark(size: 50),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memory Lab',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Read it once. Remember it for the exam.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _HeroStat(value: '${_decks.length}', label: 'sets'),
              _HeroStat(value: '$totalCards', label: 'cards'),
              _HeroStat(
                value: '$dueCards',
                label: 'due now',
                highlight: dueCards > 0,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _newStudySet,
              style: FilledButton.styleFrom(
                backgroundColor: kNotesyLuma,
                foregroundColor: kNotesyInk,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text(
                'Turn a note into cards',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          const Icon(Icons.style_outlined, size: 42, color: kNotesyLuma),
          const SizedBox(height: 12),
          const Text(
            'No study sets yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a library note or type a topic. Notesy will make the cards and quiz for you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.45,
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _newStudySet,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create the first set'),
          ),
        ],
      ),
    );
  }

  void _showHowItWorks() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How Study Lab works'),
        content: const Text(
          '1. Choose a note or type a topic.\n'
          '2. Notesy builds flashcards and a quiz online.\n'
          '3. The set is saved on this device so you can revise offline.\n\n'
          'Rate each card Again, Hard, Good, or Easy. Cards you find difficult come back sooner.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: highlight ? kNotesyLuma : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.deck, required this.onTap});

  final StudyDeck deck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reviewed = deck.cards.isEmpty
        ? 0.0
        : (deck.reviewedCount / deck.cards.length).clamp(0.0, 1.0);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kNotesyLuma.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.style_outlined, color: kNotesyInk, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deck.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        if (deck.sourceLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            deck.sourceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: reviewed,
                  minHeight: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: kNotesyLuma,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text(
                    '${deck.cards.length} cards',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (deck.quiz.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      '${deck.quiz.length} quiz',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const Spacer(),
                  if (deck.dueCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kNotesyLuma.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${deck.dueCount} due',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kNotesyInk,
                        ),
                      ),
                    )
                  else
                    Text(
                      '${(reviewed * 100).round()}% seen',
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
