import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ProgressStream extends StreamView<List<int>> {
  final int totalBytes;
  final Function(double) onProgress;
  int _bytesSent = 0;

  ProgressStream(Stream<List<int>> inner, this.totalBytes, this.onProgress) : super(inner);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return super.listen(
      (data) {
        _bytesSent += data.length;
        onProgress(_bytesSent / totalBytes);
        if (onData != null) onData(data);
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

// ATTN: Fixed Windows Auth logic to use correct obtainAccessCredentialsViaUserConsent.
// clientViaUserPrompt does not exist in googleapis_auth 1.6.0.

class GoogleDriveAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  Future<drive.DriveApi?> _getDriveApi() async {
    if (!kIsWeb && Platform.isWindows) {
      return _getWindowsDriveApi();
    }
    
    try {
      debugPrint('DriveAuth: Getting Drive API (Mobile/Web)...');
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      
      if (account == null) {
        debugPrint('DriveAuth: No active account in memory, trying silent sign-in...');
        account = await _googleSignIn.signInSilently();
      }

      if (account == null) {
        debugPrint('DriveAuth: Silent sign-in failed, prompting interactive sign-in...');
        account = await _googleSignIn.signIn();
      }

      if (account == null) {
        debugPrint('DriveAuth: Interactive sign-in cancelled or failed.');
        return null;
      }

      debugPrint('DriveAuth: Authenticated as ${account.email}');
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        debugPrint('DriveAuth: Failed to get authenticated client.');
        return null;
      }

      return drive.DriveApi(authClient);
    } catch (e) {
      debugPrint('DriveAuth: Critical error in _getDriveApi: $e');
      return null;
    }
  }

  Future<drive.DriveApi?> _getWindowsDriveApi() async {
    try {
      debugPrint('DriveAuth: Getting Drive API for Windows...');
      final clientId = gauth.ClientId(
        dotenv.env['GOOGLE_DRIVE_CLIENT_ID']!,
        dotenv.env['GOOGLE_DRIVE_CLIENT_SECRET']!,
      );
      final scopes = [drive.DriveApi.driveFileScope];

      final prefs = await SharedPreferences.getInstance();
      final tokenJson = prefs.getString('google_drive_token');
      
      if (tokenJson != null) {
        try {
          debugPrint('DriveAuth: Found stored token, trying to refresh...');
          final credentials = gauth.AccessCredentials.fromJson(jsonDecode(tokenJson));
          
          // Check if we can actually use this token or refresh it
          if (credentials.accessToken.hasExpired && credentials.refreshToken == null) {
            debugPrint('DriveAuth: Stored token expired and no refresh token available. Clearing...');
            await prefs.remove('google_drive_token');
          } else {
            final client = gauth.autoRefreshingClient(clientId, credentials, http.Client());
            return drive.DriveApi(client);
          }
        } catch (e) {
          debugPrint('DriveAuth: Error restoring stored token: $e');
          await prefs.remove('google_drive_token');
        }
      }

      debugPrint('DriveAuth: No stored token, prompting user in browser...');
      
      final httpClient = http.Client();
      final credentials = await gauth.obtainAccessCredentialsViaUserConsent(
        clientId, 
        scopes, 
        httpClient, 
        (url) async {
          debugPrint('DriveAuth: Opening browser for auth: $url');
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          } else {
            throw 'Could not launch $url';
          }
        },
      );

      final authClient = gauth.authenticatedClient(httpClient, credentials);

      // Store the credentials for next time
      await prefs.setString('google_drive_token', jsonEncode(credentials.toJson()));
      debugPrint('DriveAuth: Windows authentication successful and token stored.');
      
      return drive.DriveApi(authClient);
    } catch (e) {
      debugPrint('DriveAuth: Windows Auth Error: $e');
      return null;
    }
  }

  Future<String?> _getOrCreateFolder(drive.DriveApi api, String folderName) async {
    try {
      final query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final list = await api.files.list(q: query);
      
      if (list.files != null && list.files!.isNotEmpty) {
        return list.files!.first.id;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';
      
      final response = await api.files.create(folder);
      return response.id;
    } catch (e) {
      debugPrint('DriveAuth: Error creating folder $folderName: $e');
      return null;
    }
  }

  Future<bool> authenticate() async {
    final api = await _getDriveApi();
    return api != null;
  }

  Future<String?> uploadProfilePhoto(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    return uploadFile(file, 'Profile_$fileName');
  }

  Future<drive.File?> getFileMetadata(String fileId) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;
      return await driveApi.files.get(fileId, $fields: 'id, name, mimeType, fileExtension') as drive.File;
    } catch (e) {
      debugPrint('DriveAuth: Error getting metadata: $e');
      return null;
    }
  }

  Future<List<int>?> downloadFile(String fileId) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> bytes = [];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      return bytes;
    } catch (e) {
      debugPrint('DriveAuth: Error downloading from Drive: $e');
      return null;
    }
  }

  Future<bool> deleteFile(String fileId) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return false;

      // Ensure the 'Deleted_Notes' folder exists
      final deletedFolderId = await _getOrCreateFolder(driveApi, 'Deleted_Notes');
      if (deletedFolderId == null) return false;

      // Get the file's current parents so we can remove it from its original location
      final file = await driveApi.files.get(fileId, $fields: 'parents') as drive.File;
      final previousParents = file.parents?.join(',') ?? '';

      // Move the file to the new folder
      await driveApi.files.update(
        drive.File(),
        fileId,
        addParents: deletedFolderId,
        removeParents: previousParents,
      );

      debugPrint('DriveAuth: Successfully moved file $fileId to Deleted_Notes folder');
      return true;
    } catch (e) {
      debugPrint('DriveAuth: Error moving file to deleted folder in Drive: $e');
      return false;
    }
  }

  Future<String?> uploadFile(File file, String fileName, {String? folderId, Function(double)? onProgress}) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      // If no folderId, ensure "NotesCache_Profiles" exists if it's an image
      String? actualFolderId = folderId;
      if (actualFolderId == null && (fileName.endsWith('.jpg') || fileName.endsWith('.png'))) {
        actualFolderId = await _getOrCreateFolder(driveApi, 'NotesCache_Profiles');
      }

      final driveFile = drive.File();
      driveFile.name = fileName;
      if (actualFolderId != null) {
        driveFile.parents = [actualFolderId];
      }

      final totalBytes = file.lengthSync();
      final stream = file.openRead();
      final progressStream = ProgressStream(stream, totalBytes, (p) {
        if (onProgress != null) onProgress(p);
      });

      final media = drive.Media(progressStream, totalBytes);
      final response = await driveApi.files.create(driveFile, uploadMedia: media);
      
      if (response.id != null) {
        debugPrint('DriveAuth: Successfully uploaded $fileName (ID: ${response.id})');
        // Make publicly viewable
        await driveApi.permissions.create(
          drive.Permission()
            ..type = 'anyone'
            ..role = 'reader',
          response.id!,
        );
      }

      return response.id;
    } catch (e) {
      debugPrint('DriveAuth: Error uploading to Drive: $e');
      return null;
    }
  }
}
