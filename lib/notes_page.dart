import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services.dart';
import 'models.dart';
import 'note_detail_page.dart';
import 'upload_note_page.dart';
import 'local_docs_page.dart';
import 'taxonomy_service.dart';

enum NoteViewMode { list, details, compact }

/// File-type filter options — icons/colors mirror the note cards.
class _TypeFilter {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const _TypeFilter(this.key, this.label, this.icon, this.color);
}

const List<_TypeFilter> _typeFilters = [
  _TypeFilter('pdf', 'PDF', Icons.picture_as_pdf_rounded, Colors.red),
  _TypeFilter('doc', 'DOC', Icons.article_rounded, Colors.blue),
  _TypeFilter('ppt', 'PPT', Icons.slideshow_rounded, Colors.orange),
  _TypeFilter('xls', 'XLS', Icons.table_chart_rounded, Colors.green),
  _TypeFilter('vid', 'VID', Icons.play_circle_fill_rounded, Colors.indigo),
  _TypeFilter('aud', 'AUD', Icons.audiotrack_rounded, Colors.pink),
  _TypeFilter('img', 'IMG', Icons.image_rounded, Colors.purple),
  _TypeFilter('code', 'CODE', Icons.code_rounded, Colors.blueGrey),
  _TypeFilter('txt', 'TXT/MD', Icons.text_snippet_rounded, Colors.teal),
  _TypeFilter('other', 'OTHER', Icons.description_rounded, Colors.blueGrey),
];

const String _allUnitsValue = '__all_units__';

/// A stage or unit heading in the grouped notes list.
class _NoteSectionHeader {
  final String title;
  final bool isStage;
  final int noteCount;

  const _NoteSectionHeader({
    required this.title,
    this.isStage = false,
    this.noteCount = 0,
  });
}

/// Notes sharing a stage/semester/unit section.
class _NoteUnitGroup {
  final int stageYear;
  final int semester;
  final String? unitKey;
  final String label;
  final List<Note> notes = [];

  _NoteUnitGroup({
    required this.stageYear,
    required this.semester,
    required this.unitKey,
    required this.label,
  });
}

class NotesPage extends StatefulWidget {
  final ConnectivityService? connectivity;

