import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'file_viewer_page.dart';
import 'r2_service.dart';
import 'services.dart';

/// Local documents from the device's own storage.
/// Two sources:
///  - "Scanned": docs found across the device (opened/edited IN PLACE —
///    no copies, no dual storage). Requires the one-time all-files access.
///  - "Imported": files the user explicitly picked to copy into the app's
///    private storage (guaranteed offline).
class LocalDocsPage extends StatefulWidget {
  const LocalDocsPage({super.key});

  @override
  State<LocalDocsPage> createState() => _LocalDocsPageState();
}

class LocalDocEntry {
  final String path;
  final String name;
  final int size;
  final String addedAt;

  const LocalDocEntry({required this.path, required this.name, required this.size, required this.addedAt});

  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'size': size, 'addedAt': addedAt};

  factory LocalDocEntry.fromJson(Map<String, dynamic> json) => LocalDocEntry(
        path: json['path'] as String,
        name: json['name'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        addedAt: (json['addedAt'] as String?) ?? '',
      );
}

class _LocalDocsPageState extends State<LocalDocsPage> {
  static const String _indexKey = 'local_docs_index';
  static const String _scannedKey = 'local_docs_scanned';

  // Document-only extensions (no images, no media)
  static const Set<String> _docExts = {
    '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.csv',
    '.txt', '.md', '.rtf', '.odt', '.ods', '.odp',
  };

  List<LocalDocEntry> _imported = [];
  List<File> _scanned = [];
  bool _importing = false;
  bool _scanning = false;
  bool _hasPermission = false;
  bool _scannedBefore = false;

  @override
  void initState() {
    super.initState();
    _loadIndex();
    _checkPermission();
    _loadScannedFlag();
  }

