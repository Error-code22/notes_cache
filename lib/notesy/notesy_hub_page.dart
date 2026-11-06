import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_chat_page.dart';
import '../services.dart';
import 'notesy_style.dart';
import 'study_deck_page.dart';
import 'study_generator_page.dart';
import 'study_lab_page.dart';
import 'study_models.dart';
import 'study_store.dart';

/// The new Notesy front door. Chat is one mode, not the whole product; study
/// sets are the other. Both are reachable from here in one tap.
class NotesyHubPage extends StatefulWidget {
  const NotesyHubPage({super.key});

  @override
  State<NotesyHubPage> createState() => _NotesyHubPageState();
}

class _NotesyHubPageState extends State<NotesyHubPage> {
  final TextEditingController _promptController = TextEditingController();
  String _userId = 'guest_user';
  List<StudyDeck> _decks = const [];
  bool _loadingDecks = true;

  @override
  void initState() {
    super.initState();
    _userId = context.read<AuthService>().currentUser?.id ?? 'guest_user';
    _loadDecks();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadDecks() async {
    final decks = await StudyStore.load(_userId);
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _loadingDecks = false;
    });
  }

  Future<void> _openChat({String? prompt, bool autoSend = false}) async {
    FocusScope.of(context).unfocus();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(initialPrompt: prompt, autoSend: autoSend),
      ),
    );
  }

  void _submitPrompt() {
    final text = _promptController.text.trim();
    if (text.isEmpty) {
      _openChat();
      return;
    }
    _promptController.clear();
    _openChat(prompt: text, autoSend: true);
  }

  Future<void> _openStudyLab() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudyLabPage()),
    );
    if (mounted) await _loadDecks();
  }

  Future<void> _createStudySet({
    StudySourceMode mode = StudySourceMode.note,
    bool preferQuiz = false,
  }) async {
    final deck = await Navigator.push<StudyDeck>(
      context,
      MaterialPageRoute(
        builder: (_) => StudyGeneratorPage(
          initialMode: mode,
          preferQuiz: preferQuiz,
        ),
      ),
    );
    if (deck == null || !mounted) return;
    await _loadDecks();
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudyDeckPage(deck: deck, userId: _userId),
        ),
      );
      if (mounted) await _loadDecks();
    }
  }

  Future<void> _openDeck(StudyDeck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyDeckPage(deck: deck, userId: _userId),
      ),
    );
    if (mounted) await _loadDecks();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCards = _decks.fold<int>(0, (sum, deck) => sum + deck.cards.length);
    final dueCards = _decks.fold<int>(0, (sum, deck) => sum + deck.dueCount);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notesy',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: kNotesyLuma.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'STUDY AI',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w900,
                  color: kNotesyInk,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat history',
            onPressed: () => _openChat(),
            icon: const Icon(Icons.forum_outlined),
          ),
          const SizedBox(width: 4),
        ],
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadDecks,
        color: kNotesyInk,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
          children: [
            _buildHero(theme, dueCards),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pick a way to study',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '$totalCards cards saved',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildActionGrid(theme),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent study sets',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _openStudyLab,
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_loadingDecks)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(color: kNotesyLuma)),
              )
            else if (_decks.isEmpty)
              _buildFirstSet(theme)
            else
              SizedBox(
                height: 154,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _decks.take(4).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final deck = _decks[index];
                    return _RecentDeckCard(
                      deck: deck,
                      onTap: () => _openDeck(deck),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            _buildFootNote(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme, int dueCards) {
    return Container(
      decoration: notesyInkPanel(context),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -50,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kNotesyLuma.withValues(alpha: 0.3),
                    kNotesyLuma.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -40,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kNotesyFold.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    notesyMark(size: 46),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ask anything.\nRemember everything.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  dueCards > 0
                      ? '$dueCards ${dueCards == 1 ? 'card is' : 'cards are'} due today. Keep the streak going.'
                      : 'Use your notes, or start from any topic.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promptController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitPrompt(),
                          style: const TextStyle(color: kNotesyInk, fontSize: 14),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Ask about a note, topic, or homework...',
                            hintStyle: TextStyle(color: Colors.black45, fontSize: 13),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _submitPrompt,
                        tooltip: 'Ask Notesy',
                        icon: const Icon(Icons.arrow_upward_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: kNotesyLuma,
                          foregroundColor: kNotesyInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _promptChip(
                      'Explain a concept',
                      'Explain this concept simply, with one worked example: ',
                    ),
                    _promptChip(
                      'Summarize a note',
                      'Summarize the key points of this note and what I should remember for an exam: ',
                    ),
                    _promptChip(
                      'Make a study plan',
                      'Make me a realistic 7-day study plan for this course: ',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _promptChip(String label, String prompt) {
    return ActionChip(
      onPressed: () => _openChat(prompt: prompt, autoSend: false),
      label: Text(label),
      labelStyle: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
      backgroundColor: Colors.white.withValues(alpha: 0.09),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildActionGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickAction(
              width: width,
              icon: Icons.auto_awesome_rounded,
              title: 'From a note',
              subtitle: 'Turn it into cards',
              onTap: () => _createStudySet(),
            ),
            _QuickAction(
              width: width,
              icon: Icons.quiz_outlined,
              title: 'Quiz me',
              subtitle: 'Test recall fast',
              highlight: true,
              onTap: () => _createStudySet(preferQuiz: true),
            ),
            _QuickAction(
              width: width,
              icon: Icons.style_outlined,
              title: 'Study Lab',
              subtitle: _decks.isEmpty ? 'Your saved sets' : '${_decks.length} sets saved',
              onTap: _openStudyLab,
            ),
            _QuickAction(
              width: width,
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Open chat',
              subtitle: 'Ask, compare, explain',
              onTap: () => _openChat(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFirstSet(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: kNotesyLuma.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.style_outlined, color: kNotesyInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your first set takes a minute',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'Choose a note. Notesy writes the cards.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _createStudySet(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'Create a study set',
          ),
        ],
      ),
    );
  }

  Widget _buildFootNote(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Study sets are saved on this device. Chats and generation use Notesy online; reviewing works offline.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: highlight
            ? kNotesyLuma.withValues(alpha: 0.16)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: highlight
                    ? kNotesyLuma.withValues(alpha: 0.6)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: highlight ? kNotesyInk : kNotesyLuma, size: 24),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentDeckCard extends StatelessWidget {
  const _RecentDeckCard({required this.deck, required this.onTap});

  final StudyDeck deck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.style_outlined, color: kNotesyLuma, size: 20),
                    const Spacer(),
                    if (deck.dueCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: kNotesyLuma.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${deck.dueCount} due',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: kNotesyInk,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  deck.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${deck.cards.length} cards${deck.quiz.isEmpty ? '' : ' • ${deck.quiz.length} quiz'}',
                  style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: deck.cards.isEmpty ? 0 : deck.reviewedCount / deck.cards.length,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: kNotesyLuma,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
