import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/python.dart' as l_python;
import 'package:highlight/languages/java.dart' as l_java;
import 'package:highlight/languages/cpp.dart' as l_cpp;
import 'package:highlight/languages/dart.dart' as l_dart;
import 'package:highlight/languages/json.dart' as l_json;
import 'package:highlight/languages/xml.dart' as l_xml;
import 'package:highlight/languages/css.dart' as l_css;
import 'package:highlight/languages/javascript.dart' as l_js;
import 'package:highlight/languages/typescript.dart' as l_ts;
import 'package:highlight/languages/sql.dart' as l_sql;
import 'package:highlight/languages/bash.dart' as l_bash;
import 'package:highlight/languages/yaml.dart' as l_yaml;

/// Text / Markdown / Code editor.
/// - `.md` opens in markdown view with an edit toggle.
/// - code files open with syntax highlighting and a monospace font.
/// - plain text files open in a simple editor.
class TextCodeEditorPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const TextCodeEditorPage({super.key, required this.file, required this.title, this.onSave});

  @override
  State<TextCodeEditorPage> createState() => _TextCodeEditorPageState();
}

class _TextCodeEditorPageState extends State<TextCodeEditorPage> {
  late String _extension;
  bool _isEditing = false;
  bool _viewMarkdown = true;
  CodeController? _codeController;
  TextEditingController? _plainController;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _extension = widget.file.path.split('.').last.toLowerCase();
    _load();
  }

  @override
  void dispose() {
    _codeController?.dispose();
    _plainController?.dispose();
    super.dispose();
  }

  Mode? get _languageMode {
    switch (_extension) {
      case 'py': return l_python.python;
      case 'java': return l_java.java;
      case 'cpp': case 'cc': case 'c': case 'h': return l_cpp.cpp;
      case 'dart': return l_dart.dart;
      case 'html': case 'htm': case 'xml': case 'svg': return l_xml.xml;
      case 'json': return l_json.json;
      case 'css': return l_css.css;
      case 'js': return l_js.javascript;
      case 'ts': return l_ts.typescript;
      case 'sql': return l_sql.sql;
      case 'sh': case 'bash': return l_bash.bash;
      case 'yaml': case 'yml': return l_yaml.yaml;
      default: return null;
    }
  }

  bool get _isCode => !['txt', 'md', 'markdown', 'csv', 'log'].contains(_extension);
  bool get _isMarkdown => ['md', 'markdown'].contains(_extension);
  bool get _isCsv => _extension == 'csv';

  Future<void> _load() async {
    final content = await widget.file.readAsString();
    if (!mounted) return;
    setState(() {
      if (_isCode) {
        _codeController = CodeController(text: content, language: _languageMode);
      } else {
        _plainController = TextEditingController(text: content);
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final text = _isCode ? _codeController!.text : _plainController!.text;
    await widget.file.writeAsString(text);
    _dirty = false;
    await widget.onSave?.call(widget.file);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Saved'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = !_isMarkdown || !_viewMarkdown;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isMarkdown)
            IconButton(
              tooltip: _viewMarkdown ? 'Edit' : 'Preview',
              icon: Icon(_viewMarkdown ? Icons.edit_outlined : Icons.visibility_outlined),
              onPressed: () {
                setState(() {
                  _viewMarkdown = !_viewMarkdown;
                  _isEditing = false;
                });
              },
            ),
          if (canEdit)
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.save_outlined),
              onPressed: _dirty ? _save : null,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isMarkdown && _viewMarkdown) {
      final text = (_codeController ?? _plainController)!.text;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(data: text),
      );
    }

    final fontFamily = _isCode ? 'monospace' : null;

    if (_isCode && _codeController != null) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: CodeField(
                controller: _codeController!,
                textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                onChanged: (t) => _dirty = true,
              ),
            ),
          ),
          if (_isCsv) _csvTable(theme, _codeController!.text),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _plainController,
        style: TextStyle(fontFamily: fontFamily, fontSize: 15, height: 1.5),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(8),
        ),
        onChanged: (_) => _dirty = true,
      ),
    );
  }

  Widget _csvTable(ThemeData theme, String text) {
    // RFC 4180 parsing: handles commas inside quotes ("Nairobi, Kenya"),
    // escaped quotes, and multiline quoted cells.
    final List<List<dynamic>> rows;
    try {
      rows = Csv(skipEmptyLines: true, dynamicTyping: false).decode(text);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final visible = rows.take(50).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 240,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.length > visible.length)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Showing first ${visible.length} of ${rows.length} rows', style: theme.textTheme.bodySmall),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Table(
                border: TableBorder.all(color: theme.dividerColor, width: 0.5),
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  for (var i = 0; i < visible.length; i++)
                    TableRow(
                      decoration: i == 0 ? BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.08)) : null,
                      children: [
                        for (final c in visible[i])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(c.toString(), style: TextStyle(fontSize: 12, fontWeight: i == 0 ? FontWeight.bold : null)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
