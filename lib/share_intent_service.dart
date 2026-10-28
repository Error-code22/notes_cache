import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'file_viewer_page.dart';
import 'services.dart';

/// Receives documents shared into Foluma from Android's Open-with / Share
/// sheet. The native side copies the content URI into the app cache so the
/// existing offline reader can open it.
class SharedDocument {
  final String path;
  final String name;
  const SharedDocument({required this.path, required this.name});
}

class ShareIntentService {
  static const MethodChannel _channel = MethodChannel('foluma/intents');
  static bool _started = false;
  static bool _opening = false;
  static bool _openedFromShare = false;

  /// True when this launch was caused by an Open-with / Share intent. The
  /// dashboard uses it to avoid stacking update dialogs over the document.
  static bool get openedFromShare => _openedFromShare;

  /// Reads the document that launched the app, before [runApp]. The caller
  /// adds it as an initial route so opening it cannot race the first frame.
  static Future<SharedDocument?> takeInitialDocument() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPendingDocument',
      );
      final path = result?['path'] as String?;
      if (path == null) return null;
      _openedFromShare = true;
      return SharedDocument(
        path: path,
        name: result?['name'] as String? ?? 'Shared document',
      );
    } on PlatformException catch (e) {
      debugPrint('Could not read shared document: ${e.message}');
      return null;
    }
  }

  static Future<void> init() async {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedDocumentAvailable') {
        await _openPending();
      }
      return null;
    });
  }

  static Future<void> _openPending() async {
    if (_opening) return;
    final navigator = NotificationService.navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openPending());
      });
      return;
    }

    _opening = true;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPendingDocument',
      );
      if (result == null) return;
      final path = result['path'] as String?;
      final name = result['name'] as String? ?? 'Shared document';
      if (path == null) return;

      final current = NotificationService.navigatorKey.currentState;
      if (current == null || !current.mounted) return;
      _openedFromShare = true;
      // Do not await push: its future only completes when the document is
      // closed, which would block every later share for the whole session.
      unawaited(
        current.push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (context, animation, secondaryAnimation) =>
                FileViewerPage(file: File(path), title: name),
          ),
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Could not open shared document: ${e.message}');
      final context = NotificationService.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Could not open that document.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      _opening = false;
    }
  }
}
