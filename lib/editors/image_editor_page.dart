import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Image editor: rotate (90° steps), flip horizontal/vertical, undo.
/// Saves back to the original file as PNG/JPG depending on extension.
class ImageEditorPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const ImageEditorPage({super.key, required this.file, required this.title, this.onSave});

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  img.Image? _original;
  img.Image? _current;
  Uint8List? _displayBytes;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (!mounted) return;
    setState(() {
      _original = decoded;
      _current = decoded;
      _displayBytes = decoded == null ? null : _encodeDisplay(decoded);
      _loading = false;
    });
  }

  /// Encode a downscaled PNG once per edit — was running inside build(),
  /// re-encoding the full image on every setState (rotate/flip = jank).
  Uint8List _encodeDisplay(img.Image image) {
    return Uint8List.fromList(img.encodePng(img.copyResize(image, width: 1600)));
  }

  void _setCurrent(img.Image next) {
    setState(() {
      _current = next;
      _displayBytes = _encodeDisplay(next);
      _dirty = true;
    });
  }

  void _rotateRight() {
    final cur = _current;
    if (cur == null) return;
    _setCurrent(img.copyRotate(cur, angle: -90));
  }

  void _rotateLeft() {
    final cur = _current;
    if (cur == null) return;
    _setCurrent(img.copyRotate(cur, angle: 90));
  }

  void _flipH() {
    final cur = _current;
    if (cur == null) return;
    _setCurrent(img.flipHorizontal(cur));
  }

  void _flipV() {
    final cur = _current;
    if (cur == null) return;
    _setCurrent(img.flipVertical(cur));
  }

  void _undo() {
    setState(() {
      _current = _original;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final cur = _current;
    if (cur == null) return;
    final ext = widget.file.path.split('.').last.toLowerCase();
    final Uint8List bytes;
    if (ext == 'png') {
      bytes = Uint8List.fromList(img.encodePng(cur));
    } else {
      bytes = Uint8List.fromList(img.encodeJpg(cur, quality: 92));
    }
    await widget.file.writeAsBytes(bytes);
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: _dirty ? _undo : null,
          ),
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: _dirty ? _save : null,
          ),
        ],
      ),
      body: _loading || _current == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      maxScale: 6,
                      child: Image.memory(
                        _displayBytes ?? Uint8List(0),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _toolButton(Icons.rotate_left, 'Rotate L', _rotateLeft),
                        _toolButton(Icons.rotate_right, 'Rotate R', _rotateRight),
                        _toolButton(Icons.flip, 'Flip H', _flipH),
                        _toolButton(Icons.flip_to_back, 'Flip V', _flipV),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
