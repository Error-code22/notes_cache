import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'epub_parser.dart';

/// Offline EPUB reader.
///
/// EPUBs are local ZIP packages. We parse the spine and inline the book's
/// images/CSS, then render one chapter at a time in a WebView. No network
/// access is required, and no book content is uploaded.
class EpubViewerPage extends StatefulWidget {
  final File file;
  final String title;

  const EpubViewerPage({super.key, required this.file, required this.title});

  @override
  State<EpubViewerPage> createState() => _EpubViewerPageState();
}

class _EpubViewerPageState extends State<EpubViewerPage> {
  EpubBookData? _book;
  bool _loading = true;
  bool _chapterLoading = false;
  String? _error;
  int _chapterIndex = 0;
  double _fontScale = 1.0;
  WebViewController? _controller;
  int _loadGeneration = 0;
  final Set<int> _bookmarks = {};
  String? _bookmarkKey;
  String? _positionKey;

  bool get _canUseWebView => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_canUseWebView) {
      _controller = _createController();
    }
    _loadBook();
  }

  WebViewController _createController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFFFAFAF7))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _chapterLoading = false);
          },
          onNavigationRequest: (request) {
            // The reader is local. Links inside a book must not navigate the
            // WebView to a remote site. External links can still be opened by
            // the host app later, but are intentionally inert for now.
            final url = request.url;
            if (url.startsWith('about:') ||
                url.startsWith('data:') ||
                url.startsWith('file:')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );
  }

  Future<void> _loadBook() async {
    final generation = ++_loadGeneration;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _chapterLoading = false;
      _error = null;
    });
    try {
      final bytes = await widget.file.readAsBytes();
      final book = EpubParser.parse(bytes, fallbackTitle: widget.title);
      final prefs = await SharedPreferences.getInstance();
      final fileKey = '${p.basename(widget.file.path)}:${bytes.length}';
      final bookmarkKey = 'foluma.epub.bookmarks.v1:$fileKey';
      final positionKey = 'foluma.epub.position.v1:$fileKey';
      final saved = prefs.getStringList(bookmarkKey) ?? const [];
      final savedScale = prefs.getDouble('foluma.epub.fontScale');
      final savedPosition = prefs.getInt(positionKey) ?? 0;
      final restored = savedPosition.clamp(0, book.chapters.length - 1).toInt();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _book = book;
        _chapterIndex = restored;
        _loading = false;
        _bookmarkKey = bookmarkKey;
        _positionKey = positionKey;
        if (savedScale != null) {
          _fontScale = savedScale.clamp(0.8, 1.6).toDouble();
        }
        _bookmarks
          ..clear()
          ..addAll(saved.map((value) => int.tryParse(value)).whereType<int>());
      });
      await _showChapter(restored);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('DRM') || text.contains('encrypted')) {
      return 'This EPUB appears to be DRM-protected, so it cannot be opened '
          'inside Foluma. Use “Open with” to read it in another app.';
    }
    return 'Could not open this EPUB. The file may be damaged or use a '
        'feature Foluma does not support yet.\n\n$text';
  }

  Future<void> _showChapter(int index) async {
    final book = _book;
    if (book == null || index < 0 || index >= book.chapters.length) return;
    final positionKey = _positionKey;
    if (positionKey != null) {
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt(positionKey, index),
      );
    }
    if (!_canUseWebView || _controller == null) {
      setState(() => _chapterIndex = index);
      return;
    }
    setState(() {
      _chapterIndex = index;
      _chapterLoading = true;
    });
    final html = _buildDocument(book.chapters[index].html);
    try {
      await _controller!.loadHtmlString(html);
    } catch (e) {
      if (mounted) {
        setState(() {
          _chapterLoading = false;
          _error = 'Could not render this chapter: $e';
        });
      }
    }
  }

  String _buildDocument(String chapterHtml) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? '#111214' : '#FAFAF7';
    final foreground = dark ? '#E8E6E0' : '#17181A';
    final muted = dark ? '#A6A39B' : '#5F6368';
    final accent = dark ? '#FFC53D' : '#9A6500';
    final fontSize = (18 * _fontScale).toStringAsFixed(1);
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; media-src data:; connect-src 'none'; object-src 'none'; frame-src 'none';">
</head>
<body>
$chapterHtml
<style>
  html, body {
    margin: 0 !important; padding: 0 !important;
    width: 100%; max-width: 100%; overflow-x: hidden;
    background: $background !important;
  }
  body {
    color: $foreground !important;
    font-family: Georgia, "Times New Roman", serif;
    font-size: ${fontSize}px !important;
    line-height: 1.72;
    -webkit-text-size-adjust: 100%;
  }
  .epub-content {
    width: 100%; max-width: 760px; margin: 0 auto;
    padding: 22px 20px 54px; box-sizing: border-box;
    color: $foreground;
    font-size: ${fontSize}px;
    overflow-wrap: anywhere;
  }
  .epub-content * { max-width: 100% !important; box-sizing: border-box; }
  .epub-content p, .epub-content li { overflow-wrap: anywhere; }
  .epub-content p { margin: 0 0 1.05em; }
  .epub-content h1, .epub-content h2, .epub-content h3,
  .epub-content h4, .epub-content h5, .epub-content h6 {
    line-height: 1.25; margin: 1.35em 0 .55em;
  }
  .epub-content img, .epub-content svg, .epub-content video {
    max-width: 100% !important; height: auto !important;
  }
  .epub-content table {
    border-collapse: collapse; max-width: 100%; display: block; overflow-x: auto;
  }
  .epub-content td, .epub-content th { border: 1px solid $muted; padding: 5px 7px; }
  .epub-content pre, .epub-content code {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: .86em;
  }
  .epub-content pre { overflow-x: auto; padding: 12px; background: ${dark ? '#1B1C1F' : '#F0F0EB'}; border-radius: 8px; }
  .epub-content blockquote {
    margin: 1em 0; padding: .2em 0 .2em 1em;
    border-left: 3px solid $accent; color: $muted;
  }
  .epub-content a { color: $accent !important; }
  .epub-content hr { border: 0; border-top: 1px solid $muted; opacity: .35; margin: 1.8em 0; }
