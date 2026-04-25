import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveAuthService {
  final _clientId = ClientId(
    dotenv.env['GOOGLE_DRIVE_CLIENT_ID']!,
    dotenv.env['GOOGLE_DRIVE_CLIENT_SECRET']!,
  );

  final _scopes = [drive.DriveApi.driveFileScope];

  AuthClient? _client;

  Future<bool> authenticate() async {
    try {
      // This will open a browser window for you to sign in
      _client = await clientViaUserConsent(_clientId, _scopes, (url) {
        launchUrl(Uri.parse(url));
      });
      return _client != null;
    } catch (e) {
      print('Error during Google Auth: $e');
      return false;
    }
  }

  Future<String?> uploadFile(File file, String fileName, {String? folderId}) async {
    if (_client == null) return null;

    try {
      final driveApi = drive.DriveApi(_client!);
      final driveFile = drive.File();
      driveFile.name = fileName;
      if (folderId != null) {
        driveFile.parents = [folderId];
      }

      final media = drive.Media(file.openRead(), file.lengthSync());
      final response = await driveApi.files.create(driveFile, uploadMedia: media);
      
      // Make publicly viewable
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
}
