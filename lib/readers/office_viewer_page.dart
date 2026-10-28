import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../editors/docx_editor_page.dart';
import '../editors/spreadsheet_editor.dart';

enum OfficeViewerFormat { docx, xlsx }

/// Offline, read-only Office viewer.
///
/// The document is bundled into a local HTML/JS page and rendered by a
/// sandboxed WebView. No document ever leaves the device and no conversion
/// server is used. Basic DOCX/XLSX text editing remains available through the
/// existing editors, behind an explicit "formatting may be simplified" warning.
class OfficeViewerPage extends StatefulWidget {
  final File file;
  final String title;
  final OfficeViewerFormat format;
  final Future<void> Function(File file)? onSave;

  const OfficeViewerPage({
    super.key,
    required this.file,
    required this.title,
    required this.format,
    this.onSave,
  });

  static bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  State<OfficeViewerPage> createState() => _OfficeViewerPageState();
}

class _OfficeViewerPageState extends State<OfficeViewerPage> {
  WebViewController? _controller;
  Directory? _viewerDir;
  bool _loading = true;
  String? _error;
  bool _editing = false;
  int _loadGeneration = 0;
  Timer? _loadTimeout;

  @override
  void initState() {
    super.initState();
    _prepareViewer();
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    final dir = _viewerDir;
    _viewerDir = null;
    if (dir != null) {
      // Best-effort cleanup. The WebView may still be releasing file handles.
      dir.delete(recursive: true).catchError((_) => dir);
    }
    super.dispose();
  }

  Future<void> _prepareViewer() async {
    _loadTimeout?.cancel();
    final generation = ++_loadGeneration;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cache = await getTemporaryDirectory();
      final root = Directory(p.join(cache.path, 'foluma_office_viewer'));
      await root.create(recursive: true);
      final dir = Directory(
        p.join(
          root.path,
          '${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(widget.file.path)}',
        ),
      );
      await dir.create(recursive: true);

      final bytes = await widget.file.readAsBytes();
      await File(p.join(dir.path, 'data.js')).writeAsString(
        'window.FOLUMA_DATA="${base64Encode(bytes)}";'
        'function folumaBytes(){var b=atob(window.FOLUMA_DATA),a=new Uint8Array(b.length);'
        'for(var i=0;i<b.length;i++)a[i]=b.charCodeAt(i);return a;}',
      );

      if (widget.format == OfficeViewerFormat.docx) {
        await _copyAsset('assets/readers/jszip3.min.js', dir, 'jszip3.min.js');
        await _copyAsset(
          'assets/readers/docx-preview.min.js',
          dir,
          'docx-preview.min.js',
        );
        await _copyAsset('assets/readers/docx_viewer.html', dir, 'viewer.html');
      } else {
        await _copyAsset(
          'assets/readers/xlsx.full.min.js',
          dir,
          'xlsx.full.min.js',
        );
        await _copyAsset('assets/readers/xlsx_viewer.html', dir, 'viewer.html');
      }

      final oldDir = _viewerDir;
      _viewerDir = dir;
      if (oldDir != null && oldDir.path != dir.path) {
        oldDir.delete(recursive: true).catchError((_) => oldDir);
      }

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFF5F5F3))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted && generation == _loadGeneration) {
                setState(() => _loading = true);
              }
            },
            onPageFinished: (_) {
              // The JS channel normally clears this as soon as rendering ends.
              // Keep the spinner up so the user does not see a half-built page.
            },
            onWebResourceError: (error) {
              // Sub-resource failures (for example a missing favicon) must not
              // replace a perfectly rendered document with an error screen.
              final isMainFrame =
                  error.isForMainFrame ??
                  (error.url?.contains('viewer.html') ?? false);
              if (isMainFrame && mounted && generation == _loadGeneration) {
                _loadTimeout?.cancel();
                setState(() {
                  _loading = false;
                  _error = 'Viewer failed to load: ${error.description}';
                });
              }
            },
            onNavigationRequest: (request) {
              // The viewer is a local document. Never let a document link
              // navigate the whole WebView away from the local page.
              if (request.isMainFrame && !request.url.startsWith('file://')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..addJavaScriptChannel(
          'Foluma',
          onMessageReceived: (message) {
            if (!mounted || generation != _loadGeneration) return;
            final value = message.message;
            if (value == 'ready') {
              _loadTimeout?.cancel();
              setState(() {
                _loading = false;
                _error = null;
              });
            } else if (value.startsWith('error:')) {
              _loadTimeout?.cancel();
              setState(() {
                _loading = false;
                _error = value.substring(6);
              });
            }
          },
        );

      if (!mounted || generation != _loadGeneration) return;
      setState(() => _controller = controller);
      await controller.loadFile(p.join(dir.path, 'viewer.html'));

      // A broken/malicious document can make a renderer fail without posting
      // an error. Never leave the user staring at an endless spinner.
      _loadTimeout?.cancel();
      _loadTimeout = Timer(const Duration(seconds: 20), () {
        if (!mounted || generation != _loadGeneration || !_loading) return;
        setState(() {
          _loading = false;
          _error =
              'The viewer took too long to render this file. '
              'It may use a feature that is not supported yet.';
        });
      });
    } catch (e) {
      _loadTimeout?.cancel();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Could not prepare the viewer: $e';
      });
    }
  }

  Future<void> _copyAsset(
    String assetPath,
    Directory dir,
    String fileName,
  ) async {
    final data = await rootBundle.load(assetPath);
    await File(
      p.join(dir.path, fileName),
    ).writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  Future<void> _openExternal() async {
    final result = await OpenFilex.open(widget.file.path);
    if (mounted && result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.type == ResultType.noAppToOpen
                ? 'No app installed on this device can open this file.'
                : 'Could not open externally: ${result.message}',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  bool get _canBasicEdit =>
      widget.onSave != null &&
      (widget.format == OfficeViewerFormat.docx ||
          widget.format == OfficeViewerFormat.xlsx);

  Future<void> _basicEdit() async {
    if (_editing || !_canBasicEdit) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Basic text edit'),
        content: const Text(
          'This editor only preserves text and simple bold/italic formatting. '
          'Images, tables, headers, page layout, formulas and styles may be lost when you save.\n\n'
          'For the original layout, keep the file read-only or use “Open with”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _editing = true);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => widget.format == OfficeViewerFormat.docx
              ? DocxEditorPage(
                  file: widget.file,
                  title: widget.title,
                  onSave: widget.onSave,
                )
              : SpreadsheetEditorPage(
                  file: widget.file,
                  title: widget.title,
                  onSave: widget.onSave,
                ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _editing = false);
        await _prepareViewer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (_canBasicEdit)
            IconButton(
              tooltip: 'Basic text edit',
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: _editing ? null : _basicEdit,
            ),
          IconButton(
            tooltip: 'Open with device',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openExternal,
          ),
        ],
      ),
      body: _error != null
          ? _buildError(theme)
          : Stack(
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!)
                else
                  const SizedBox.expand(),
                if (_loading)
                  ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('Opening document offline…'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 72,
              color: theme.colorScheme.primary.withOpacity(0.25),
            ),
            const SizedBox(height: 18),
            const Text(
              'Could not render this file',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _error ?? 'The document viewer did not finish loading.',
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
                  onPressed: _prepareViewer,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
                FilledButton.icon(
                  onPressed: _openExternal,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open with'),
                ),
                if (_canBasicEdit)
                  TextButton.icon(
                    onPressed: _basicEdit,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Basic text edit'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Everything stays on this device. The viewer is bundled with Foluma; '
              'no document is uploaded.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
