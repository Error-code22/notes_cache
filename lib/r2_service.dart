import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudinaryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _functionUrl => '${dotenv.env['SUPABASE_URL']}/functions/v1';

  /// Upload a file to Cloudinary via edge function
  /// Returns the public URL of the uploaded file, or null on failure
  Future<String?> uploadFile({
    required File file,
    required String userId,
    String folder = 'notes',
    Function(double)? onProgress,
  }) async {
    try {
      onProgress?.call(0.0);

      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileBytes = await file.readAsBytes();

      // Create multipart form data
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_functionUrl/cloudinary-upload'),
      );

      // Add headers
      request.headers.addAll({
        'apikey': dotenv.env['SUPABASE_ANON_KEY'] ?? '',
        'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken ?? dotenv.env['SUPABASE_ANON_KEY'] ?? ''}',
      });

      // Add file
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      );
      request.files.add(multipartFile);

      // Add metadata
      request.fields['folder'] = folder;
      request.fields['userId'] = userId;

      onProgress?.call(0.3);

      // Send request
      final streamedResponse = await request.send();

      onProgress?.call(0.8);

      // Parse response
      final response = await streamedResponse.stream.bytesToString();
      final jsonResponse = Map<String, dynamic>.from(
        const JsonDecoder().convert(response) as Map,
      );

      onProgress?.call(1.0);

      if (jsonResponse['success'] == true) {
        debugPrint('CloudinaryService: Upload successful - ${jsonResponse['url']}');
        return jsonResponse['url'] as String?;
      } else {
        debugPrint('CloudinaryService: Upload failed - ${jsonResponse['error']}');
        return null;
      }
    } catch (e) {
      debugPrint('CloudinaryService: Upload error - $e');
      return null;
    }
  }

  /// Delete a file from Cloudinary by public_id
  Future<bool> deleteFile(String publicId) async {
    try {
      final response = await _supabase.functions.invoke(
        'cloudinary-delete',
        body: {'publicId': publicId},
      );

      return response.data['success'] == true;
    } catch (e) {
      debugPrint('CloudinaryService: Delete error - $e');
      return false;
    }
  }

  /// Extract the public_id from a Cloudinary URL
  static String? extractPublicIdFromUrl(String url) {
    try {
      // Cloudinary URLs: https://res.cloudinary.com/{cloud}/image/upload/v1234/folder/file.ext
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      // Find 'upload' index and get everything after it
      final uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex + 1 >= pathSegments.length) return null;
      
      // Skip version number if present (v1234...)
      final startIndex = pathSegments[uploadIndex + 1].startsWith('v') 
          ? uploadIndex + 2 
          : uploadIndex + 1;
      
      if (startIndex >= pathSegments.length) return null;
      
      // Join remaining path segments (without extension)
      final pathParts = pathSegments.sublist(startIndex);
      final fullPath = pathParts.join('/');
      
      // Remove file extension
      final lastDot = fullPath.lastIndexOf('.');
      return lastDot > 0 ? fullPath.substring(0, lastDot) : fullPath;
    } catch (e) {
      return null;
    }
  }
}
