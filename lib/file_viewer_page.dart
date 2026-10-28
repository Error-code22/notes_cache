import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'editors/text_code_editor.dart';
import 'editors/docx_editor_page.dart';
import 'editors/pptx_viewer_page.dart';
import 'editors/spreadsheet_editor.dart';
import 'editors/image_editor_page.dart';
import 'editors/video_player_page.dart';
import 'editors/audio_player_page.dart';
import 'readers/epub_viewer_page.dart';
import 'readers/file_type_detector.dart';
import 'readers/office_viewer_page.dart';
import 'readers/pdf_ocr_page.dart';
import 'readers/pdf_page_tools_page.dart';
import 'readers/signature_pad_page.dart';

enum _FileKind {
  pdf,
  epub,
  text,
  markdown,
  code,
  csv,
  docx,
  pptx,
  xlsx,
  image,
  video,
  audio,
  unsupported,
}

// ─────────────────────────────────────────────────────────────
// Main Viewer/Editor Page — entry point from NoteDetailPage.
// Dispatches to the right editor for every supported format.
// ─────────────────────────────────────────────────────────────
class FileViewerPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const FileViewerPage({
    super.key,
    required this.file,
    required this.title,
    this.onSave,
  });

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late String _extension;
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLandscape = false;

  // PDF search
  bool _searchMode = false;
  final TextEditingController _searchController = TextEditingController();
  PdfTextSearcher? _searcher;
  int _matchIndex = 0;
  int _matchTotal = 0;
  int _pdfReloadKey = 0;

  FileSignature? _signature;
  _FileKind? _kindOverride;

  @override
  void initState() {
    super.initState();
    _extension = p.extension(widget.file.path).toLowerCase();
    _detectSignature();
  }

  Future<void> _detectSignature() async {
    final signature = await FileTypeDetector.detect(widget.file);
    if (!mounted) return;
    _FileKind? override;
    if (signature == FileSignature.pdf && _extension != '.pdf') {
      override = _FileKind.pdf;
    } else if (signature == FileSignature.legacyOffice &&
        ['.pdf', '.docx', '.pptx', '.xlsx'].contains(_extension)) {
      // These formats are ZIP/PDF containers. An OLE header means the file is
      // really a legacy .doc/.ppt/.xls file with a misleading extension.
      override = _FileKind.unsupported;
    }
    setState(() {
      _signature = signature;
      _kindOverride = override;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searcher?.dispose();
    // Reset to portrait when leaving
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    SystemChrome.setPreferredOrientations(
      _isLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  _FileKind get _kind {
    if (_kindOverride != null) return _kindOverride!;
    if (_extension == '.pdf') return _FileKind.pdf;
    if (['.epub'].contains(_extension)) return _FileKind.epub;
    if (['.docx'].contains(_extension)) return _FileKind.docx;
    if (['.pptx'].contains(_extension)) return _FileKind.pptx;
    if (['.xlsx'].contains(_extension)) return _FileKind.xlsx;
    if (['.md', '.markdown'].contains(_extension)) return _FileKind.markdown;
    if ([
      '.py',
      '.java',
      '.cpp',
      '.cc',
      '.c',
      '.h',
      '.dart',
      '.json',
      '.html',
      '.htm',
      '.css',
      '.js',
      '.ts',
      '.sql',
      '.sh',
      '.bash',
      '.yaml',
      '.yml',
      '.xml',
      '.svg',
      '.log',
    ].contains(_extension))
      return _FileKind.code;
    if (['.csv'].contains(_extension)) return _FileKind.csv;
    if (['.txt'].contains(_extension)) return _FileKind.text;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(_extension))
      return _FileKind.image;
    if (['.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v'].contains(_extension))
      return _FileKind.video;
    if (['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac'].contains(_extension))
      return _FileKind.audio;
    return _FileKind.unsupported;
  }

  @override
  Widget build(BuildContext context) {
    switch (_kind) {
      case _FileKind.epub:
        return EpubViewerPage(file: widget.file, title: widget.title);
      case _FileKind.docx:
        if (OfficeViewerPage.isSupportedPlatform) {
          return OfficeViewerPage(
            file: widget.file,
            title: widget.title,
            format: OfficeViewerFormat.docx,
            onSave: widget.onSave,
          );
        }
        return DocxEditorPage(
          file: widget.file,
          title: widget.title,
          onSave: widget.onSave,
        );
      case _FileKind.pptx:
        // Read-only slide text. No third-party PPTX renderer is bundled.
        return PptxViewerPage(file: widget.file, title: widget.title);
      case _FileKind.xlsx:
        if (OfficeViewerPage.isSupportedPlatform) {
          return OfficeViewerPage(
            file: widget.file,
            title: widget.title,
            format: OfficeViewerFormat.xlsx,
            onSave: widget.onSave,
          );
        }
        return SpreadsheetEditorPage(
          file: widget.file,
          title: widget.title,
          onSave: widget.onSave,
        );
      case _FileKind.markdown:
      case _FileKind.text:
      case _FileKind.code:
      case _FileKind.csv:
        return TextCodeEditorPage(
          file: widget.file,
          title: widget.title,
          onSave: widget.onSave,
        );
      case _FileKind.video:
        return VideoPlayerPage(file: widget.file, title: widget.title);
      case _FileKind.audio:
        return AudioPlayerPage(file: widget.file, title: widget.title);
      case _FileKind.image:
        return _buildImageScaffold(context);
      case _FileKind.pdf:
        return _buildPdfScaffold(context);
      case _FileKind.unsupported:
        return _buildUnsupportedScaffold(context);
    }
  }

  // ── IMAGES ────────────────────────────────────────────────
  Widget _buildImageScaffold(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Edit Image',
            icon: Icon(Icons.edit_rounded, color: theme.colorScheme.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageEditorPage(
                  file: widget.file,
                  title: widget.title,
                  onSave: widget.onSave,
                ),
              ),
            ),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: FileImage(widget.file),
        backgroundDecoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
        ),
      ),
    );
  }

  // ── PDF ───────────────────────────────────────────────────
  Widget _buildPdfScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          // Native annotation editor (mobile only)
          if (Platform.isAndroid || Platform.isIOS)
            IconButton(
              tooltip: 'Annotate',
              icon: Icon(Icons.draw_outlined, color: primaryColor),
              onPressed: _annotatePdf,
            ),
          IconButton(
            tooltip: 'Search',
            icon: Icon(Icons.search_rounded, color: primaryColor),
            onPressed: () => setState(() => _searchMode = !_searchMode),
          ),
          _buildPdfMenu(primaryColor),
        ],
      ),
      body: Column(
        children: [
          if (_searchMode) _buildSearchBar(theme, primaryColor),
          Expanded(
            child: Stack(
              children: [
                // Any pointer interaction (tap/scroll) dismisses the search keyboard
                Listener(
                  onPointerDown: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  child: PdfViewer(
                    _ReloadablePdfFileRef(widget.file.path, _pdfReloadKey),
                    key: ValueKey(_pdfReloadKey),
                    controller: _pdfController,
                    params: PdfViewerParams(
                      onDocumentChanged: (doc) =>
                          setState(() => _totalPages = doc?.pages.length ?? 0),
                      onPageChanged: (page) =>
                          setState(() => _currentPage = page ?? 1),
                      backgroundColor: theme.scaffoldBackgroundColor,
                      margin: 16.0,
                      enableTextSelection: true,
                      matchTextColor: Colors.yellow.withAlpha(127),
                      activeMatchTextColor: Colors.orange.withAlpha(160),
                      pagePaintCallbacks: _searcher == null
                          ? null
                          : [_searcher!.pageTextMatchPaintCallback],
                    ),
                  ),
                ),
                _buildPdfControls(theme, primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfMenu(Color primaryColor) {
    final mobile = Platform.isAndroid || Platform.isIOS;
    return PopupMenuButton<String>(
      tooltip: 'More PDF tools',
      icon: Icon(Icons.more_vert_rounded, color: primaryColor),
      onSelected: (value) {
        switch (value) {
          case 'sign':
            _signPdf();
            break;
          case 'ocr':
            _openOcr();
            break;
          case 'pages':
            _openPageTools();
            break;
          case 'gallery':
            _openGallery(_currentPage);
            break;
          case 'orientation':
            _toggleOrientation();
            break;
        }
      },
      itemBuilder: (_) => [
        if (mobile)
          const PopupMenuItem(
            value: 'sign',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.gesture_rounded),
              title: Text('Sign with signature'),
            ),
          ),
        if (mobile)
          const PopupMenuItem(
            value: 'ocr',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.text_snippet_outlined),
              title: Text('Copy text (OCR)'),
            ),
          ),
        const PopupMenuItem(
          value: 'pages',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.auto_stories_outlined),
            title: Text('Page tools'),
          ),
        ),
        const PopupMenuItem(
          value: 'gallery',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.photo_library_rounded),
            title: Text('Page thumbnails'),
          ),
        ),
        PopupMenuItem(
          value: 'orientation',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _isLandscape
                  ? Icons.stay_current_portrait
                  : Icons.stay_current_landscape,
            ),
            title: Text(_isLandscape ? 'Portrait mode' : 'Landscape mode'),
          ),
        ),
      ],
    );
  }

  Future<void> _openOcr() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfOcrPage(
          file: widget.file,
          title: widget.title,
          initialPage: _currentPage,
        ),
      ),
    );
  }

  Future<void> _openPageTools() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPageToolsPage(
          file: widget.file,
          title: widget.title,
          onSave: widget.onSave,
        ),
      ),
    );
    if (mounted) {
      _searcher?.dispose();
      _searcher = null;
      _searchController.clear();
      setState(() {
        _searchMode = false;
        _matchIndex = 0;
        _matchTotal = 0;
        _pdfReloadKey++;
        _totalPages = 0;
        _currentPage = 1;
      });
    }
  }

  Widget _buildSearchBar(ThemeData theme, Color primaryColor) {
    _searcher ??= PdfTextSearcher(_pdfController);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 18,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search in document...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  final searcher = _searcher;
                  if (searcher == null) return;
                  final text = value.trim();
                  if (text.isEmpty) {
                    searcher.resetTextSearch();
                    setState(() => _matchTotal = 0);
                    return;
                  }
                  searcher.startTextSearch(
                    text,
                    caseInsensitive: true,
                    goToFirstMatch: true,
                  );
                  searcher.addListener(_onSearchUpdate);
                },
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _searcher?.startTextSearch(
                      value.trim(),
                      caseInsensitive: true,
                      goToFirstMatch: true,
                    );
                  }
                },
              ),
            ),
            if (_matchTotal > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${_matchIndex + 1}/$_matchTotal',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
              onPressed: () async {
                final idx = await _searcher?.goToPrevMatch();
                if (idx != null && idx >= 0 && mounted)
                  setState(() => _matchIndex = idx);
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
              onPressed: () async {
                final idx = await _searcher?.goToNextMatch();
                if (idx != null && idx >= 0 && mounted)
                  setState(() => _matchIndex = idx);
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Close search',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () {
                _searcher?.resetTextSearch();
                _searchController.clear();
                setState(() {
                  _searchMode = false;
                  _matchTotal = 0;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchUpdate() {
    final s = _searcher;
    if (s == null || !mounted) return;
    var total = 0;
    for (var p = 1; p <= _totalPages; p++) {
      final r = s.getMatchesRangeForPage(p);
      if (r != null) total += r.end - r.start;
    }
    setState(() => _matchTotal = total);
  }

  /// Opens the native PDF annotation editor (pen, highlighter, stamps).
  /// Annotations are saved INTO the PDF, then re-uploaded via [onSave].
  Future<void> _annotatePdf() async {
    await _openPdfEditor(
      title: 'Annotate',
      successMessage: '✅ Annotations saved',
      action: 'annotator',
    );
  }

  /// Opens a signature pad, then hands the PNG signature to the native
  /// annotation editor as an image stamp. The original is backed up first.
  Future<void> _signPdf() async {
    final signature = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignaturePadPage()),
    );
    if (signature == null || !mounted) return;

    await _openPdfEditor(
      title: 'Add signature',
      images: [signature],
      successMessage: 'Signature saved into the PDF',
      action: 'signature editor',
    );
  }

  /// The annotation plugin only permits saving inside its own app files
  /// directory. Shared documents live in the cache, and note attachments can
  /// live elsewhere, so edit a working copy under documents and copy it back.
  Future<File> _pdfWorkingCopy() async {
    // getApplicationSupportDirectory maps to Android's filesDir, which is the
    // only location the annotation plugin accepts for its save path.
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'foluma', 'pdf_working'));
    await dir.create(recursive: true);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(widget.file.path)}';
    return widget.file.copy(p.join(dir.path, name));
  }

  Future<void> _openPdfEditor({
    required String title,
    required String successMessage,
    required String action,
    List<Uint8List>? images,
  }) async {
    await _backupPdf();
    File? working;
    try {
      working = await _pdfWorkingCopy();
      final result = await FlutterPdfAnnotations.openPDF(
        filePath: working.path,
        savePath: working.path,
        config: PDFAnnotationConfig(title: title, imagesToInsert: images),
      );
      if (result.isSuccess) {
        await working.copy(widget.file.path);
        await widget.onSave?.call(widget.file);
        if (!mounted) return;
        _searcher?.dispose();
        _searcher = null;
        setState(() {
          _pdfReloadKey++;
          _totalPages = 0;
          _currentPage = 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result.isError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${title == 'Annotate' ? 'Annotation' : 'Signature'} error: ${result.error}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('$title error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $action: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (working != null) {
        try {
          await working.delete();
        } catch (_) {}
      }
    }
  }

  /// Destructive PDF edits (annotations/signatures) rewrite the file in place.
  /// Keep a local backup so a bad save never destroys the only copy.
  Future<void> _backupPdf() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final backups = Directory(p.join(docs.path, 'foluma', 'pdf_backups'));
      await backups.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final name = '${p.basenameWithoutExtension(widget.file.path)}_$stamp.pdf';
      await widget.file.copy(p.join(backups.path, name));
    } catch (e) {
      debugPrint('PDF backup skipped: $e');
    }
  }

  Widget _buildPdfControls(ThemeData theme, Color primaryColor) {
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: primaryColor.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _currentPage > 1
                    ? () =>
                          _pdfController.goToPage(pageNumber: _currentPage - 1)
                    : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'PAGE $_currentPage / $_totalPages',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _currentPage < _totalPages
                    ? () =>
                          _pdfController.goToPage(pageNumber: _currentPage + 1)
                    : null,
              ),
              const VerticalDivider(width: 20, indent: 8, endIndent: 8),
              IconButton(
                icon: const Icon(Icons.zoom_in_rounded),
                onPressed: () => _pdfController.zoomUp(),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out_rounded),
                onPressed: () => _pdfController.zoomDown(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openGallery(int pageNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfGalleryPage(
          file: widget.file,
          initialPage: pageNumber,
          title: widget.title,
        ),
      ),
    );
  }

  // ── UNSUPPORTED ───────────────────────────────────────────
  Widget _buildUnsupportedScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    String size = '';
    try {
      final bytes = widget.file.lengthSync();
      if (bytes >= 1024 * 1024) {
        size = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else if (bytes >= 1024) {
        size = '${(bytes / 1024).toStringAsFixed(0)} KB';
      } else {
        size = '$bytes bytes';
      }
    } catch (_) {}
    final format = _extension.isEmpty
        ? 'this format'
        : _extension.toUpperCase();
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 80,
                color: primaryColor.withOpacity(0.2),
              ),
              const SizedBox(height: 24),
              const Text(
                'Open this format elsewhere',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$format${size.isEmpty ? '' : ' · $size'}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
              if (_signature != null &&
                  _signature != FileSignature.unknown &&
                  _signature != FileSignature.empty) ...[
                const SizedBox(height: 4),
                Text(
                  'Detected: ${FileTypeDetector.label(_signature!)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Foluma cannot render $_extension on this device yet. Your file is unchanged and stays on this device. Open it in another app, or share it with someone who can.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new),
                label: const Text('OPEN WITH ANOTHER APP'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _shareFile,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share file'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Tip: EPUB, PDF, DOCX, XLSX and PPTX open directly in Foluma.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareFile() async {
    try {
      await Share.shareXFiles([XFile(widget.file.path)], text: widget.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not share file: $e')));
      }
    }
  }

  Future<void> _openExternal() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Process.run('explorer', [widget.file.path], runInShell: true);
      } else if (Platform.isAndroid || Platform.isIOS) {
        // open_filex exposes a content:// URI via FileProvider —
        // raw file:// intents crash Android 7+ (FileUriExposedException)
        final result = await OpenFilex.open(widget.file.path);
        if (mounted && result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.type == ResultType.noAppToOpen
                    ? 'No app installed on this device can open $_extension files.'
                    : 'Could not open externally: ${result.message}',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        final uri = Uri.file(widget.file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('No app can open this file');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open externally: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Full-Screen Gallery — opened when user taps a PDF page
// ─────────────────────────────────────────────────────────────
/// pdfrx caches a loaded document by [PdfDocumentRef] equality. A plain file
/// ref only uses the path, so an edited PDF at the same path can keep showing
/// stale pages until the app restarts. The revision makes each reload a new
/// reference without copying the file.
class _ReloadablePdfFileRef extends PdfDocumentRef {
  final String path;
  final int revision;

  const _ReloadablePdfFileRef(this.path, this.revision);

  @override
  String get sourceName => path;

  @override
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
  ) => PdfDocument.openFile(path);

  @override
  bool operator ==(Object other) =>
      other is _ReloadablePdfFileRef &&
      other.path == path &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(path, revision);
}

class PdfGalleryPage extends StatefulWidget {
  final File file;
  final int initialPage;
  final String title;

  const PdfGalleryPage({
    super.key,
    required this.file,
    required this.initialPage,
    required this.title,
  });

  @override
  State<PdfGalleryPage> createState() => _PdfGalleryPageState();
}

class _PdfGalleryPageState extends State<PdfGalleryPage> {
  late PageController _pageController;
  late int _currentPage;
  bool _isExporting = false;
  bool _isLandscape = false;
  PdfDocument? _document;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage - 1);
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    final doc = await PdfDocument.openFile(widget.file.path);
    if (mounted) setState(() => _document = doc);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _document?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    SystemChrome.setPreferredOrientations(
      _isLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  Future<void> _exportPage() async {
    if (_isExporting || _document == null) return;

    // Ask the user: Image or PDF?
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildExportMenu(),
    );
    if (choice == null) return;

    setState(() => _isExporting = true);
    try {
      final pageIndex = _currentPage - 1;
      final page = _document!.pages[pageIndex];
      final image = await page.render(fullWidth: 2048, fullHeight: 2048);
      final uiImage = await image?.createImage();
      if (uiImage == null) throw Exception('Render failed');

      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Byte conversion failed');

      final tempDir = await getTemporaryDirectory();
      final ext = choice == 'image'
          ? 'png'
          : 'png'; // both save as image for now
      final path =
          '${tempDir.path}/page_${_currentPage}_${widget.title.replaceAll(' ', '_')}.$ext';
      await File(path).writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        await Share.shareXFiles([
          XFile(path, mimeType: 'image/png'),
        ], text: 'Page $_currentPage from "${widget.title}"');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildExportMenu() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Download Page $_currentPage',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose format',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildExportOption(
                Icons.image_rounded,
                'Save as Image',
                '.PNG',
                Colors.blue,
                'image',
              ),
              _buildExportOption(
                Icons.share_rounded,
                'Share Page',
                'Send to...',
                Colors.green,
                'share',
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildExportOption(
    IconData icon,
    String label,
    String sub,
    Color color,
    String value,
  ) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, value),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_document == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final totalPages = _document!.pages.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Page $_currentPage of $totalPages',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isLandscape
                ? 'Switch to Portrait'
                : 'Switch to Landscape',
            icon: Icon(
              _isLandscape
                  ? Icons.stay_current_portrait
                  : Icons.stay_current_landscape,
              color: Colors.white,
            ),
            onPressed: _toggleOrientation,
          ),
          IconButton(
            tooltip: 'Download This Page',
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: _exportPage,
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: totalPages,
            onPageChanged: (index) => setState(() => _currentPage = index + 1),
            itemBuilder: (_, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: PdfPageView(
                    document: _document!,
                    pageNumber: index + 1,
                  ),
                ),
              );
            },
          ),
          // Swipe hint overlay at the bottom
          if (totalPages > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalPages > 20 ? 0 : totalPages, (i) {
                  final isActive = i == _currentPage - 1;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.white30,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
