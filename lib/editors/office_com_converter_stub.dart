/// Stub implementation for non-Windows platforms.
/// The real COM converter lives in office_com_converter_windows.dart.
library;

import 'dart:async';

/// Result of a batch conversion run.
class ConvertResult {
  final int converted;
  final int failed;
  final int total;
  final List<String> errors;
  const ConvertResult({
    required this.converted,
    required this.failed,
    required this.total,
    required this.errors,
  });
}

/// Callback for progress updates: (current, total, currentFile).
typedef ProgressCallback = void Function(int current, int total, String fileName);

/// No-op converter for non-Windows platforms.
class OfficeComConverter {
  OfficeComConverter({
    // These params are ignored on non-Windows but accepted for API compatibility.
    dynamic supabase,
    String? functionUrl,
    String? anonKey,
  });

  /// Returns an error — COM conversion is Windows-only.
  Future<ConvertResult> convertBatch({ProgressCallback? onProgress}) async {
    return const ConvertResult(
      converted: 0,
      failed: 0,
      total: 0,
      errors: ['Office COM conversion only works on Windows desktop.'],
    );
  }
}
