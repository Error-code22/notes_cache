import 'dart:io';
import 'package:flutter/material.dart';
import 'office_docx.dart';

/// DOCX editor: loads the document's text (with **bold** / _italic_ markers),
/// lets the user edit it, and rebuilds a real .docx on save.
class DocxEditorPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const DocxEditorPage({super.key, required this.file, required this.title, this.onSave});

  @override
  State<DocxEditorPage> createState() => _DocxEditorPageState();
}

class _DocxEditorPageState extends State<DocxEditorPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final paragraphs = await DocxService.readParagraphs(widget.file);
      final text = DocxService.paragraphsToText(paragraphs);
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    try {
      final paragraphs = DocxService.textToParagraphs(_controller.text);
      final bytes = DocxService.buildDocx(paragraphs);
      await widget.file.writeAsBytes(bytes);
      _dirty = false;
      await widget.onSave?.call(widget.file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Saved as .docx'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
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
            onPressed: _dirty && !_loading ? _save : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not read document:\n$_error\n\nTip: this may not be a valid .docx file.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(8),
                          ),
                          onChanged: (_) => _dirty = true,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
