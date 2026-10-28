import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfrx/pdfrx.dart';

/// Local PDF page tools: rotate, delete and move pages.
///
/// Editing is done by the bundled `pdf_manipulator` engine. The original file
/// is backed up before it is replaced, and every edit stays on the device.
class PdfPageToolsPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const PdfPageToolsPage({
    super.key,
    required this.file,
    required this.title,
    this.onSave,
  });

  @override
  State<PdfPageToolsPage> createState() => _PdfPageToolsPageState();
}

class _PdfPageToolsPageState extends State<PdfPageToolsPage> {
  PdfDocument? _document;
  final List<ui.Image?> _thumbnails = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _generation++;
    _disposeThumbnails();
    _document?.dispose();
    super.dispose();
  }

  void _disposeThumbnails() {
    for (final image in _thumbnails) {
      image?.dispose();
    }
    _thumbnails.clear();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    final oldDocument = _document;
    _document = null;
    _disposeThumbnails();
    await oldDocument?.dispose();

    try {
      final document = await PdfDocument.openFile(widget.file.path);
      if (!mounted || generation != _generation) {
        await document.dispose();
        return;
      }
      _thumbnails.addAll(List<ui.Image?>.filled(document.pages.length, null));
      setState(() {
        _document = document;
        _loading = false;
      });
      _loadThumbnails(document, generation);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this PDF.\n\n$e';
      });
    }
  }

  Future<void> _loadThumbnails(PdfDocument document, int generation) async {
    for (var i = 0; i < document.pages.length; i++) {
      if (!mounted || generation != _generation) return;
      try {
        final page = document.pages[i];
        final width = 140.0;
        final height = width * page.height / page.width;
        final pdfImage = await page.render(
          fullWidth: width,
          fullHeight: height,
          backgroundColor: Colors.white,
        );
        if (pdfImage == null) continue;
        final image = await pdfImage.createImage();
        pdfImage.dispose();
        if (!mounted || generation != _generation) {
          image.dispose();
          return;
        }
        setState(() {
          if (i < _thumbnails.length) _thumbnails[i] = image;
        });
      } catch (_) {
        // A single damaged page must not break the rest of the grid.
      }
      // Let the UI breathe between page renders.
      await Future<void>.delayed(Duration.zero);
    }
  }

  void _toggle(int index) {
    if (_busy) return;
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _selectAll() {
    final count = _document?.pages.length ?? 0;
    setState(() {
      if (_selected.length == count) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(List.generate(count, (index) => index));
      }
    });
  }

  Future<void> _rotateSelected() async {
    if (_selected.isEmpty) return;
    await _apply(rotate: true);
  }

  Future<void> _deleteSelected() async {
    final count = _document?.pages.length ?? 0;
    final selected = _selected.toList()..sort();
    if (selected.isEmpty) return;
    if (selected.length >= count) {
      _showMessage('A PDF must keep at least one page.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete ${selected.length} page${selected.length == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'The pages will be removed from this PDF. A backup of the original '
          'is kept on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _apply(delete: true);
    }
  }

  Future<void> _moveSelected(int delta) async {
    if (_selected.length != 1) return;
    final from = _selected.first;
    final to = from + delta;
    if (to < 0 || to >= (_document?.pages.length ?? 0)) return;
    await _apply(moveFrom: from, moveTo: to);
  }

  Future<void> _apply({
    bool rotate = false,
    bool delete = false,
    int? moveFrom,
    int? moveTo,
  }) async {
    if (_busy) return;
    final selected = _selected.toList()..sort();
    if (selected.isEmpty) return;
    setState(() => _busy = true);
    final temp = await getTemporaryDirectory();
    final output = File(
      p.join(
        temp.path,
        'foluma_page_tools_${DateTime.now().microsecondsSinceEpoch}.pdf',
      ),
    );
    final backup = await _backupOriginal();
    var pdf = Pdf();
    PdfEditor? editor;
    FileSink? sink;
    var replaced = false;
    try {
      editor = await pdf.edit(FileSource(widget.file));
      if (rotate) {
        for (final index in selected) {
          await editor.rotatePage(index, degrees: 90);
        }
      }
      if (delete) {
        for (final index in selected.reversed) {
          await editor.deletePage(index);
        }
      }
      if (moveFrom != null && moveTo != null) {
        await editor.movePage(from: moveFrom, to: moveTo);
      }
      sink = await FileSink.create(output);
      await editor.save(sink);
      await sink.close();
      sink = null;
      await editor.dispose();
      editor = null;
      await pdf.dispose();

      // Close the thumbnail document before replacing the file on disk.
      _generation++;
      final oldDocument = _document;
      _document = null;
      _disposeThumbnails();
      await oldDocument?.dispose();

      await output.copy(widget.file.path);
      replaced = true;
      await widget.onSave?.call(widget.file);
      if (!mounted) return;
      _showMessage(
        rotate
            ? 'Rotated ${selected.length} page${selected.length == 1 ? '' : 's'}'
            : delete
            ? 'Deleted ${selected.length} page${selected.length == 1 ? '' : 's'}'
            : 'Page moved',
      );
      await _reload();
    } catch (e) {
      // If replacing the file failed halfway, restore the backup. A completed
      // replacement is already valid, so it is not rolled back.
      if (!replaced && backup != null) {
        try {
          await File(backup).copy(widget.file.path);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _busy = false;
        });
      }
    } finally {
      await sink?.close();
      await editor?.dispose();
      await pdf.dispose();
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.toLowerCase().contains('password')) {
      return 'This PDF is password-protected. Unlock it in another app before '
          'using page tools.';
    }
    return 'Could not save the page changes.\n\n$text';
  }

  Future<String?> _backupOriginal() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'foluma', 'pdf_backups'));
      await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backup = await widget.file.copy(
        p.join(
          dir.path,
          '${p.basenameWithoutExtension(widget.file.path)}_$stamp.pdf',
        ),
      );
      return backup.path;
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              'Page tools',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
                size: 64,
                color: theme.colorScheme.primary.withOpacity(0.25),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final count = _document?.pages.length ?? 0;
    if (count == 0) {
      return const Center(child: Text('This PDF has no pages.'));
    }
    return Stack(
      children: [
        Column(
          children: [
            _buildSelectionBar(theme, count),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 600
                      ? 5
                      : 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemCount: count,
                itemBuilder: (context, index) => _pageTile(theme, index),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '${_document?.pages.length ?? 0} pages',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : _selectAll,
                      child: Text(
                        _selected.length == count
                            ? 'Clear selection'
                            : 'Select all',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_busy)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionBar(ThemeData theme, int count) {
    if (_selected.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        color: theme.colorScheme.surface,
        child: Text(
          'Tap pages to rotate, delete or reorder them.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.58),
          ),
        ),
      );
    }
    final one = _selected.length == 1;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Row(
          children: [
            Text(
              '${_selected.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Rotate 90°',
              icon: const Icon(Icons.rotate_right_rounded),
              onPressed: _busy ? null : _rotateSelected,
            ),
            IconButton(
              tooltip: 'Move earlier',
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: !_busy && one && _selected.first > 0
                  ? () => _moveSelected(-1)
                  : null,
            ),
            IconButton(
              tooltip: 'Move later',
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: !_busy && one && _selected.first < count - 1
                  ? () => _moveSelected(1)
                  : null,
            ),
            IconButton(
              tooltip: 'Delete pages',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
              onPressed: _busy ? null : _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageTile(ThemeData theme, int index) {
    final selected = _selected.contains(index);
    final image = index < _thumbnails.length ? _thumbnails[index] : null;
    return GestureDetector(
      onTap: _busy ? null : () => _toggle(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null)
                    RawImage(
                      image: image,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.low,
                    )
                  else
                    Center(
                      child: Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 30,
                        color: theme.colorScheme.outline.withOpacity(0.35),
                      ),
                    ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 21,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: theme.colorScheme.surface,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