  const NotesPage({super.key, this.connectivity});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  String _searchQuery = '';
  String _selectedFilter = 'All Notes';
  String? _typeFilter;
  bool _myNotesOnly = false;
  NoteViewMode _viewMode = NoteViewMode.list;
  Future<List<Note>>? _notesFuture;
  bool _downloadingOffline = false;
  bool _healthCheckPending = false;
  Timer? _searchDebounce;
  final Set<String> _offlineAvailable = {};
  bool _offlineCheckDone = false;
  int? _selectedStage;
  String? _selectedUnitId;
  List<ProgrammeUnit> _programmeUnits = const [];
  bool _programmeUnitsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _loadProgrammeUnits();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotes();
    });
  }

  /// Loads the viewer's programme basket once so the Unit dropdown and
  /// unit titles are available without another round-trip per note.
  Future<void> _loadProgrammeUnits() async {
    final programmeId = context.read<AuthService>().currentUser?.programmeId;
    if (programmeId == null || programmeId.trim().isEmpty) {
      return;
    }
    _programmeUnitsLoading = true;
    try {
      final units = await TaxonomyService().getProgrammeUnits(programmeId);
      if (!mounted) return;
      setState(() {
        _programmeUnits = units;
        _programmeUnitsLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load programme units: $e');
      if (!mounted) return;
      setState(() => _programmeUnitsLoading = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _refreshNotes({bool? forceOffline}) {
    final noteService = context.read<NoteService>();
    final user = context.read<AuthService>().currentUser!;
    final isOffline = forceOffline ?? !(widget.connectivity?.isOnline.value ?? true);
    if (isOffline) {
      // No semester/unit filters here: the cached list always holds the full
      // programme library, and the grouped view filters it client-side.
      setState(() {
        _notesFuture = noteService.getCachedNotes(user.id);
      });
    } else {
      setState(() {
        _notesFuture = noteService.getNotesForUser(
          user,
          searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
          myNotesOnly: _myNotesOnly,
        );
      });
    }
  }

  int? get _selectedSemester {
    if (!_selectedFilter.startsWith('Semester')) return null;
    return int.tryParse(_selectedFilter.split(' ').last);
  }

  /// The taxonomy unit id on a note, with a code-only fallback for notes
  /// imported before unit ids were stored.
  String? _unitIdOf(Note note) {
    final unitId = note.unitId?.trim();
    return (unitId == null || unitId.isEmpty) ? null : unitId;
  }

  String? _unitCodeOf(Note note) {
    final code = note.unitCode?.trim();
    if (code != null && code.isNotEmpty) return code;
    final unitCode = _programmeUnitFor(_unitIdOf(note))?.unitCode.trim();
    return (unitCode == null || unitCode.isEmpty) ? null : unitCode;
  }

  String? _unitTitleOf(Note note) {
    final title = _programmeUnitFor(_unitIdOf(note))?.unitTitle.trim();
    return (title == null || title.isEmpty) ? null : title;
  }

  ProgrammeUnit? _programmeUnitFor(String? unitId) {
    if (unitId == null) return null;
    for (final unit in _programmeUnits) {
      // notes.unit_id points at units.id; also tolerate callers storing the
      // programme_units row id.
      if (unit.unitId == unitId || unit.id == unitId) return unit;
    }
    return null;
  }

  /// Unit heading/card label, e.g. "IGB3405 IT and Society".
  String _unitLabelFor(Note note) {
    final code = _unitCodeOf(note);
    final title = _unitTitleOf(note);
    if (code != null && title != null) return '$code $title';
    if (code != null) return code;
    if (title != null) return title;
    return 'Unassigned (legacy)';
  }

  /// Stable grouping key; null means the note predates unit taxonomy.
  String? _unitGroupKey(Note note) {
    final unitId = _unitIdOf(note);
    if (unitId != null) return 'id:$unitId';
    final code = note.unitCode?.trim();
    if (code != null && code.isNotEmpty) return 'code:$code';
    return null;
  }

  bool _matchesUnitFilter(Note note) {
    final selected = _selectedUnitId;
    if (selected == null) return true;
    if (_unitIdOf(note) == selected) return true;
    // A selected programme unit should also catch notes that only carry the
    // unit code (legacy rows).
    final unit = _programmeUnitFor(selected);
    final code = note.unitCode?.trim();
    return unit != null &&
        _unitIdOf(note) == null &&
        code != null &&
        code.isNotEmpty &&
        code == unit.unitCode;
  }

  bool _matchesFilters(Note note) {
    final semester = _selectedSemester;
    if (semester != null && (note.stageSemester ?? note.semester) != semester) {
      return false;
    }
    if (_selectedStage != null && (note.stageYear ?? note.targetYear) != _selectedStage) {
      return false;
    }
    if (!_matchesUnitFilter(note)) return false;
    if (_typeFilter != null && _typeOf(note) != _typeFilter) return false;
    return true;
  }

  /// Flattens filtered notes into stage headers, unit headers and note cards.
  /// Ordering is Stage -> Semester -> Unit (unassigned sections last).
  List<Object> _buildGroupedEntries(List<Note> notes) {
    final groups = <String, _NoteUnitGroup>{};
    for (final note in notes) {
      final stageYear = note.stageYear ?? note.targetYear;
      final semester = note.stageSemester ?? note.semester;
      final unitKey = _unitGroupKey(note);
      final groupKey = '$stageYear|$semester|${unitKey ?? 'legacy'}';
      groups
          .putIfAbsent(
            groupKey,
            () => _NoteUnitGroup(
              stageYear: stageYear,
              semester: semester,
              unitKey: unitKey,
              label: _unitLabelFor(note),
            ),
          )
          .notes
          .add(note);
    }

    final ordered = groups.values.toList()
      ..sort((a, b) {
        final byStage = a.stageYear.compareTo(b.stageYear);
        if (byStage != 0) return byStage;
        final bySemester = a.semester.compareTo(b.semester);
        if (bySemester != 0) return bySemester;
        if (a.unitKey == null && b.unitKey != null) return 1;
        if (a.unitKey != null && b.unitKey == null) return -1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    final stageCounts = <int, int>{};
    for (final note in notes) {
      final stage = note.stageYear ?? note.targetYear;
      stageCounts[stage] = (stageCounts[stage] ?? 0) + 1;
    }

    final entries = <Object>[];
    int? currentStage;
    for (final group in ordered) {
      if (group.stageYear != currentStage) {
        currentStage = group.stageYear;
        entries.add(_NoteSectionHeader(
          title: 'YEAR ${group.stageYear}',
          isStage: true,
          noteCount: stageCounts[group.stageYear] ?? group.notes.length,
        ));
      }
      entries.add(_NoteSectionHeader(
        title: 'Y${group.stageYear}S${group.semester} • ${group.label}',
        noteCount: group.notes.length,
      ));
      entries.addAll(group.notes);
    }
    return entries;
  }

  /// File-type of a note, matching the card icon logic.
  String _typeOf(Note n) {
    final title = n.title.toLowerCase();
    final category = (n.category ?? '').toLowerCase();
    if (title.endsWith('.pdf') || category == 'pdf') return 'pdf';
    if (title.endsWith('.pptx') || title.endsWith('.ppt') || title.endsWith('.pub') || category == 'slides' || category == 'presentation' || category == 'publisher') return 'ppt';
    if (title.endsWith('.docx') || title.endsWith('.doc') || category == 'document' || category == 'word') return 'doc';
    if (title.endsWith('.xlsx') || title.endsWith('.xls') || title.endsWith('.csv') || category == 'spreadsheet') return 'xls';
    if (title.endsWith('.mp4') || title.endsWith('.mov') || title.endsWith('.mkv') || category == 'video' || category == 'vid') return 'vid';
    if (title.endsWith('.mp3') || title.endsWith('.wav') || title.endsWith('.m4a') || category == 'audio') return 'aud';
    if (title.endsWith('.jpg') || title.endsWith('.jpeg') || title.endsWith('.png') || category == 'image') return 'img';
    if (title.endsWith('.py') || title.endsWith('.java') || title.endsWith('.cpp') || title.endsWith('.dart') || title.endsWith('.json') || title.endsWith('.html') || category == 'code') return 'code';
    if (title.endsWith('.md')) return 'txt';
    if (title.endsWith('.txt') || category == 'text') return 'txt';
    return 'other';
  }

  /// Checks which notes already have local copies (for the OFFLINE badge).
  /// Runs the checks in parallel — was one sequential await per note.
  Future<void> _checkOfflineAvailability(List<Note> notes) async {
    if (_offlineCheckDone) return;
    final noteService = context.read<NoteService>();
    final results = await Future.wait(notes.map((n) async {
      final ok = await noteService.isAvailableOffline(n);
      return (id: n.id, ok: ok);
    }));
    if (!mounted) return;
    setState(() {
      _offlineCheckDone = true;
      for (final r in results) {
        if (r.ok) _offlineAvailable.add(r.id);
      }
    });
  }

  /// Bulk-downloads all note files so the app works fully offline.
  Future<void> _downloadAllOffline() async {
    if (_downloadingOffline) return;
    final messenger = ScaffoldMessenger.of(context);
    final notes = await _notesFuture ?? [];
    setState(() => _downloadingOffline = true);
    messenger.showSnackBar(
      SnackBar(content: Text('Downloading ${notes.length} files for offline...'), backgroundColor: Colors.blue),
    );
    final result = await context.read<NoteService>().downloadAllForOffline(notes);
    if (!mounted) return;
    setState(() {
      _downloadingOffline = false;
      _offlineCheckDone = false;
    });
    await _checkOfflineAvailability(notes);
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.failed == 0
            ? '✅ All files ready for offline reading'
            : '${result.ok} ready, ${result.failed} failed (some may be unavailable)'),
        backgroundColor: result.failed == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt('note_view_mode') ?? NoteViewMode.list.index;
    if (mounted) {
      setState(() {
        _viewMode = NoteViewMode.values[modeIndex];
      });
    }
  }

  Future<void> _saveViewMode(NoteViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('note_view_mode', mode.index);
    setState(() => _viewMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final noteService = context.read<NoteService>();
    final user = context.watch<AuthService>().currentUser!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Container(
          height: 40,
          constraints: const BoxConstraints(maxWidth: 400),
          child: TextField(
            onChanged: (value) {
              _searchQuery = value.toLowerCase();
              // Debounce: wait 350ms after the last keystroke before hitting
              // the DB (was one round-trip per character).
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), _refreshNotes);
            },
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search notes...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: theme.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.filter_list_rounded,
              color: _typeFilter != null ? primaryColor : null,
            ),
            tooltip: _typeFilter == null ? 'Filter by type' : 'Filter: ${_typeFilter!.toUpperCase()}',
            onSelected: (value) {
              setState(() => _typeFilter = value == 'all' ? null : value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Row(children: [
                  Icon(Icons.folder_outlined, size: 20, color: _typeFilter == null ? primaryColor : Colors.grey),
                  const SizedBox(width: 10),
                  Text('All Files', style: TextStyle(fontWeight: _typeFilter == null ? FontWeight.bold : FontWeight.normal)),
                ]),
              ),
              const PopupMenuDivider(),
              for (final t in _typeFilters)
                PopupMenuItem(
                  value: t.key,
                  child: Row(children: [
                    Icon(t.icon, size: 20, color: t.color),
                    const SizedBox(width: 10),
                    Text(t.label, style: TextStyle(fontWeight: _typeFilter == t.key ? FontWeight.bold : FontWeight.normal)),
                  ]),
                ),
            ],
          ),
          PopupMenuButton<NoteViewMode>(
            icon: const Icon(Icons.view_agenda_outlined),
            onSelected: _saveViewMode,
            itemBuilder: (context) => [
              const PopupMenuItem(value: NoteViewMode.list, child: ListTile(leading: Icon(Icons.view_list_rounded), title: Text('List View'))),
              const PopupMenuItem(value: NoteViewMode.details, child: ListTile(leading: Icon(Icons.view_agenda_rounded), title: Text('Detailed View'))),
              const PopupMenuItem(value: NoteViewMode.compact, child: ListTile(leading: Icon(Icons.grid_view_rounded), title: Text('Compact View'))),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'offline') _downloadAllOffline();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'offline',
                child: Row(children: [
                  const Icon(Icons.download_for_offline_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(_downloadingOffline ? 'Downloading...' : 'Download All for Offline'),
                ]),
              ),
            ],
          ),
        ],
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Listener(
          // Scrolling/tapping the list dismisses the search keyboard
          onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
          children: [
            const SizedBox(height: 16),
  
            // Filters
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  _buildFilterChip(context, 'All Notes'),
                  if (!(context.read<AuthService>().currentUser?.isGuest ?? true))
                    _buildMyNotesChip(context),
                  _buildLocalDocsChip(context),
                  _buildSemesterDropdown(context),
                  _buildStageDropdown(context),
                  _buildUnitDropdown(context),
                  _buildFilterChip(context, 'Past Papers'),
                  _buildFilterChip(context, 'Exam Solutions'),
                ],
              ),
            ),
  
            const SizedBox(height: 24),

            // Offline banner
            if (widget.connectivity != null)
              ValueListenableBuilder<bool>(
                valueListenable: widget.connectivity!.isOnline,
                builder: (context, online, _) {
                  if (online) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You are offline - showing cached notes',
                            style: TextStyle(color: Colors.orange.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // Notes List
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FutureBuilder<List<Note>>(
                  future: _notesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final notes = snapshot.data ?? [];

                    // Fire-and-forget file health check (cached 12h).
                    // Only rebuilds the list when a health status actually
                    // changed — otherwise this looped forever.
                    if (notes.isNotEmpty && !_healthCheckPending) {
                      _healthCheckPending = true;
                      unawaited(
                        context.read<NoteService>().checkNotesHealth(notes).then((changed) {
                          _healthCheckPending = false;
                          if (changed && mounted) setState(() {});
                        }),
                      );
                    }

                    final filtered = notes.where(_matchesFilters).toList();
                    final entries = _buildGroupedEntries(filtered);

                    // Mark which notes are available offline (once per session)
                    unawaited(_checkOfflineAvailability(notes));

                    if (entries.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notes_rounded, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                            const SizedBox(height: 16),
                            Text(
                              notes.isEmpty ? 'No matching notes found.' : 'No ${_typeFilter?.toUpperCase() ?? 'notes'} in this view.',
                              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      );
                    }
   
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is _NoteSectionHeader) {
                          return _buildSectionHeader(context, entry);
                        }
                        return _buildNoteCard(context, entry as Note);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
          ),
        ),
      ),
      floatingActionButton: (user.hasRole(UserRole.lecturer) || user.hasRole(UserRole.admin))
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const UploadNotePage()),
                );
              },
              backgroundColor: primaryColor,
              foregroundColor: theme.colorScheme.onPrimary,
              icon: const Icon(Icons.add),
              label: const Text('UPLOAD NOTE', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  /// "Local Docs" action next to All Notes — opens the device's imported docs.
  Widget _buildLocalDocsChip(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(Icons.folder_open_rounded, size: 16, color: primaryColor),
        label: const Text('Local Docs'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LocalDocsPage()),
        ),
        backgroundColor: theme.cardColor,
        labelStyle: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: primaryColor.withOpacity(0.25)),
        ),
      ),
    );
  }

  /// Semester chips merged into a single dropdown.
  Widget _buildSemesterDropdown(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isSemester = _selectedFilter.startsWith('Semester');
    final semesterNum = isSemester ? _selectedFilter.split(' ').last : 'All';

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isSemester ? primaryColor.withOpacity(0.1) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSemester ? primaryColor.withOpacity(0.2) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_rounded, size: 16, color: isSemester ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7)),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: semesterNum,
              dropdownColor: theme.cardColor,
              icon: Icon(Icons.arrow_drop_down_rounded, color: isSemester ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7)),
              style: TextStyle(
                fontSize: 13,
                color: isSemester ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7),
                fontWeight: isSemester ? FontWeight.bold : FontWeight.normal,
              ),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('Semester: All')),
                DropdownMenuItem(value: '1', child: Text('Semester 1')),
                DropdownMenuItem(value: '2', child: Text('Semester 2')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedFilter = value == 'All' ? 'All Notes' : 'Semester $value';
                });
                _refreshNotes();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Stage filter (all years / 1–4).
  Widget _buildStageDropdown(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isFiltered = _selectedStage != null;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isFiltered ? primaryColor.withOpacity(0.1) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isFiltered ? primaryColor.withOpacity(0.2) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stairs_rounded, size: 16, color: isFiltered ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7)),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedStage ?? 0,
              dropdownColor: theme.cardColor,
              icon: Icon(Icons.arrow_drop_down_rounded, color: isFiltered ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7)),
              style: TextStyle(
                fontSize: 13,
                color: isFiltered ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7),
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Stage: All')),
                DropdownMenuItem(value: 1, child: Text('Stage 1')),
                DropdownMenuItem(value: 2, child: Text('Stage 2')),
                DropdownMenuItem(value: 3, child: Text('Stage 3')),
                DropdownMenuItem(value: 4, child: Text('Stage 4')),
              ],
              onChanged: (value) {
                setState(() => _selectedStage = value == 0 ? null : value);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Unit filter built from the viewer's programme basket. Gracefully falls
  /// back to "All units" when no programme / units are available.
  Widget _buildUnitDropdown(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isFiltered = _selectedUnitId != null;

    final unitsById = <String, ProgrammeUnit>{};
    for (final unit in _programmeUnits) {
      unitsById.putIfAbsent(unit.unitId, () => unit);
    }
    final units = unitsById.values.toList()
      ..sort((a, b) => a.unitCode.toLowerCase().compareTo(b.unitCode.toLowerCase()));
    final hasSelection = _selectedUnitId != null && unitsById.containsKey(_selectedUnitId);
    final selectedValue = hasSelection ? _selectedUnitId! : _allUnitsValue;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isFiltered ? primaryColor.withOpacity(0.1) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isFiltered ? primaryColor.withOpacity(0.2) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded, size: 16, color: isFiltered ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7)),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              dropdownColor: theme.cardColor,
              icon: Icon(Icons.arrow_drop_down_rounded, color: isFiltered ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7)),
              style: TextStyle(
                fontSize: 13,
                color: isFiltered ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7),
                fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
              ),
              items: [
                DropdownMenuItem(
                  value: _allUnitsValue,
                  child: Text(_programmeUnitsLoading ? 'Unit: Loading…' : 'Unit: All'),
                ),
                for (final unit in units)
                  DropdownMenuItem(
                    value: unit.unitId,
                    child: Text(
                      '${unit.unitCode} — ${unit.unitTitle}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selectedItemBuilder: (context) => [
                Text(_programmeUnitsLoading ? 'Unit: Loading…' : 'Unit: All'),
                for (final unit in units) Text(unit.unitCode),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedUnitId = value == _allUnitsValue ? null : value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyNotesChip(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: Icon(Icons.person_outline_rounded, size: 16,
            color: _myNotesOnly ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.6)),
        label: const Text('My Notes'),
        selected: _myNotesOnly,
        onSelected: (val) {
          setState(() {
            _myNotesOnly = val;
            _selectedFilter = 'All Notes';
          });
          _refreshNotes();
        },
        backgroundColor: theme.cardColor,
        selectedColor: primaryColor.withOpacity(0.1),
        checkmarkColor: primaryColor,
        labelStyle: TextStyle(
          color: _myNotesOnly ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7),
          fontWeight: _myNotesOnly ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _myNotesOnly ? primaryColor.withOpacity(0.2) : Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label) {
    final isSelected = _selectedFilter == label;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          final wasMyNotes = _myNotesOnly;
          setState(() {
            _selectedFilter = label;
            if (label == 'All Notes') _myNotesOnly = false;
          });
          if (label == 'All Notes' && wasMyNotes) _refreshNotes();
        },
        backgroundColor: theme.cardColor,
        selectedColor: primaryColor.withOpacity(0.1),
        checkmarkColor: primaryColor,
        labelStyle: TextStyle(
          color: isSelected ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.7),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isSelected ? primaryColor.withOpacity(0.2) : Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, _NoteSectionHeader header) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (header.isStage) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Row(
          children: [
            Text(
              header.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${header.noteCount} ${header.noteCount == 1 ? 'note' : 'notes'}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Divider(
                height: 1,
                color: theme.dividerColor.withOpacity(0.2),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.folder_copy_rounded, size: 16, color: primaryColor.withOpacity(0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              header.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${header.noteCount}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, Note note) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isHealthy = context.read<NoteService>().isFileHealthy(note.id);
    final showUnavailable = isHealthy == false;
    final showOffline = _offlineAvailable.contains(note.id);

    // Dynamic Icon & Color logic
    IconData fileIcon = Icons.article_rounded;
    Color fileColor = primaryColor;
    String typeLabel = 'NOTE';

    final title = note.title.toLowerCase();
    final category = (note.category ?? '').toLowerCase();
    
    if (title.endsWith('.pdf') || category == 'pdf') {
      fileIcon = Icons.picture_as_pdf_rounded;
      fileColor = Colors.red;
      typeLabel = 'PDF';
    } else if (title.endsWith('.pptx') || title.endsWith('.ppt') || title.endsWith('.pub') || category == 'slides' || category == 'presentation' || category == 'publisher') {
      fileIcon = Icons.slideshow_rounded;
      fileColor = Colors.orange;
      typeLabel = 'PPT';
    } else if (title.endsWith('.docx') || title.endsWith('.doc') || category == 'document' || category == 'word') {
      fileIcon = Icons.article_rounded;
      fileColor = Colors.blue;
      typeLabel = 'DOC';
    } else if (title.endsWith('.xlsx') || title.endsWith('.xls') || title.endsWith('.csv') || category == 'spreadsheet') {
      fileIcon = Icons.table_chart_rounded;
      fileColor = Colors.green;
      typeLabel = 'XLS';
    } else if (title.endsWith('.mp4') || title.endsWith('.mov') || title.endsWith('.mkv') || category == 'video' || category == 'vid') {
      fileIcon = Icons.play_circle_fill_rounded;
      fileColor = Colors.indigo;
      typeLabel = 'VID';
    } else if (title.endsWith('.mp3') || title.endsWith('.wav') || title.endsWith('.m4a') || category == 'audio') {
      fileIcon = Icons.audiotrack_rounded;
      fileColor = Colors.pink;
      typeLabel = 'AUD';
    } else if (title.endsWith('.jpg') || title.endsWith('.png') || title.endsWith('.jpeg') || category == 'image') {
      fileIcon = Icons.image_rounded;
      fileColor = Colors.purple;
      typeLabel = 'IMG';
    } else if (title.endsWith('.py') || title.endsWith('.java') || title.endsWith('.cpp') || title.endsWith('.dart') || title.endsWith('.json') || title.endsWith('.html') || category == 'code') {
      fileIcon = Icons.code_rounded;
      fileColor = Colors.blueGrey;
      typeLabel = 'CODE';
    } else if (title.endsWith('.md')) {
      fileIcon = Icons.description_rounded;
      fileColor = Colors.teal;
      typeLabel = 'MD';
    } else if (title.endsWith('.txt') || category == 'text') {
      fileIcon = Icons.text_snippet_rounded;
      fileColor = Colors.teal;
      typeLabel = 'TXT';
    } else {
      // Smart Heuristics for old files uploaded before the extension-fix
      if (title.contains('assignment') || title.contains('case') || title.contains('lit') || title.contains('rev') || title.contains('report')) {
        fileIcon = Icons.picture_as_pdf_rounded;
        fileColor = Colors.red;
        typeLabel = 'PDF';
      } else if (title.contains('summary') || title.contains('note')) {
        fileIcon = Icons.text_snippet_rounded;
        fileColor = Colors.teal;
        typeLabel = 'TXT';
      } else if (title.contains('presentation') || title.contains('slide')) {
        fileIcon = Icons.slideshow_rounded;
        fileColor = Colors.orange;
        typeLabel = 'PPT';
      } else {
        fileIcon = Icons.description_rounded;
        fileColor = Colors.blueGrey;
        typeLabel = 'DOC';
      }
    }
    if (_viewMode == NoteViewMode.compact) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        color: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
        child: ListTile(
          dense: true,
          leading: Icon(fileIcon, color: fileColor, size: 20),
          title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Text('By ${note.lecturerName}${note.isFromCache ? ' • Cached' : ''}', style: const TextStyle(fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showOffline) _buildBadge('OFFLINE', Colors.green),
              if (showUnavailable) ...[
                const SizedBox(width: 6),
                _buildBadge('UNAVAILABLE', Colors.red),
              ],
              const SizedBox(width: 6),
              _buildBadge(typeLabel, fileColor),
            ],
          ),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailPage(note: note)));
            _refreshNotes();
          },
        ),
      );
    }

    if (_viewMode == NoteViewMode.details) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 16),
        color: theme.cardColor,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
        child: InkWell(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailPage(note: note)));
            _refreshNotes();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 100,
                width: double.infinity,
                color: fileColor.withOpacity(0.05),
                child: Center(child: Icon(fileIcon, color: fileColor, size: 48)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildBadge(typeLabel, fileColor),
                        const SizedBox(width: 8),
                        _buildBadge('Year ${note.targetYear}', Colors.blueGrey),
                        if (note.isFromCache) ...[
                          const SizedBox(width: 8),
                          _buildBadge('CACHED', Colors.orange),
                        ],
                        if (showOffline) ...[
                          const SizedBox(width: 8),
                          _buildBadge('OFFLINE', Colors.green),
                        ],
                        if (showUnavailable) ...[
                          const SizedBox(width: 8),
                          _buildBadge('UNAVAILABLE', Colors.red),
                        ],
                        const Spacer(),
                        Text(
                          '${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Authored by ${note.lecturerName}', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                    if (note.category != null) ...[
                      const SizedBox(height: 8),
                      Text(note.category!, style: TextStyle(color: fileColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: fileColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(fileIcon, color: fileColor),
        ),
        title: Text(note.title, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('By ${note.lecturerName} • Semester ${note.semester}', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildBadge(typeLabel, fileColor),
                const SizedBox(width: 8),
                _buildBadge('Year ${note.targetYear}', Colors.blueGrey),
                if (note.isFromCache) ...[
                  const SizedBox(width: 8),
                  _buildBadge('CACHED', Colors.orange),
                ],
                if (showOffline) ...[
                  const SizedBox(width: 8),
                  _buildBadge('OFFLINE', Colors.green),
                ],
                if (showUnavailable) ...[
                  const SizedBox(width: 8),
                  _buildBadge('UNAVAILABLE', Colors.red),
                ],
              ],
            ),
          ],
        ),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailPage(note: note)));
          _refreshNotes();
        },
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
