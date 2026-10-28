import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A small, offline signature pad. The signature is returned as a PNG so it can
/// be placed on a PDF as an image stamp by the native annotation editor.
class SignaturePadPage extends StatefulWidget {
  const SignaturePadPage({super.key});

  @override
  State<SignaturePadPage> createState() => _SignaturePadPageState();
}

class _SignaturePadPageState extends State<SignaturePadPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;
  bool _saving = false;

  void _start(Offset point) {
    setState(() {
      _current = [point];
      _strokes.add(_current!);
    });
  }

  void _update(Offset point) {
    if (_current == null) return;
    setState(() => _current!.add(point));
  }

  void _end() {
    setState(() => _current = null);
  }

  Future<void> _clear() async {
    if (_strokes.isEmpty) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear signature?'),
        content: const Text('This removes the strokes you have drawn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true) {
      setState(() {
        _strokes.clear();
        _current = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _strokes.isEmpty) {
      if (_strokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draw your signature first.')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Signature canvas is not ready.');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode the signature.');
      if (!mounted) return;
      Navigator.pop(context, data.buffer.asUint8List());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save signature: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Draw signature',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Use'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sign with your finger, then tap Use. In the PDF editor, '
                      'tap Image to place the stamp on a page.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) => _start(details.localPosition),
                    onPanUpdate: (details) => _update(details.localPosition),
                    onPanEnd: (_) => _end(),
                    child: SizedBox.expand(
                      child: CustomPaint(painter: _SignaturePainter(_strokes)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _strokes.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Clear'),
                  ),
                  const Spacer(),
                  Text(
                    'Black ink · transparent PNG',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) {
      final hint = TextPainter(
        text: const TextSpan(
          text: 'Sign here',
          style: TextStyle(
            color: Color(0xFFB8B8B0),
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hint.paint(
        canvas,
        Offset((size.width - hint.width) / 2, (size.height - hint.height) / 2),
      );
      return;
    }
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
