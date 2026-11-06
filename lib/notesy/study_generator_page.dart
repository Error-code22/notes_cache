import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services.dart';
import 'notesy_style.dart';
import 'study_models.dart';
import 'study_service.dart';
import 'study_store.dart';

enum StudySourceMode { note, topic }

/// Creates a study set from a library note, a typed topic, or an answer that
/// was just produced in chat. Generation needs a connection; everything after
/// this page is local.
class StudyGeneratorPage extends StatefulWidget {
  const StudyGeneratorPage({
    super.key,
    this.initialMode = StudySourceMode.note,
    this.initialTopic = '',
    this.initialTitle = '',
    this.initialContent = '',
    this.initialNote,
    this.preferQuiz = false,
  });

  final StudySourceMode initialMode;
  final String initialTopic;
  final String initialTitle;
  final String initialContent;
  final Note? initialNote;
  final bool preferQuiz;

  @override
  State<StudyGeneratorPage> createState() => _StudyGeneratorPageState();
}

class _StudyGeneratorPageState extends State<StudyGeneratorPage> {
  late StudySourceMode _mode;
  late final TextEditingController _titleController;
  late final TextEditingController _topicController;
  final TextEditingController _noteSearchController = TextEditingController();

  String _userId = 'guest_user';
  bool _isGuest = true;
  bool _loadingNotes = false;
  bool _generating = false;
  List<Note> _notes = const [];
  Note? _selectedNote;
  int _cardCount = 8;
  int _quizCount = 5;

  bool get _fixedSource => widget.initialContent.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedNote = widget.initialNote;
    _mode = _fixedSource
        ? StudySourceMode.topic
        : (widget.initialNote != null ? StudySourceMode.note : widget.initialMode);
    _titleController = TextEditingController(
      text: widget.initialTitle.isNotEmpty
          ? widget.initialTitle
          : (widget.initialNote?.title ?? ''),
    );
    _topicController = TextEditingController(
      text: _fixedSource ? widget.initialContent : widget.initialTopic,
    );
    _quizCount = widget.preferQuiz ? 10 : 5;
    final user = context.read<AuthService>().currentUser;
    _userId = user?.id ?? 'guest_user';
    _isGuest = user?.isGuest ?? true;
    if (widget.initialNote != null) {
      _notes = [widget.initialNote!];
    }
    if (!_fixedSource && _mode == StudySourceMode.note) {
      _loadNotes();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _topicController.dispose();
    _noteSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    if (_isGuest || _loadingNotes) return;
    setState(() => _loadingNotes = true);
    try {
      final user = context.read<AuthService>().currentUser;
      if (user == null) return;
      final notes = await NoteService().getNotesForUser(user);
      if (mounted) setState(() => _notes = notes);
    } catch (e) {
      debugPrint('StudyGenerator.loadNotes error: $e');
    } finally {
      if (mounted) setState(() => _loadingNotes = false);
    }
  }

