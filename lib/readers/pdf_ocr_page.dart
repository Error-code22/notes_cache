import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// On-device OCR for one PDF page at a time.
///
/// The page is rendered locally with PDFium, recognised locally with ML Kit,
/// and the temporary image is deleted immediately. No page ever leaves the
/// device. Latin script is supported by the bundled recogniser.
class PdfOcrPage extends StatefulWidget {
  final File file;
  final String title;
  final int initialPage;

  const PdfOcrPage({
    super.key,
    required this.file,
    required this.title,
    this.initialPage = 1,
  });

  @override
  State<PdfOcrPage> createState() => _PdfOcrPageState();
}

class _PdfOcrPageState extends State<PdfOcrPage> {
  PdfDocument? _document;
  TextRecognizer? _recognizer;
  int _pageIndex = 0;
  int _totalPages = 0;
  bool _loading = true;
  String? _error;
  String? _text;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _openDocument();
  }

  @override
  void dispose() {
    _generation++;
    _document?.dispose();
    try {
      _recognizer?.close();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _openDocument() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _text = null;
    });
    try {
      final document = await PdfDocument.openFile(widget.file.path);
      if (!mounted || generation != _generation) {
        document.dispose();
        return;
      }
      final pages = document.pages.length;
      if (pages == 0) {
        document.dispose();
        throw const FormatException('This PDF has no pages.');
      }
      setState(() {
        _document = document;
        _totalPages = pages;
        _pageIndex = (widget.initialPage - 1)
            .clamp(0, math.max(0, pages - 1))
            .toInt();
      });
      await _recognize();
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.toLowerCase().contains('password')) {
      return 'This PDF is password-protected. Open it in another app to '
          'unlock it, then try OCR again.';
    }
    return 'Could not read this PDF page.\n\n$text';
  }

  Future<void> _recognize() async {
    final document = _document;
    final recognizer = _recognizer;
    if (document == null || recognizer == null || _totalPages == 0) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _text = null;
    });

    File? temporary;
    try {
      final page = document.pages[_pageIndex];
      final scale = (2200 / math.max(page.width, page.height)).clamp(1.0, 3.0);
      final pdfImage = await page.render(
        fullWidth: (page.width * scale).roundToDouble(),
        fullHeight: (page.height * scale).roundToDouble(),
        backgroundColor: Colors.white,
      );
      if (pdfImage == null) {
        throw StateError('The PDF page could not be rendered.');
      }
      final image = await pdfImage.createImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      pdfImage.dispose();
      image.dispose();
      if (byteData == null) {
        throw StateError('The PDF page could not be encoded.');
      }
      if (!mounted || generation != _generation) return;

      final tempDir = await getTemporaryDirectory();
      temporary = File(
        p.join(
          tempDir.path,
          'foluma_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await temporary.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      final result = await recognizer.processImage(
        InputImage.fromFilePath(temporary.path),
      );
      if (!mounted || generation != _generation) return;
      final text = result.text.trim();
      setState(() {
        _loading = false;
        _text = text;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Could not recognise this page.\n\n$e';
      });
    } finally {
      if (temporary != null) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _copy() async {
    final text = _text;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Text copied')));
    }
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _totalPages || index == _pageIndex) return;
    setState(() => _pageIndex = index);
    _recognize();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              'On-device OCR · Latin script',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy recognised text',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: (_text == null || _text!.isEmpty) ? null : _copy,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPageBar(theme),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildPageBar(ThemeData theme) {
    if (_totalPages == 0) return const SizedBox.shrink();
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous page',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _pageIndex > 0
                    ? () => _goToPage(_pageIndex - 1)
                    : null,
              ),
              Expanded(
                child: Text(
                  'Page ${_pageIndex + 1} of $_totalPages',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _pageIndex < _totalPages - 1
                    ? () => _goToPage(_pageIndex + 1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Reading page ${_pageIndex + 1} on this device…',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
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
                Icons.text_snippet_outlined,
                size: 64,
                color: theme.colorScheme.primary.withOpacity(0.25),
              ),
              const SizedBox(height: 16),
              const Text(
                'OCR could not finish',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
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
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _recognize,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final text = _text ?? '';
    if (text.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.text_fields_rounded,
                size: 72,
                color: theme.colorScheme.primary.withOpacity(0.22),
              ),
              const SizedBox(height: 18),
              const Text(
                'No text found on this page',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Try a page with clearer, larger text. Scans with handwriting or '
                'unusual fonts may not be recognised.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 16, height: 1.6),
      ),
    );
  }
}
