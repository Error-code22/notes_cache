import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The asset record returned by the `note-upload` Edge Function.
class StoredAsset {
  final String assetId;
  final String provider;
  final String key;
  final String url;
  final int size;

  const StoredAsset({
    required this.assetId,
    required this.provider,
    required this.key,
    required this.url,
    required this.size,
  });

  factory StoredAsset.fromMap(Map<String, dynamic> map) {
    return StoredAsset(
      assetId: (map['asset_id'] ?? map['assetId'] ?? '').toString(),
      provider: (map['provider'] ?? 'r2').toString(),
      key: (map['key'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      size: (map['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Uploads note/donation originals through the storage Edge Functions.
///
/// R2 is the primary store; the Edge Function may fall back to Cloudinary for
/// documents. Telegram backup is requested per upload and must stay off for
/// private notes.
class NoteStorageService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _supabaseUrl {
    final raw = dotenv.env['SUPABASE_URL'] ?? '';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String get _anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Uploads [file] and attaches it to an existing note or donation row.
  ///
  /// Exactly one of [noteId] and [donationId] must be provided; the Edge
  /// Function verifies that the caller may write that row.
  Future<StoredAsset?> uploadFile({
    required File file,
    required String userId,
    String? noteId,
    String? donationId,
    bool telegramBackup = true,
    void Function(double)? onProgress,
  }) async {
    if (noteId == null && donationId == null) {
      debugPrint('NoteStorageService: noteId or donationId is required.');
      return null;
    }
    if (_supabaseUrl.isEmpty || _anonKey.isEmpty) {
      debugPrint('NoteStorageService: Supabase URL/key are not configured.');
      return null;
    }

    final session = _supabase.auth.currentSession;
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      debugPrint('NoteStorageService: no signed-in session for upload.');
      return null;
    }

    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final totalBytes = await file.length();
      if (totalBytes <= 0) {
        debugPrint('NoteStorageService: refusing to upload an empty file.');
        return null;
      }

      onProgress?.call(0);

      var sentBytes = 0;
      final countedStream = file.openRead().transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            sentBytes += data.length;
            final fraction = (sentBytes / totalBytes).clamp(0.0, 1.0);
            onProgress?.call(fraction * 0.9);
            sink.add(data);
          },
        ),
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_supabaseUrl/functions/v1/note-upload'),
      );
      request.headers.addAll({
        'apikey': _anonKey,
        'Authorization': 'Bearer $token',
      });
      request.fields['kind'] = 'original';
      request.fields['telegram_backup'] = telegramBackup ? 'true' : 'false';
      if (noteId != null) request.fields['note_id'] = noteId;
      if (donationId != null) request.fields['donation_id'] = donationId;

      request.files.add(
        http.MultipartFile(
          'file',
          countedStream,
          totalBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await request
          .send()
          .timeout(const Duration(minutes: 10));
      onProgress?.call(0.92);

      final body = await streamedResponse.stream
          .bytesToString()
          .timeout(const Duration(minutes: 2));

      if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
        debugPrint(
          'NoteStorageService: upload failed HTTP ${streamedResponse.statusCode}: $body',
        );
        return null;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        debugPrint('NoteStorageService: unexpected upload response: $body');
        return null;
      }

      var payload = Map<String, dynamic>.from(decoded);
      // Tolerate a `{ data: {...} }` wrapper without changing the contract.
      if (payload['data'] is Map) {
        payload = Map<String, dynamic>.from(payload['data'] as Map);
      }

      final asset = StoredAsset.fromMap(payload);
      if (asset.assetId.isEmpty) {
        debugPrint('NoteStorageService: response had no asset_id: $body');
        return null;
      }

      onProgress?.call(1);
      debugPrint(
        'NoteStorageService: uploaded ${asset.assetId} via ${asset.provider} '
        'for ${noteId != null ? 'note $noteId' : 'donation $donationId'} '
        '(user $userId, ${asset.size} bytes)',
      );
      return asset;
    } catch (e) {
      debugPrint('NoteStorageService: upload error: $e');
      return null;
    }
  }

  /// Downloads the note's original bytes, following every storage fallback.
  ///
  /// R2 and Cloudinary are fetched directly from their short-lived URLs, while
  /// Telegram-backed files are streamed chunk by chunk from `note-file` with
  /// the caller's token (a bare URL cannot authenticate to that endpoint).
  Future<List<int>?> downloadNoteBytes(String noteId) async {
    if (_supabaseUrl.isEmpty || _anonKey.isEmpty) return null;
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;

    final headers = {
      'apikey': _anonKey,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    try {
      final metaResponse = await http
          .post(
            Uri.parse('$_supabaseUrl/functions/v1/note-file'),
            headers: headers,
            body: jsonEncode({'note_id': noteId}),
          )
          .timeout(const Duration(seconds: 60));
      if (metaResponse.statusCode != 200) {
        debugPrint(
          'NoteStorageService: file metadata failed HTTP ${metaResponse.statusCode}: ${metaResponse.body}',
        );
        return null;
      }

      final decoded = jsonDecode(metaResponse.body);
      if (decoded is! Map) return null;
      final meta = Map<String, dynamic>.from(decoded);

      final direct = meta['url'];
      if (direct is String && direct.isNotEmpty) {
        final response =
            await http.get(Uri.parse(direct)).timeout(const Duration(seconds: 120));
        if (response.statusCode != 200) {
          debugPrint('NoteStorageService: direct file fetch HTTP ${response.statusCode}');
          return null;
        }
        return response.bodyBytes;
      }

      final downloadUrl = meta['download_url'];
      final chunks = meta['chunks'];
      if (downloadUrl is String && downloadUrl.isNotEmpty) {
        final authHeaders = {
          'apikey': _anonKey,
          'Authorization': 'Bearer $token',
        };

        // A single proxied R2 object (Cloudflare REST fallback) has no chunk
        // list; the URL itself streams the whole file with authentication.
        if (chunks is! List || chunks.isEmpty) {
          final response = await http
              .get(Uri.parse(downloadUrl), headers: authHeaders)
              .timeout(const Duration(minutes: 5));
          if (response.statusCode != 200) {
            debugPrint(
              'NoteStorageService: proxied file fetch HTTP ${response.statusCode}',
            );
            return null;
          }
          return response.bodyBytes;
        }

        final ordered = List<Map<String, dynamic>>.from(
          chunks.whereType<Map>().map((c) => Map<String, dynamic>.from(c)),
        )..sort(
            (a, b) => ((a['chunk_index'] as num?)?.toInt() ?? 0)
                .compareTo((b['chunk_index'] as num?)?.toInt() ?? 0),
          );
        final builder = BytesBuilder(copy: false);
        final base = Uri.parse(downloadUrl);
        for (final chunk in ordered) {
          final index = (chunk['chunk_index'] as num?)?.toInt() ?? 0;
          final uri = base.replace(queryParameters: {
            ...base.queryParameters,
            'chunk': '$index',
          });
          final response = await http
              .get(uri, headers: authHeaders)
              .timeout(const Duration(seconds: 180));
          if (response.statusCode != 200) {
            debugPrint(
              'NoteStorageService: Telegram chunk $index HTTP ${response.statusCode}',
            );
            return null;
          }
          builder.add(response.bodyBytes);
        }
        return builder.takeBytes();
      }
      return null;
    } catch (e) {
      debugPrint('NoteStorageService: download error: $e');
      return null;
    }
  }

  /// Returns a signed/fallback URL for a note's original file.
  Future<String?> getFileUrl(String noteId) async {
    try {
      final response = await _supabase.functions.invoke(
        'note-file',
        body: {'note_id': noteId},
      );

      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final url = map['url'] ?? map['download_url'];
        if (url is String && url.isNotEmpty) return url;
      }
      return null;
    } catch (e) {
      debugPrint('NoteStorageService: getFileUrl error: $e');
      return null;
    }
  }
}