</style>
</body>
</html>
''';
  }

  Future<void> _openExternal() async {
    final result = await OpenFilex.open(widget.file.path);
    if (mounted && result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.type == ResultType.noAppToOpen
                ? 'No app installed on this device can open this EPUB.'
                : 'Could not open externally: ${result.message}',
          ),
        ),
      );
    }
  }

  Future<void> _toggleBookmark() async {
    final key = _bookmarkKey;
    if (key == null) return;
    setState(() {
      if (!_bookmarks.remove(_chapterIndex)) {
        _bookmarks.add(_chapterIndex);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordered = _bookmarks.toList()..sort();
      await prefs.setStringList(key, ordered.map((index) => '$index').toList());
    } catch (_) {
      // A bookmark is a convenience; it must never block reading.
    }
  }

  Future<void> _openToc() async {
    final book = _book;
    if (book == null) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: book.chapters.length,
            itemBuilder: (context, index) {
              final isCurrent = index == _chapterIndex;
              return ListTile(
                dense: true,
                selected: isCurrent,
                leading: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                title: Text(
                  book.chapters[index].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: _bookmarks.contains(index)
                    ? Icon(
                        Icons.bookmark_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(context, index),
              );
            },
          ),
        );
      },
    );
    if (selected != null && selected != _chapterIndex) {
      await _showChapter(selected);
    }
  }

  Future<void> _openTextSettings() async {
    var draft = _fontScale;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Reading text size'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(draft * 100).round()}%'),
                Slider(
                  value: draft,
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  label: '${(draft * 100).round()}%',
                  onChanged: (value) => setDialogState(() => draft = value),
                ),
                const Text(
                  'Images, tables and chapter styling are preserved.',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _fontScale = draft);
                  Navigator.pop(context);
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setDouble('foluma.epub.fontScale', draft),
                  );
                  _showChapter(_chapterIndex);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = _book;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              book?.title ?? widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (book != null && book.author.isNotEmpty)
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _bookmarks.contains(_chapterIndex)
                ? 'Remove bookmark'
                : 'Bookmark this chapter',
            icon: Icon(
              _bookmarks.contains(_chapterIndex)
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
            onPressed: book == null ? null : _toggleBookmark,
          ),
          IconButton(
            tooltip: 'Contents',
            icon: const Icon(Icons.format_list_numbered_rounded),
            onPressed: book == null ? null : _openToc,
          ),
          IconButton(
            tooltip: 'Text size',
            icon: const Icon(Icons.text_fields_rounded),
            onPressed: book == null ? null : _openTextSettings,
          ),
        ],
      ),
      body: _buildBody(theme, book),
    );
  }

  Widget _buildBody(ThemeData theme, EpubBookData? book) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Opening book offline…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 72,
                color: theme.colorScheme.primary.withOpacity(0.25),
              ),
              const SizedBox(height: 18),
              const Text(
                'Could not open this book',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadBook,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  FilledButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open with'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (book == null || book.chapters.isEmpty) {
      return const Center(child: Text('This EPUB has no readable chapters.'));
    }

    if (!_canUseWebView || _controller == null) {
      return _buildFallbackReader(book);
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller!),
              if (_chapterLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
        _buildChapterBar(theme, book),
      ],
    );
  }

  Widget _buildChapterBar(ThemeData theme, EpubBookData book) {
    final canPrevious = _chapterIndex > 0;
    final canNext = _chapterIndex < book.chapters.length - 1;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous chapter',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: canPrevious
                    ? () => _showChapter(_chapterIndex - 1)
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.chapters[_chapterIndex].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_chapterIndex + 1} of ${book.chapters.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next chapter',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: canNext
                    ? () => _showChapter(_chapterIndex + 1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackReader(EpubBookData book) {
    final text = book.chapters[_chapterIndex].html
        .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 17, height: 1.6),
            ),
          ),
        ),
        _buildChapterBar(Theme.of(context), book),
      ],
    );
  }
}
