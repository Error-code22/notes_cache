/// Windows-only COM automation for converting Office documents to PDF.
/// Uses PowerShell subprocess for COM interop — no special packages needed.
/// Requires Microsoft Office installed on the machine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Converts Office documents (PPTX, DOCX, Publisher) to PDF using
/// Microsoft Office COM automation via PowerShell. Windows-only.
class OfficeComConverter {
  final SupabaseClient _supabase;
  final String _functionUrl;
  final String _anonKey;

  OfficeComConverter({
    SupabaseClient? supabase,
    String? functionUrl,
    String? anonKey,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _functionUrl = functionUrl ??
            '${const String.fromEnvironment('SUPABASE_URL')}/functions/v1',
        _anonKey = anonKey ??
            const String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Convert all pending PPTX/DOCX/Publisher notes that lack a pdf_url.
  Future<ConvertResult> convertBatch({ProgressCallback? onProgress}) async {
    if (!Platform.isWindows) {
      return const ConvertResult(
        converted: 0, failed: 0, total: 0,
        errors: ['Office COM conversion only works on Windows.'],
      );
    }

    final notes = await _fetchPendingNotes();
    if (notes.isEmpty) {
      return const ConvertResult(converted: 0, failed: 0, total: 0, errors: []);
    }

    final errors = <String>[];
    var converted = 0;
    var failed = 0;
    final total = notes.length;

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final idx = i + 1;
      final title = note['title'] as String? ?? 'Untitled';
      final category = (note['category'] as String?)?.toLowerCase() ?? '';
      onProgress?.call(idx, total, title);

      try {
        if (category == 'slides' || title.endsWith('.pptx') || title.endsWith('.ppt')) {
          await _convertWithPowerPoint(note);
        } else if (category == 'document' || title.endsWith('.docx') || title.endsWith('.doc')) {
          await _convertWithWord(note);
        } else if (category == 'publisher' || title.endsWith('.pub')) {
          await _convertWithPublisher(note);
        } else {
          failed++;
          errors.add('$title: Unknown format');
          continue;
        }
        converted++;
      } catch (e) {
        failed++;
        errors.add('$title: $e');
        debugPrint('OfficeComConverter: Failed "$title": $e');
      }
    }

    return ConvertResult(converted: converted, failed: failed, total: total, errors: errors);
  }

  // ─── PowerPoint ───────────────────────────────────────────────

  Future<void> _convertWithPowerPoint(Map<String, dynamic> note) async {
    final noteId = note['id'] as String;
    final originalUrl = note['gdrive_id'] as String?;
    if (originalUrl == null || originalUrl.isEmpty) throw Exception('No file URL');

    final tempDir = Directory.systemTemp;
    final tempPptx = File(p.join(tempDir.path, '$noteId.pptx'));
    await _downloadFile(originalUrl, tempPptx);
    final tempPdf = File(p.join(tempDir.path, '$noteId.pdf'));

    try {
      // PowerShell script: open PPTX, save as PDF, close
      final script = '''
\$pptx = '${tempPptx.path.replaceAll("'", "''")}'
\$pdf = '${tempPdf.path.replaceAll("'", "''")}'
\$app = New-Object -ComObject PowerPoint.Application
\$app.Visible = [Microsoft.Office.Interop.MsoTriState]::msoTrue
\$pres = \$app.Presentations.Open(\$pptx, \$true, \$false, \$false)
\$pres.SaveAs(\$pdf, 32)
\$pres.Close()
\$app.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$pres) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$app) | Out-Null
''';

      final result = await Process.run(
        'powershell', ['-NoProfile', '-NonInteractive', '-Command', script],
      );

      if (result.exitCode != 0) {
        throw Exception('PowerPoint failed: ${result.stderr}');
      }

      final pdfUrl = await _uploadPdf(tempPdf, noteId);
      if (pdfUrl != null) await _updateNotePdfUrl(noteId, pdfUrl);
    } finally {
      await _deleteTemp(tempPptx);
      await _deleteTemp(tempPdf);
    }
  }

  // ─── Word (DOCX) ─────────────────────────────────────────────

  Future<void> _convertWithWord(Map<String, dynamic> note) async {
    final noteId = note['id'] as String;
    final originalUrl = note['gdrive_id'] as String?;
    if (originalUrl == null || originalUrl.isEmpty) throw Exception('No file URL');

    final tempDir = Directory.systemTemp;
    final tempDocx = File(p.join(tempDir.path, '$noteId.docx'));
    await _downloadFile(originalUrl, tempDocx);
    final tempPdf = File(p.join(tempDir.path, '$noteId.pdf'));

    try {
      final script = '''
\$docx = '${tempDocx.path.replaceAll("'", "''")}'
\$pdf = '${tempPdf.path.replaceAll("'", "''")}'
\$app = New-Object -ComObject Word.Application
\$app.Visible = \$false
\$doc = \$app.Documents.Open(\$docx, \$true)
\$doc.SaveAs([ref]\$pdf, 17)
\$doc.Close()
\$app.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$doc) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$app) | Out-Null
''';

      final result = await Process.run(
        'powershell', ['-NoProfile', '-NonInteractive', '-Command', script],
      );

      if (result.exitCode != 0) {
        throw Exception('Word failed: ${result.stderr}');
      }

      final pdfUrl = await _uploadPdf(tempPdf, noteId);
      if (pdfUrl != null) await _updateNotePdfUrl(noteId, pdfUrl);
    } finally {
      await _deleteTemp(tempDocx);
      await _deleteTemp(tempPdf);
    }
  }

  // ─── Publisher ────────────────────────────────────────────────

  Future<void> _convertWithPublisher(Map<String, dynamic> note) async {
    final noteId = note['id'] as String;
    final originalUrl = note['gdrive_id'] as String?;
    if (originalUrl == null || originalUrl.isEmpty) throw Exception('No file URL');

    final tempDir = Directory.systemTemp;
    final tempPub = File(p.join(tempDir.path, '$noteId.pub'));
    await _downloadFile(originalUrl, tempPub);
    final tempPdf = File(p.join(tempDir.path, '$noteId.pdf'));

    try {
      final script = '''
\$pubFile = '${tempPub.path.replaceAll("'", "''")}'
\$pdf = '${tempPdf.path.replaceAll("'", "''")}'
\$app = New-Object -ComObject Publisher.Application
\$app.Open(\$pubFile)
Start-Sleep -Seconds 1
\$app.ActiveDocument.ExportAsFixedFormat(2, \$pdf)
Start-Sleep -Milliseconds 500
\$app.ActiveDocument.Close()
\$app.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject(\$app) | Out-Null
''';

      final result = await Process.run(
        'powershell', ['-NoProfile', '-NonInteractive', '-Command', script],
      );

      if (result.exitCode != 0) {
        throw Exception('Publisher failed: ${result.stderr}');
      }

      final pdfUrl = await _uploadPdf(tempPdf, noteId);
      if (pdfUrl != null) await _updateNotePdfUrl(noteId, pdfUrl);
    } finally {
      await _deleteTemp(tempPub);
      await _deleteTemp(tempPdf);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchPendingNotes() async {
    try {
      final response = await _supabase
          .from('notes')
          .select('id, title, gdrive_id, category')
          .isFilter('pdf_url', null)
          .inFilter('category', ['Slides', 'Document', 'Publisher']);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('OfficeComConverter: fetchPendingNotes error: $e');
      return [];
    }
  }

  Future<void> _downloadFile(String url, File dest) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      await dest.writeAsBytes(bytes);
    } finally {
      client.close();
    }
  }

  Future<String?> _uploadPdf(File pdfFile, String noteId) async {
    try {
      final session = _supabase.auth.currentSession;
      final token = session?.accessToken ?? _anonKey;
      final request = http.MultipartRequest('POST', Uri.parse('$_functionUrl/cloudinary-upload'));
      request.headers.addAll({'apikey': _anonKey, 'Authorization': 'Bearer $token'});
      request.files.add(await http.MultipartFile.fromPath('file', pdfFile.path));
      request.fields['folder'] = 'notes';
      request.fields['userId'] = 'office_com_converter';
      final streamed = await request.send();
      final response = await streamed.stream.bytesToString();
      final json = Map<String, dynamic>.from(const JsonDecoder().convert(response) as Map);
      if (json['success'] == true) return json['url'] as String?;
      return null;
    } catch (e) {
      debugPrint('OfficeComConverter: uploadPdf error: $e');
      return null;
    }
  }

  Future<void> _updateNotePdfUrl(String noteId, String pdfUrl) async {
    try {
      await _supabase.from('notes').update({'pdf_url': pdfUrl}).eq('id', noteId);
    } catch (e) {
      debugPrint('OfficeComConverter: updateNotePdfUrl error: $e');
    }
  }

  Future<void> _deleteTemp(File file) async {
    try { if (await file.exists()) await file.delete(); } catch (_) {}
  }
}
