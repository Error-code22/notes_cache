import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'editors/text_code_editor.dart';
import 'editors/rich_text_editor.dart';
import 'editors/docx_editor_page.dart';
import 'editors/pptx_viewer_page.dart';
import 'editors/spreadsheet_editor.dart';
import 'editors/image_editor_page.dart';
import 'editors/video_player_page.dart';
import 'editors/audio_player_page.dart';

enum _FileKind { pdf, text, markdown, code, csv, docx, pptx, xlsx, image, video, audio, unsupported }

// ─────────────────────────────────────────────────────────────
// Main Viewer/Editor Page — entry point from NoteDetailPage.
// Dispatches to the right editor for every supported format.
// ─────────────────────────────────────────────────────────────
class FileViewerPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const FileViewerPage({super.key, required this.file, required this.title, this.onSave});

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late String _extension;
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    _extension = p.extension(widget.file.path).toLowerCase();
  }

  @override
  void dispose() {
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
    if (_extension == '.pdf') return _FileKind.pdf;
    if (['.docx'].contains(_extension)) return _FileKind.docx;
    if (['.pptx', '.ppt'].contains(_extension)) return _FileKind.pptx;
    if (['.xlsx'].contains(_extension)) return _FileKind.xlsx;
    if (['.md', '.markdown'].contains(_extension)) return _FileKind.markdown;
    if (['.py', '.java', '.cpp', '.cc', '.c', '.h', '.dart', '.json', '.html', '.htm', '.css', '.js', '.ts', '.sql', '.sh', '.bash', '.yaml', '.yml', '.xml', '.svg', '.log'].contains(_extension)) return _FileKind.code;
    if (['.csv'].contains(_extension)) return _FileKind.csv;
    if (['.txt'].contains(_extension)) return _FileKind.text;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(_extension)) return _FileKind.image;
    if (['.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v'].contains(_extension)) return _FileKind.video;
    if (['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac'].contains(_extension)) return _FileKind.audio;
    return _FileKind.unsupported;
  }

  @override
  Widget build(BuildContext context) {
    switch (_kind) {
      case _FileKind.docx:
        return DocxEditorPage(file: widget.file, title: widget.title, onSave: widget.onSave);
      case _FileKind.pptx:
        return PptxViewerPage(file: widget.file, title: widget.title);
      case _FileKind.xlsx:
        return SpreadsheetEditorPage(file: widget.file, title: widget.title, onSave: widget.onSave);
      case _FileKind.markdown:
      case _FileKind.text:
      case _FileKind.code:
      case _FileKind.csv:
        return TextCodeEditorPage(file: widget.file, title: widget.title, onSave: widget.onSave);
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
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Edit Image',
            icon: Icon(Icons.edit_rounded, color: theme.colorScheme.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageEditorPage(file: widget.file, title: widget.title, onSave: widget.onSave),
              ),
            ),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: FileImage(widget.file),
        backgroundDecoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
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
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Gallery Mode',
            icon: Icon(Icons.photo_library_rounded, color: primaryColor),
            onPressed: () => _openGallery(_currentPage),
          ),
          IconButton(
            tooltip: _isLandscape ? 'Switch to Portrait' : 'Switch to Landscape',
            icon: Icon(
              _isLandscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
              color: primaryColor,
            ),
            onPressed: _toggleOrientation,
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer.file(
            widget.file.path,
            controller: _pdfController,
            params: PdfViewerParams(
              onDocumentChanged: (doc) => setState(() => _totalPages = doc?.pages.length ?? 0),
              onPageChanged: (page) => setState(() => _currentPage = page ?? 1),
              backgroundColor: theme.scaffoldBackgroundColor,
              margin: 16.0,
            ),
          ),
          _buildPdfControls(theme, primaryColor),
        ],
      ),
    );
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
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
            border: Border.all(color: primaryColor.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _currentPage > 1 ? () => _pdfController.goToPage(pageNumber: _currentPage - 1) : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text('PAGE $_currentPage / $_totalPages',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _currentPage < _totalPages ? () => _pdfController.goToPage(pageNumber: _currentPage + 1) : null,
              ),
              const VerticalDivider(width: 20, indent: 8, endIndent: 8),
              IconButton(icon: const Icon(Icons.zoom_in_rounded), onPressed: () => _pdfController.zoomUp()),
              IconButton(icon: const Icon(Icons.zoom_out_rounded), onPressed: () => _pdfController.zoomDown()),
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 80, color: primaryColor.withOpacity(0.2)),
              const SizedBox(height: 24),
              const Text('Unsupported format', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                'This format ($_extension) cannot be opened inside the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new),
                label: const Text('OPEN WITH DEVICE VIEWER'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              content: Text(result.type == ResultType.noAppToOpen
                  ? 'No app installed on this device can open $_extension files.'
                  : 'Could not open externally: ${result.message}'),
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
          SnackBar(content: Text('Could not open externally: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Full-Screen Gallery — opened when user taps a PDF page
// ─────────────────────────────────────────────────────────────
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
      final ext = choice == 'image' ? 'png' : 'png'; // both save as image for now
      final path = '${tempDir.path}/page_${_currentPage}_${widget.title.replaceAll(' ', '_')}.$ext';
      await File(path).writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        await Share.shareXFiles(
          [XFile(path, mimeType: 'image/png')],
          text: 'Page $_currentPage from "${widget.title}"',
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildExportMenu() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Download Page $_currentPage', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Choose format', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildExportOption(Icons.image_rounded, 'Save as Image', '.PNG', Colors.blue, 'image'),
              _buildExportOption(Icons.share_rounded, 'Share Page', 'Send to...', Colors.green, 'share'),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildExportOption(IconData icon, String label, String sub, Color color, String value) {
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
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
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
            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            Text('Page $_currentPage of $totalPages', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isLandscape ? 'Switch to Portrait' : 'Switch to Landscape',
            icon: Icon(
              _isLandscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
              color: Colors.white,
            ),
            onPressed: _toggleOrientation,
          ),
          IconButton(
            tooltip: 'Download This Page',
            icon: _isExporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
