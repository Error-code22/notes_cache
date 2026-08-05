import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Rich text editor built on flutter_quill.
/// Works on plain text / markdown-ish content:
/// loads the file's text into the editor and saves the document
/// back as text (one line per paragraph).
class RichTextEditorPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const RichTextEditorPage({super.key, required this.file, required this.title, this.onSave});

  @override
  State<RichTextEditorPage> createState() => _RichTextEditorPageState();
}

class _RichTextEditorPageState extends State<RichTextEditorPage> {
  QuillController? _controller;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final text = await widget.file.readAsString();
    if (!mounted) return;
    setState(() {
      final doc = Document()
        ..insert(0, _textToDelta(text));
      _controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _loading = false;
    });
  }

  /// Converts plain text (paragraphs on separate lines) into Quill ops.
  List<Map<String, dynamic>> _textToDelta(String text) {
    final lines = text.split('\n');
    final ops = <Map<String, dynamic>>[];
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        ops.add({'insert': '\n'});
        continue;
      }
      // Headings: # / ## / ### -> header blocks
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        ops.add({'insert': heading.group(2)! + '\n', 'attributes': {'header': level}});
        continue;
      }
      // Bold: **text** -> bold. Keep inline markers stripped.
      final bold = RegExp(r'^\*\*(.*)\*\*$').firstMatch(trimmed);
      if (bold != null) {
        ops.add({'insert': bold.group(1)! + '\n', 'attributes': {'bold': true}});
        continue;
      }
      ops.add({'insert': trimmed + '\n'});
    }
    return ops;
  }

  Future<void> _save() async {
    final doc = _controller!.document;
    // Build text from blocks, preserving headings/bold where simple
    final lines = <String>[];
    final iter = doc.root.children.iterator;
    while (iter.moveNext()) {
      final block = iter.current;
      final text = block.toPlainText().replaceFirst(RegExp(r'\n$'), '');
      final attrs = block.style?.attributes;
      final header = attrs?['header']?.value;
      if (header != null && header != 1) {
        lines.add('${'#' * (header as int)} $text');
      } else {
        lines.add(text);
      }
    }
    await widget.file.writeAsString(lines.join('\n'));
    _dirty = false;
    await widget.onSave?.call(widget.file);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Saved'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: _dirty && _controller != null ? _save : null,
          ),
        ],
      ),
      body: _loading || _controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                QuillSimpleToolbar(
                  controller: _controller!,
                  config: QuillSimpleToolbarConfig(
                    showAlignmentButtons: false,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showFontSize: false,
                    showFontFamily: false,
                    showDirection: false,
                    showCodeBlock: true,
                    showIndent: false,
                    showListCheck: true,
                    showHeaderStyle: false,
                    showLink: false,
                    showSearchButton: false,
                    showInlineCode: true,
                    showSubscript: false,
                    showSuperscript: false,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: QuillEditor.basic(
                    controller: _controller!,
                    config: QuillEditorConfig(
                      placeholder: 'Start typing...',
                      autoFocus: true,
                      expands: true,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
