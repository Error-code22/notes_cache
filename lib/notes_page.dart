import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services.dart';
import 'models.dart';
import 'note_detail_page.dart';
import 'upload_note_page.dart';
import 'local_docs_page.dart';

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
  final Set<String> _offlineAvailable = {};
  bool _offlineCheckDone = false;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotes();
    });
  }

  void _refreshNotes({bool? forceOffline}) {
    final noteService = context.read<NoteService>();
    final user = context.read<AuthService>().currentUser!;
    final semester = _selectedFilter.startsWith('Semester')
        ? int.tryParse(_selectedFilter.split(' ').last)
        : null;
    final isOffline = forceOffline ?? !(widget.connectivity?.isOnline.value ?? true);
    if (isOffline) {
      setState(() {
        _notesFuture = noteService.getCachedNotes(user.id, semester: semester);
      });
    } else {
      setState(() {
        _notesFuture = noteService.getNotesForUser(
          user,
          searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
          semester: semester,
          myNotesOnly: _myNotesOnly,
        );
      });
    }
  }


  /// File-type of a note, matching the card icon logic.
  String _typeOf(Note n) {
    final title = n.title.toLowerCase();
    final category = (n.category ?? '').toLowerCase();
    if (title.endsWith('.pdf') || category == 'pdf') return 'pdf';
    if (title.endsWith('.pptx') || title.endsWith('.ppt') || category == 'slides' || category == 'presentation') return 'ppt';
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
  Future<void> _checkOfflineAvailability(List<Note> notes) async {
    if (_offlineCheckDone) return;
    final noteService = context.read<NoteService>();
    final available = <String>{};
    for (final n in notes) {
      if (await noteService.isAvailableOffline(n)) available.add(n.id);
    }
    if (!mounted) return;
    setState(() {
      _offlineCheckDone = true;
      _offlineAvailable.addAll(available);
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
              _refreshNotes();
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

                    // Fire-and-forget file health check (cached 12h)
                    if (notes.isNotEmpty) {
                      unawaited(
                        context.read<NoteService>().checkNotesHealth(notes).then((_) {
                          if (mounted) setState(() {});
                        }),
                      );
                    }

                    final filtered = _typeFilter == null
                        ? notes
                        : notes.where((n) => _typeOf(n) == _typeFilter).toList();

                    // Mark which notes are available offline (once per session)
                    unawaited(_checkOfflineAvailability(notes));

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notes_rounded, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                            const SizedBox(height: 16),
                            Text(
                              notes.isEmpty ? 'No matching notes found.' : 'No ${_typeFilter?.toUpperCase()} files in this view.',
                              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                            ),
                          ],
                        ),
                      );
                    }
  
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => _buildNoteCard(context, filtered[index]),
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
    } else if (title.endsWith('.pptx') || title.endsWith('.ppt') || category == 'slides' || category == 'presentation') {
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
