import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class DriveService {
  static const _scopes = [drive.DriveApi.driveFileScope];

  Future<AuthClient> _getAuthClient() async {
    final String jsonString = await rootBundle.loadString('service_account.json');
    final accountCredentials = ServiceAccountCredentials.fromJson(jsonString);
    return clientViaServiceAccount(accountCredentials, _scopes);
  }

  Future<String?> uploadFile(File file, String fileName, {String? folderId}) async {
    try {
      final client = await _getAuthClient();
      final driveApi = drive.DriveApi(client);

      final driveFile = drive.File();
      driveFile.name = fileName;
      if (folderId != null) {
        driveFile.parents = [folderId];
      }

      final media = drive.Media(file.openRead(), file.lengthSync());
      final response = await driveApi.files.create(driveFile, uploadMedia: media);

      // Make the file publicly viewable so students can read it
      await driveApi.permissions.create(
        drive.Permission()
          ..type = 'anyone'
          ..role = 'reader',
        response.id!,
      );

      return response.id;
    } catch (e) {
      print('Error uploading to Drive: $e');
      return null;
    }
  }

  Future<String?> getDownloadUrl(String fileId) async {
    // Note: For Service Account files, we can construct a direct preview link
    return 'https://drive.google.com/uc?export=view&id=$fileId';
  }
}
