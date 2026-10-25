import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
      final prefs = await SharedPreferences.getInstance();

      gauth.AccessCredentials? credentials;
      final tokenJson = prefs.getString('google_drive_token');
      if (tokenJson != null) {
        try {
          credentials = gauth.AccessCredentials.fromJson(jsonDecode(tokenJson));
        } catch (e) {
          debugPrint('DriveAuth: Stored token is unreadable, clearing: $e');
          await prefs.remove('google_drive_token');
        }
      }

      if (credentials == null) {
        credentials = await _windowsConsentFlow();
        await prefs.setString('google_drive_token', jsonEncode(credentials.toJson()));
      } else if (_needsRefresh(credentials)) {
        try {
          credentials = await _refreshCredentials(credentials);
          await prefs.setString('google_drive_token', jsonEncode(credentials.toJson()));
        } catch (e) {
          debugPrint('DriveAuth: Refresh failed, re-authenticating: $e');
          await prefs.remove('google_drive_token');
          credentials = await _windowsConsentFlow();
          await prefs.setString('google_drive_token', jsonEncode(credentials.toJson()));
        }
      }

      debugPrint('DriveAuth: Windows authentication ready.');
      return drive.DriveApi(_DriveAuthClient(credentials, prefs));
    } catch (e) {
      debugPrint('DriveAuth: Windows Auth Error: $e');
      return null;
    }
  }

  bool _needsRefresh(gauth.AccessCredentials credentials) {
    if (credentials.refreshToken == null) return credentials.accessToken.hasExpired;
    final remaining =
        credentials.accessToken.expiry.difference(DateTime.now().toUtc());
    return remaining < const Duration(minutes: 2);
  }

  Future<gauth.AccessCredentials> _windowsConsentFlow() async {
    final clientId = dotenv.env['GOOGLE_DRIVE_CLIENT_ID'];
    if (clientId == null || clientId.isEmpty) {
      throw StateError('GOOGLE_DRIVE_CLIENT_ID is missing from .env');
    }

    final scopes = [drive.DriveApi.driveFileScope];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    final state = _randomUrlSafe(32);
    final verifier = _randomUrlSafe(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

    debugPrint('DriveAuth: Opening browser for auth: $authUri');
    if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw StateError('Could not open the Google sign-in page.');
    }

    try {
      final request = await server.first.timeout(const Duration(minutes: 5));
      final params = request.uri.queryParameters;

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html><body style="font-family:sans-serif;padding:40px">'
            '<h2>NotesCache is connected to Google Drive.</h2>'
            '<p>You can close this tab and return to the app.</p>'
            '</body></html>');
      await request.response.close();

      if (params['error'] != null) {
        throw StateError('Google sign-in was cancelled (${params['error']}).');
      }
      if (params['state'] != state) {
        throw StateError('Google sign-in state mismatch. Please try again.');
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw StateError('Google did not return an authorization code.');
      }

      return await _exchangeCode(code, verifier, redirectUri);
    } finally {
      await server.close(force: true);
    }
  }

  String _randomUrlSafe(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  Future<gauth.AccessCredentials> _exchangeCode(
    String code,
    String verifier,
    String redirectUri,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'drive-oauth',
      body: {
        'action': 'exchange',
        'code': code,
        'codeVerifier': verifier,
        'redirectUri': redirectUri,
      },
    );
    return _credentialsFromResponse(response.data);
  }

  Future<gauth.AccessCredentials> _refreshCredentials(
    gauth.AccessCredentials old,
  ) async {
    final refresh = old.refreshToken;
    if (refresh == null) {
      throw StateError('Google Drive session expired. Please sign in again.');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'drive-oauth',
      body: {'action': 'refresh', 'refreshToken': refresh},
    );
    return _credentialsFromResponse(response.data, refreshToken: refresh);
  }

  gauth.AccessCredentials _credentialsFromResponse(
    dynamic data, {
    String? refreshToken,
  }) {
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : Map<String, dynamic>.from(jsonDecode(data.toString()) as Map);
    final accessToken = map['access_token'] as String?;
    final expiresIn = map['expires_in'] as num?;
    if (accessToken == null || expiresIn == null) {
      throw StateError('Drive OAuth returned an incomplete token response.');
    }
    return gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        accessToken,
        DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt())),
      ),
      (map['refresh_token'] as String?) ?? refreshToken,
      [drive.DriveApi.driveFileScope],
    );
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

/// Adds a bearer token to Drive requests and refreshes it through the
/// `drive-oauth` Edge Function. The Google client secret never ships with the
/// desktop app; it lives only in Supabase Function secrets.
class _DriveAuthClient extends http.BaseClient {
  _DriveAuthClient(this._credentials, this._prefs);

  gauth.AccessCredentials _credentials;
  final SharedPreferences _prefs;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_credentials.accessToken.hasExpired ||
        _credentials.accessToken.expiry.difference(DateTime.now().toUtc()) <
            const Duration(minutes: 2)) {
      await _refresh();
    }

    request.headers['Authorization'] =
        'Bearer ${_credentials.accessToken.data}';
    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      await _prefs.remove('google_drive_token');
      throw StateError('Google Drive session expired. Please retry the upload.');
    }
    return response;
  }

  Future<void> _refresh() async {
    final refreshToken = _credentials.refreshToken;
    if (refreshToken == null) {
      throw StateError('Google Drive session expired. Please sign in again.');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'drive-oauth',
      body: {'action': 'refresh', 'refreshToken': refreshToken},
    );
    final data = response.data;
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : Map<String, dynamic>.from(jsonDecode(data.toString()) as Map);
    final accessToken = map['access_token'] as String?;
    final expiresIn = map['expires_in'] as num?;
    if (accessToken == null || expiresIn == null) {
      throw StateError('Drive OAuth refresh returned an incomplete response.');
    }
    _credentials = gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        accessToken,
        DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt())),
      ),
      (map['refresh_token'] as String?) ?? refreshToken,
      [drive.DriveApi.driveFileScope],
    );
    await _prefs.setString(
      'google_drive_token',
      jsonEncode(_credentials.toJson()),
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
