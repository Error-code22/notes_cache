import 'dart:io';
import 'package:flutter/material.dart';
import 'office_pptx.dart';

/// PPTX viewer: renders extracted slide text, one slide at a time.
class PptxViewerPage extends StatefulWidget {
  final File file;
  final String title;

  const PptxViewerPage({super.key, required this.file, required this.title});

  @override
  State<PptxViewerPage> createState() => _PptxViewerPageState();
}

class _PptxViewerPageState extends State<PptxViewerPage> {
  List<List<String>>? _slides;
  int _current = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (await PptxService.isBinaryPpt(widget.file)) {
        if (mounted) setState(() {
          _error = 'This is an old binary .ppt file (Office 97-2003). In-app reading supports the newer .pptx format. Use the device default viewer for this file.';
          _loading = false;
        });
        return;
      }
      final slides = await PptxService.readSlides(widget.file);
      if (!mounted) return;
      setState(() {
        _slides = slides;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Could not read presentation:\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Export text',
            icon: const Icon(Icons.download_outlined),
            onPressed: _slides == null ? null : _exportText,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not read presentation:\n$_error', textAlign: TextAlign.center))
              : (_slides == null || _slides!.isEmpty)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No readable slides found.\n\nThis deck may have no text content (e.g. images-only slides), or it may be an old binary .ppt file. Try the device default viewer.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            itemCount: _slides!.length,
                            onPageChanged: (i) => setState(() => _current = i),
                            itemBuilder: (context, i) => _buildSlide(theme, _slides![i], i),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            border: Border(top: BorderSide(color: theme.dividerColor)),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: _current > 0
                                      ? () {
                                          final c = _current - 1;
                                          setState(() => _current = c);
                                        }
                                      : null,
                                ),
                                Expanded(
                                  child: Text(
                                    'Slide ${_current + 1} of ${_slides!.length}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: _current < _slides!.length - 1
                                      ? () {
                                          final c = _current + 1;
                                          setState(() => _current = c);
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildSlide(ThemeData theme, List<String> blocks, int index) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
      ),
      child: blocks.isEmpty
          ? Center(
              child: Text(
                'Slide ${index + 1}\n(no text content)',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < blocks.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        blocks[i],
                        style: i == 0
                            ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
                            : theme.textTheme.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _exportText() async {
    try {
      final markdown = await PptxService.toMarkdown(widget.file);
      final exportFile = File('${widget.file.path}.txt');
      await exportFile.writeAsString(markdown);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Exported to ${exportFile.path.split('/').last.split('\\').last}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