  Future<void> _pickNote() async {
    if (_isGuest) {
      _snack('Sign in to build study sets from library notes.');
      return;
    }
    if (_loadingNotes) return;
    if (_notes.isEmpty) {
      await _loadNotes();
      if (!mounted) return;
    }
    if (_notes.isEmpty) {
      _snack('No library notes are available yet. Try a topic instead.');
      return;
    }
    final picked = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotePickerSheet(notes: _notes),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedNote = picked;
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = picked.title;
        }
      });
    }
  }

  String _noteText(Note note) {
    final pieces = <String>[];
    if ((note.summary ?? '').trim().isNotEmpty) pieces.add(note.summary!.trim());
    if (note.content.trim().isNotEmpty) pieces.add(note.content.trim());
    return pieces.join('\n\n');
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    final title = _titleController.text.trim();
    String source;
    String sourceLabel;
    String sourceKind;

    if (_mode == StudySourceMode.note) {
      final note = _selectedNote;
      if (note == null) {
        _snack('Choose a note first.');
        return;
      }
      source = _noteText(note);
      sourceLabel = note.title;
      sourceKind = 'note';
      if (source.trim().length < 20) {
        _snack('This note has no readable text yet. Try a topic instead.');
        return;
      }
    } else {
      source = _topicController.text.trim();
      sourceLabel = _fixedSource ? (title.isEmpty ? 'Notesy answer' : title) : 'Topic';
      sourceKind = _fixedSource ? 'answer' : 'topic';
      if (source.length < 20) {
        _snack('Add a little more detail so Notesy has something to work with.');
        return;
      }
    }

    final fallbackTitle = title.isNotEmpty
        ? title
        : _mode == StudySourceMode.note
            ? _selectedNote!.title
            : source.split(RegExp(r'\s+')).take(8).join(' ');

    setState(() => _generating = true);
    try {
      final pack = await StudyService().generate(
        title: fallbackTitle,
        source: source,
        cardCount: _cardCount,
        quizCount: _quizCount,
      );
      final now = DateTime.now();
      final deck = StudyDeck(
        id: '${now.microsecondsSinceEpoch}',
        title: pack.title,
        sourceLabel: sourceLabel,
        sourceKind: sourceKind,
        createdAt: now,
        updatedAt: now,
        cards: pack.cards,
        quiz: pack.quiz,
      );
      await StudyStore.upsert(_userId, deck);
      if (!mounted) return;
      Navigator.pop(context, deck);
    } on StudyException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      debugPrint('StudyGenerator.generate error: $e');
      if (mounted) {
        _snack('Could not build this study set. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: kNotesyInk),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New study set'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildIntro(theme),
                const SizedBox(height: 18),
                _buildSourcePicker(theme),
                if (_mode == StudySourceMode.note) ...[
                  const SizedBox(height: 12),
                  _buildNoteTile(theme),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _topicController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: _fixedSource ? 'Source answer' : 'Topic or source text',
                      hintText: 'e.g. The water cycle, or paste the material you want to revise',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Study set name (optional)',
                    hintText: 'Notesy will suggest one',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _buildCountRow(
                  theme,
                  label: 'Flashcards',
                  values: const [8, 12, 16],
                  selected: _cardCount,
                  onSelected: (value) => setState(() => _cardCount = value),
                ),
                const SizedBox(height: 14),
                _buildCountRow(
                  theme,
                  label: 'Quiz questions',
                  values: const [0, 5, 10],
                  selected: _quizCount,
                  onSelected: (value) => setState(() => _quizCount = value),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  style: FilledButton.styleFrom(
                    backgroundColor: kNotesyLuma,
                    foregroundColor: kNotesyInk,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _generating ? 'Building your set…' : 'Build study set',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Notesy reads the source and writes the cards. Review them once before relying on them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_generating)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: kNotesyLuma),
                        const SizedBox(height: 18),
                        const Text(
                          'Building your study set',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Finding the ideas worth remembering…',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIntro(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Make it stick.',
          style: TextStyle(
            fontSize: 28,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Turn a note or topic into flashcards and a quick quiz. Saved on this device.',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSourcePicker(ThemeData theme) {
    if (_fixedSource) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kNotesyLuma.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kNotesyLuma.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, color: kNotesyInk),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Using the answer from this chat',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SegmentedButton<StudySourceMode>(
      segments: const [
        ButtonSegment(
          value: StudySourceMode.note,
          label: Text('From a note'),
          icon: Icon(Icons.menu_book_outlined),
        ),
        ButtonSegment(
          value: StudySourceMode.topic,
          label: Text('From a topic'),
          icon: Icon(Icons.lightbulb_outline_rounded),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (value) {
        final next = value.first;
        setState(() => _mode = next);
        if (next == StudySourceMode.note && _notes.isEmpty) _loadNotes();
      },
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return kNotesyInk;
          return theme.colorScheme.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return kNotesyFold;
          return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
        }),
      ),
    );
  }

  Widget _buildNoteTile(ThemeData theme) {
    final note = _selectedNote;
    return InkWell(
      onTap: _pickNote,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: note == null
                ? theme.colorScheme.outlineVariant
                : kNotesyLuma.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kNotesyLuma.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.description_outlined, color: kNotesyInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note?.title ?? (_isGuest ? 'Sign in to choose a note' : 'Choose a note'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note == null
                        ? 'Notesy will use its summary and extracted text.'
                        : 'Year ${note.targetYear} • Semester ${note.semester}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_loadingNotes)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildCountRow(
    ThemeData theme, {
    required String label,
    required List<int> values,
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(value == 0 ? 'None' : '$value'),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
                selectedColor: kNotesyFold,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected == value ? kNotesyInk : theme.colorScheme.onSurfaceVariant,
                ),
                side: BorderSide(
                  color: selected == value
                      ? kNotesyLuma
                      : theme.colorScheme.outlineVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NotePickerSheet extends StatefulWidget {
  const _NotePickerSheet({required this.notes});

  final List<Note> notes;

  @override
  State<_NotePickerSheet> createState() => _NotePickerSheetState();
}

class _NotePickerSheetState extends State<_NotePickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.text.trim().toLowerCase();
    final visible = widget.notes.where((note) {
      if (query.isEmpty) return true;
      return note.title.toLowerCase().contains(query) ||
          note.lecturerName.toLowerCase().contains(query) ||
          (note.category ?? '').toLowerCase().contains(query);
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose a note',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search your library',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          'No notes match that search.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final note = visible[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: kNotesyLuma.withValues(alpha: 0.2),
                              child: const Icon(
                                Icons.description_outlined,
                                color: kNotesyInk,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Year ${note.targetYear} • Semester ${note.semester}${note.lecturerName.isEmpty ? '' : ' • ${note.lecturerName}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, note),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
