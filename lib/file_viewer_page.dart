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

// ─────────────────────────────────────────────────────────────
// Main Viewer Page — entry point from NoteDetailPage
// ─────────────────────────────────────────────────────────────
class FileViewerPage extends StatefulWidget {
  final File file;
  final String title;

  const FileViewerPage({super.key, required this.file, required this.title});

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late String _extension;
  bool _isEditing = false;
  late TextEditingController _textController;
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    _extension = p.extension(widget.file.path).toLowerCase();
    _textController = TextEditingController();
    if (_isTextFile()) _loadTextContent();
  }

  @override
  void dispose() {
    _textController.dispose();
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

  bool _isTextFile() => ['.txt', '.md', '.py', '.java', '.cpp', '.dart', '.json', '.html', '.csv'].contains(_extension);
  bool _isPdf() => _extension == '.pdf';
  bool _isImage() => ['.jpg', '.jpeg', '.png'].contains(_extension);

  Future<void> _loadTextContent() async {
    final content = await widget.file.readAsString();
    if (mounted) setState(() => _textController.text = content);
  }

  Future<void> _saveTextContent() async {
    await widget.file.writeAsString(_textController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Changes saved locally')));
      setState(() => _isEditing = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (_isTextFile())
            IconButton(
              icon: Icon(_isEditing ? Icons.save_rounded : Icons.edit_rounded, color: primaryColor),
              onPressed: () => _isEditing ? _saveTextContent() : setState(() => _isEditing = true),
            ),
          if (_isPdf()) ...[
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
        ],
      ),
      body: Stack(
        children: [
          _buildViewer(theme, primaryColor),
          if (_isPdf()) _buildPdfControls(theme, primaryColor),
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

  Widget _buildViewer(ThemeData theme, Color primaryColor) {
    if (_isPdf()) {
      return PdfViewer.file(
        widget.file.path,
        controller: _pdfController,
        params: PdfViewerParams(
          onDocumentChanged: (doc) => setState(() => _totalPages = doc?.pages.length ?? 0),
          onPageChanged: (page) => setState(() => _currentPage = page ?? 1),
          backgroundColor: theme.scaffoldBackgroundColor,
          margin: 16.0,
        ),
      );
    } else if (_isImage()) {
      return PhotoView(
        imageProvider: FileImage(widget.file),
        backgroundDecoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      );
    } else if (_isTextFile()) {
      if (_isEditing) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _textController,
            maxLines: null,
            expands: true,
            style: TextStyle(color: theme.colorScheme.onSurface, fontFamily: 'monospace'),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Start writing...'),
          ),
        );
      } else {
        return Markdown(
          data: _textController.text,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, height: 1.6),
            h1: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
            h2: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
            code: TextStyle(backgroundColor: primaryColor.withOpacity(0.1), fontFamily: 'monospace'),
          ),
        );
      }
    } else {
      final isOffice = _extension.contains(RegExp(r'\.(doc|docx|ppt|pptx|xls|xlsx)$'));
      final isMedia = _extension.contains(RegExp(r'\.(mp4|mp3|wav|mov|mkv|m4a)$'));
      
      IconData icon = Icons.insert_drive_file_outlined;
      String typeTitle = 'Unsupported format';
      String typeDesc = 'This format ($_extension) cannot be viewed inside the app.';

      if (isOffice) {
        icon = Icons.description_rounded;
        typeTitle = 'Office Document';
        typeDesc = 'Word, Excel, and PowerPoint files must be opened in their native apps.';
      } else if (isMedia) {
        icon = Icons.play_circle_fill_rounded;
        typeTitle = 'Media File';
        typeDesc = 'Audio and video files should be played using your device\'s media player.';
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 80, color: theme.colorScheme.primary.withOpacity(0.2)),
              const SizedBox(height: 24),
              Text(typeTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                typeDesc,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('GO BACK & USE DEVICE VIEWER'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
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