  Future<void> _loadIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final docs = list.map((e) => LocalDocEntry.fromJson(Map<String, dynamic>.from(e))).toList();
      if (mounted) setState(() => _imported = docs.where((d) => File(d.path).existsSync()).toList());
    } catch (e) {
      debugPrint('Local docs index error: $e');
    }
  }

  Future<void> _saveIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(_imported.map((d) => d.toJson()).toList()));
  }

  Future<void> _loadScannedFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_scannedKey) ?? [];
    if (!mounted) return;
    setState(() {
      _scannedBefore = raw.isNotEmpty;
      _scanned = raw.map((path) => File(path)).where((f) => f.existsSync()).toList();
    });
  }

  Future<void> _saveScannedFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scannedKey, _scanned.map((f) => f.path).toList());
  }

  Future<void> _checkPermission() async {
    // Desktop: no storage permission needed — the OS folder picker is used.
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (mounted) setState(() => _hasPermission = true);
      return;
    }
    // Android 11+: MANAGE_EXTERNAL_STORAGE ("all files access").
    // Android 10 and below: READ_EXTERNAL_STORAGE (legacy).
    if (await Permission.manageExternalStorage.isGranted) {
      if (mounted) setState(() => _hasPermission = true);
      return;
    }
    final legacy = await Permission.storage.isGranted;
    if (mounted) setState(() => _hasPermission = legacy);
  }

  /// One-time access request. Opens the appropriate permission screen.
  Future<void> _requestAccess() async {
    var granted = false;
    if (await Permission.manageExternalStorage.isGranted) {
      granted = true;
    } else if (await Permission.manageExternalStorage.request().isGranted) {
      granted = true;
    } else if (await Permission.storage.request().isGranted) {
      granted = true;
    }
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Device access granted — scanning now...'), backgroundColor: Colors.green),
      );
      _scanDevice();
    } else {
      openAppSettings();
    }
  }

  /// Walks common storage roots (depth-limited) collecting documents.
  Future<void> _scanDevice() async {
    setState(() => _scanning = true);
    final found = <File>[];
    final roots = <String>[
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Android/media',
      '/storage/emulated/0/',
    ];

    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await _walk(dir, found, depth: 0, maxDepth: 8);
    }

    // Dedupe + sort by name
    final seen = <String>{};
    final unique = found.where((f) => seen.add(f.path)).toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _scanned = unique;
      _scanning = false;
    });
    await _saveScannedFlag();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📄 Found ${unique.length} document(s) on this device'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  /// Desktop (Windows/Linux/macOS): pick a folder and scan it instead of
  /// the phone-style whole-device scan.
  Future<void> _pickFolderOnDesktop() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    setState(() => _scanning = true);
    final found = <File>[];
    await _walk(Directory(path), found, depth: 0, maxDepth: 8);
    if (!mounted) return;
    setState(() {
      _scanned = found..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      _scanning = false;
    });
    await _saveScannedFlag();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📄 Found ${found.length} document(s) in that folder'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _walk(Directory dir, List<File> out, {required int depth, required int maxDepth}) async {
    if (depth > maxDepth) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.path.split('/').last.toLowerCase();
          if (name.startsWith('.')) continue;
          // Only these two are truly inaccessible on Android 11+ (scoped
          // storage blocks them even with all-files access). Android/media
          // (e.g. WhatsApp received docs) is readable and must be scanned.
          final lowerPath = entity.path.toLowerCase();
          if (lowerPath.contains('/android/data') || lowerPath.contains('/android/obb')) continue;
          await _walk(entity, out, depth: depth + 1, maxDepth: maxDepth);
        } else if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_docExts.contains(ext)) out.add(entity);
        }
      }
    } catch (e) {
      debugPrint('Scan skip ${dir.path}: $e');
    }
  }

  Future<String> _docsDirectory() async {
    final appDir = await NoteService().getAppDirectory();
    final dir = Directory('$appDir\\local_docs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _importDocs() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    setState(() => _importing = true);
    final dir = await _docsDirectory();
    var added = 0;
    var skipped = 0;

    for (final file in result.files) {
      final sourcePath = file.path;
      if (sourcePath == null) continue;
      final source = File(sourcePath);
      final baseName = p.basename(sourcePath);
      var uniquePath = '$dir\\$baseName';
      var counter = 1;
      while (File(uniquePath).existsSync()) {
        uniquePath = '$dir\\${p.basenameWithoutExtension(baseName)}($counter)${p.extension(baseName)}';
        counter++;
      }
      try {
        await source.copy(uniquePath);
        _imported.add(LocalDocEntry(
          path: uniquePath,
          name: p.basename(uniquePath),
          size: await File(uniquePath).length(),
          addedAt: DateTime.now().toIso8601String(),
        ));
        added++;
      } catch (e) {
        debugPrint('Local doc import failed for $baseName: $e');
        skipped++;
      }
    }

    await _saveIndex();
    if (mounted) {
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(skipped == 0 ? '✅ $added document(s) imported' : '$added imported, $skipped failed'),
          backgroundColor: skipped == 0 ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _removeDoc(LocalDocEntry doc) async {
    try {
      final f = File(doc.path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Local doc delete error: $e');
    }
    setState(() => _imported.removeWhere((d) => d.path == doc.path));
    await _saveIndex();
  }

  /// Explicit per-file donation: user picks year/semester, then the doc is
  /// uploaded to the shared library. Never automatic.
  Future<void> _donateDoc(File file) async {
    int year = 1;
    int semester = 1;
    final picked = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Share to library'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This uploads the document to the shared NotesCache library, visible to everyone. This action is covered by the app\'s Terms of Service.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: year,
                decoration: const InputDecoration(labelText: 'Year level', border: OutlineInputBorder()),
                items: [for (var y = 1; y <= 4; y++) DropdownMenuItem(value: y, child: Text('Year $y'))],
                onChanged: (v) => setState(() => year = v ?? 1),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: semester,
                decoration: const InputDecoration(labelText: 'Semester', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Semester 1')),
                  DropdownMenuItem(value: 2, child: Text('Semester 2')),
                ],
                onChanged: (v) => setState(() => semester = v ?? 1),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, (year, semester)),
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final authService = context.read<AuthService>();
    final noteService = context.read<NoteService>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Uploading to library...'), backgroundColor: Colors.blue));

    final url = await CloudinaryService().uploadFile(
      file: file,
      userId: authService.currentUser?.id ?? 'guest',
      folder: 'donations',
    );
    if (url == null) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Upload failed. Check your connection.'), backgroundColor: Colors.red));
      }
      return;
    }
    final ok = await noteService.saveDonatedNote(
      title: p.basename(file.path),
      lecturerName: authService.currentUser?.fullName ?? 'Student Donation',
      targetYear: picked.$1,
      semester: picked.$2,
      gDriveId: url,
      content: '',
      category: 'Donation',
      fileSize: await file.length(),
      userId: authService.currentUser?.isGuest == true ? null : authService.currentUser?.id,
    );
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '✅ Shared to the library!' : 'Saved to library failed'), backgroundColor: ok ? Colors.green : Colors.red),
      );
    }
  }

  String _fmtSize(int bytes) {
    if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Local Docs', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          bottom: TabBar(
            labelColor: primaryColor,
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
            indicatorColor: primaryColor,
            tabs: const [
              Tab(icon: Icon(Icons.search_rounded, size: 20), text: 'On Device'),
              Tab(icon: Icon(Icons.folder_copy_outlined, size: 20), text: 'Imported'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildScanTab(theme, primaryColor),
            _buildImportedTab(theme, primaryColor),
          ],
        ),
      ),
    );
  }

  // ── TAB 1: Scan the device (open in place, no copies) ──────
  Widget _buildScanTab(ThemeData theme, Color primaryColor) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_open_rounded),
                      SizedBox(width: 10),
                      Expanded(child: Text('Choose a folder on this computer to browse its documents.', style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _scanning ? null : _pickFolderOnDesktop,
                    icon: _scanning
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.folder_open_rounded),
                    label: Text(_scanning ? 'Scanning...' : 'CHOOSE FOLDER'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_scanned.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Pick a folder above — documents appear here and open in the in-app editors.',
                      textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                ),
              )
            else ...[
              Text('${_scanned.length} document(s) found — opened in place, nothing is copied', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(height: 8),
              for (final file in _scanned) _buildScannedTile(theme, primaryColor, file),
            ],
          ] else if (!_hasPermission)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_open_rounded, color: Colors.orange),
                      SizedBox(width: 10),
                      Expanded(child: Text('Connect device storage to find documents scattered across your phone.', style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'One-time setup: Android will ask you to allow "All files access". The app only reads documents (PDF, Word, PowerPoint, Excel, text) — never photos or media. You can revoke this anytime in Android settings.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _requestAccess,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('CONNECT DEVICE STORAGE'),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                const Text('Device access granted', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green, fontSize: 13)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _scanning ? null : _scanDevice,
                  icon: _scanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_scanning ? 'Scanning...' : 'Rescan'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_scanning)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_scanned.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.folder_off_outlined, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                      const SizedBox(height: 12),
                      Text(_scannedBefore ? 'No documents found. Tap Rescan.' : 'Tap "Connect device storage" above, then documents appear here.', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                    ],
                  ),
                ),
              )
            else ...[
              Text('${_scanned.length} document(s) found — opened in place, nothing is copied', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(height: 8),
              for (final file in _scanned) _buildScannedTile(theme, primaryColor, file),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildScannedTile(ThemeData theme, Color primaryColor, File file) {
    final ext = p.extension(file.path).toLowerCase();
    final dirName = file.path.split('/').length > 3 ? file.path.split('/')[file.path.split('/').length - 2] : '';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: theme.dividerColor.withOpacity(0.08))),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Icon(_iconForExt(ext), color: primaryColor),
        ),
        title: Text(p.basename(file.path), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
        subtitle: Text('$dirName • ${_fmtSize(file.lengthSync())}', style: const TextStyle(fontSize: 11)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FileViewerPage(file: file, title: p.basename(file.path))),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          onSelected: (v) {
            if (v == 'donate') _donateDoc(file);
            if (v == 'copy') _copyScanned(file);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'donate', child: Row(children: [Icon(Icons.volunteer_activism_outlined, size: 18), SizedBox(width: 8), Text('Share to library')])),
            PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.save_alt_rounded, size: 18), SizedBox(width: 8), Text('Keep offline copy')])),
          ],
        ),
      ),
    );
  }

  /// Copies a scanned file into the app's private storage (explicit action).
  Future<void> _copyScanned(File file) async {
    final dir = await _docsDirectory();
    final baseName = p.basename(file.path);
    var uniquePath = '$dir\\$baseName';
    var counter = 1;
    while (File(uniquePath).existsSync()) {
      uniquePath = '$dir\\${p.basenameWithoutExtension(baseName)}($counter)${p.extension(baseName)}';
      counter++;
    }
    try {
      await file.copy(uniquePath);
      _imported.add(LocalDocEntry(path: uniquePath, name: p.basename(uniquePath), size: await File(uniquePath).length(), addedAt: DateTime.now().toIso8601String()));
      await _saveIndex();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Offline copy saved (Imported tab)'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── TAB 2: Imported (explicit copies, fully offline) ───────
  Widget _buildImportedTab(ThemeData theme, Color primaryColor) {
    if (_imported.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_copy_outlined, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text('No imported documents', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _importing ? null : _importDocs,
              icon: _importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('IMPORT FILES'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _imported.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: _importing ? null : _importDocs,
              icon: _importing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('IMPORT MORE FILES'),
            ),
          );
        }
        final doc = _imported[index - 1];
        final ext = p.extension(doc.name).toLowerCase();
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: theme.dividerColor.withOpacity(0.08))),
          child: ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: Icon(_iconForExt(ext), color: primaryColor),
            ),
            title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
            subtitle: Text('${_typeLabel(ext)} • ${_fmtSize(doc.size)} • Offline', style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onSurface.withOpacity(0.4), size: 20),
              onPressed: () => _removeDoc(doc),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FileViewerPage(file: File(doc.path), title: doc.name)),
            ),
          ),
        );
      },
    );
  }

  String _typeLabel(String ext) {
    switch (ext) {
      case '.pdf': return 'PDF';
      case '.ppt': case '.pptx': case '.odp': return 'PPT';
      case '.doc': case '.docx': case '.rtf': case '.odt': return 'DOC';
      case '.xls': case '.xlsx': case '.csv': case '.ods': return 'XLS';
      case '.txt': case '.md': return 'TXT';
      default: return 'DOC';
    }
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case '.pdf': return Icons.picture_as_pdf_rounded;
      case '.ppt': case '.pptx': case '.odp': return Icons.slideshow_rounded;
      case '.doc': case '.docx': case '.rtf': case '.odt': return Icons.article_rounded;
      case '.xls': case '.xlsx': case '.csv': case '.ods': return Icons.table_chart_rounded;
      case '.txt': case '.md': return Icons.text_snippet_rounded;
      default: return Icons.description_rounded;
    }
  }
}
