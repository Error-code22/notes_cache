import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'google_drive_auth_service.dart';
import 'models.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _colorKey = 'theme_color';
  static const String _fontKey = 'theme_font';

  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF1A237E);
  String _fontFamily = 'Inter';
  String? _currentUserId;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  String get fontFamily => _fontFamily;

  ThemeProvider() { _loadSettings(); }
  void setUserId(String? id) { _currentUserId = id; }

  void setUserTheme(UserProfile user) {
    _themeMode = user.themeMode == 'light' ? ThemeMode.light : (user.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.system);
    _seedColor = Color(user.themeColor);
    _fontFamily = user.themeFont;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_themeKey);
    if (mode == 'light') _themeMode = ThemeMode.light;
    else if (mode == 'dark') _themeMode = ThemeMode.dark;
    final colorVal = prefs.getInt(_colorKey);
    if (colorVal != null) _seedColor = Color(colorVal);
    _fontFamily = prefs.getString(_fontKey) ?? 'Inter';
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    _themeMode = m; notifyListeners();
    (await SharedPreferences.getInstance()).setString(_themeKey, m.name);
    _syncToSupabase();
  }

  Future<void> setSeedColor(Color c) async {
    _seedColor = c; notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_colorKey, c.value);
    _syncToSupabase();
  }

  Future<void> setFontFamily(String f) async {
    _fontFamily = f; notifyListeners();
    (await SharedPreferences.getInstance()).setString(_fontKey, f);
    _syncToSupabase();
  }

  Future<void> _syncToSupabase() async {
    if (_currentUserId == null) return;
    try {
      await Supabase.instance.client.from('profiles').update({
        'theme_mode': _themeMode.name, 'theme_color': _seedColor.value, 'theme_font': _fontFamily,
      }).eq('id', _currentUserId!);
    } catch (e) { debugPrint('Theme sync error: $e'); }
  }

  ThemeData getThemeData(Brightness b) {
    final isDark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: ColorScheme.fromSeed(seedColor: _seedColor, brightness: b),
      scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : null,
      cardColor: isDark ? const Color(0xFF1E1E1E) : null,
    );
  }
}

class AuthService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  UserProfile? _currentUser;
  bool _isLoading = false;
  ThemeProvider? _themeProvider;
  Function(int)? onYearAutoUpdated;

  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  AuthService() { _recoverSession(); }
  void updateThemeProvider(ThemeProvider p) { _themeProvider = p; }

  Future<void> _recoverSession() async {
    final session = _supabase.auth.currentSession;
    if (session != null) await _fetchUserProfile(session.user);
  }

  Future<void> signIn(String e, String p) async {
    _setLoading(true);
    try {
      final res = await _supabase.auth.signInWithPassword(email: e, password: p);
      if (res.user != null) await _fetchUserProfile(res.user!);
    } finally { _setLoading(false); }
  }

  Future<void> signUp(String e, String p, String n, int y) async {
    _setLoading(true);
    try {
      final res = await _supabase.auth.signUp(email: e, password: p, data: {'full_name': n, 'year_level': y, 'role': 'student'});
      if (res.user != null) await _fetchUserProfile(res.user!);
    } finally { _setLoading(false); }
  }

  Future<void> _fetchUserProfile(User user) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // Try fetching from Supabase
      final data = await _supabase.from('profiles').select().eq('id', user.id).single();
      _currentUser = UserProfile.fromMap(data, user.email!);
      
      // Save for offline use
      await prefs.setString('offline_profile_${user.id}', jsonEncode(data));
      await prefs.setString('offline_email_${user.id}', user.email!);
      
      if (_themeProvider != null) {
        _themeProvider!.setUserId(_currentUser!.id);
        _themeProvider!.setUserTheme(_currentUser!);
      }
      await _checkAndAutoUpdateYear();
      notifyListeners();
    } catch (e) { 
      debugPrint('Online profile fetch failed, trying offline cache...');
      final cachedData = prefs.getString('offline_profile_${user.id}');
      final cachedEmail = prefs.getString('offline_email_${user.id}');
      if (cachedData != null && cachedEmail != null) {
        _currentUser = UserProfile.fromMap(jsonDecode(cachedData), cachedEmail);
        notifyListeners();
      }
    }
  }

  Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) { return false; }
  }

  Future<void> _checkAndAutoUpdateYear() async {
    if (_currentUser == null || !_currentUser!.hasRole(UserRole.student) || _currentUser!.yearLevel == null) return;
    if (_currentUser!.yearLevel! >= 4) return;
    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    final targetStart = DateTime(startYear, 9, 1);
    if (_currentUser!.lastYearUpdate == null || _currentUser!.lastYearUpdate!.isBefore(targetStart)) {
      final newYear = _currentUser!.yearLevel! + 1;
      try {
        await _supabase.from('profiles').update({'year_level': newYear, 'last_year_update': now.toIso8601String()}).eq('id', _currentUser!.id);
        final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
        _currentUser = UserProfile.fromMap(data, _currentUser!.email);
        if (onYearAutoUpdated != null) onYearAutoUpdated!(newYear);
      } catch (e) { debugPrint('Auto-year error: $e'); }
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    _currentUser = null;
    if (_themeProvider != null) _themeProvider!.setUserId(null);
    notifyListeners();
  }

  Future<List<UserProfile>> getAllUsers() async {
    try {
      final List<dynamic> data = await _supabase.from('profiles').select();
      return data.map((item) => UserProfile.fromMap(item, item['email'] ?? '')).toList();
    } catch (e) { return []; }
  }

  Future<bool> updateUserRoles(String uid, List<UserRole> roles) async {
    try {
      final roleString = roles.map((r) => r.name).join(',');
      await _supabase.from('profiles').update({'role': roleString}).eq('id', uid);
      return true;
    } catch (e) { return false; }
  }

  Future<void> ensureFriendCode() async {
    if (_currentUser == null || _currentUser!.friendCode != null) return;
    
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; 
    final rnd = math.Random();
    String gen(int len) => List.generate(len, (i) => chars[rnd.nextInt(chars.length)]).join();
    
    final code = '${gen(3)}-${gen(3)}'; 
    
    try {
      await _supabase.from('profiles').update({'friend_code': code}).eq('id', _currentUser!.id);
      final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
    } catch (e) {
      debugPrint('Error generating friend code: $e');
    }
  }

  Future<void> updateProfileDetails({String? fullName, String? bio}) async {
    if (_currentUser == null) return;
    try {
      final updates = {if (fullName != null) 'full_name': fullName, if (bio != null) 'bio': bio};
      await _supabase.from('profiles').update(updates).eq('id', _currentUser!.id);
      final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
    } catch (e) {}
  }

  Future<bool> updateYearLevel(int y) async {
    if (_currentUser == null || _currentUser!.yearChanged) return false;
    try {
      await _supabase.from('profiles').update({'year_level': y, 'year_changed': true}).eq('id', _currentUser!.id);
      final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> updateProfileImage(File f) async {
    if (_currentUser == null) return false;
    try {
      final path = 'avatars/${_currentUser!.id}.${f.path.split('.').last}';
      await _supabase.storage.from('profiles').upload(path, f, fileOptions: const FileOptions(upsert: true));
      final url = _supabase.storage.from('profiles').getPublicUrl(path);
      await _supabase.from('profiles').update({'avatar_url': url}).eq('id', _currentUser!.id);
      final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
      return true;
    } catch (e) { return false; }
  }

  Future<void> signInAsGuest() async {
    _setLoading(true);
    try {
      // Create a dummy guest profile
      _currentUser = UserProfile(
        id: 'guest_user',
        email: 'guest@notescache.demo',
        fullName: 'Demo Student',
        roles: [UserRole.student],
        yearLevel: 1,
        isGuest: true,
      );
      if (_themeProvider != null) {
        _themeProvider!.setUserId('guest_user');
      }
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) { _isLoading = v; notifyListeners(); }
}

class NoteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Note>> getNotesForUser(UserProfile u, {int? semester, String? searchQuery}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'notes_cache_${u.id}_${semester ?? "all"}';

    try {
      var q = _supabase.from('notes').select();
      // Only restrict by yearLevel if they are strictly a student
      final isStrictlyStudent = u.hasRole(UserRole.student) && !u.hasRole(UserRole.admin) && !u.hasRole(UserRole.moderator) && !u.hasRole(UserRole.lecturer);
      
      if (isStrictlyStudent && u.yearLevel != null) {
        q = q.eq('target_year', u.yearLevel!);
      }
      if (semester != null) q = q.eq('semester', semester);
      if (searchQuery != null) q = q.ilike('title', '%$searchQuery%');
      
      final List<dynamic> data = await q.order('created_at', ascending: false).timeout(const Duration(seconds: 5));
      
      // Save to cache
      if (searchQuery == null) { // Only cache full lists
        await prefs.setString(cacheKey, jsonEncode(data));
      }
      
      return data.map((item) => Note.fromMap(item)).toList();
    } catch (e, st) {
      debugPrint('Note fetch error: $e\n$st');
      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        final List<dynamic> data = jsonDecode(cachedData);
        return data.map((item) => Note.fromMap(item)).toList();
      }
      return [];
    }
  }

  Future<List<UserActivity>> getUserActivity(String uid, {required Duration period}) async {
    final cutoff = DateTime.now().subtract(period).toIso8601String();
    // Filter by uid to ensure privacy in profile history
    final List<dynamic> data = await _supabase.from('notes')
        .select()
        .eq('user_id', uid)
        .gt('created_at', cutoff)
        .order('created_at', ascending: false);
        
    return data.map((item) => UserActivity(
      id: item['id'].toString(), title: 'Note Uploaded: ${item['title']}',
      description: 'You added this to the Year ${item['target_year']} library',
      timestamp: DateTime.parse(item['created_at']), type: 'upload',
    )).toList();
  }

  Future<Map<String, dynamic>?> findDuplicateNote({
    required String title,
    required int year,
    required int semester,
    required int fileSize,
  }) async {
    try {
      final sizeMatches = await _supabase.from('notes').select().eq('target_year', year).eq('semester', semester).eq('file_size', fileSize);
      if (sizeMatches.isNotEmpty) return {'reason': 'exact_size', 'note': sizeMatches.first};

      final List<dynamic> allNotes = await _supabase.from('notes').select('title, id').eq('target_year', year).eq('semester', semester);
      final normalizedNew = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      for (var existing in allNotes) {
        final existingTitle = (existing['title'] as String).toLowerCase();
        final normalizedExisting = existingTitle.replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (normalizedNew == normalizedExisting || (normalizedNew.length > 5 && normalizedExisting.contains(normalizedNew)) || (normalizedExisting.length > 5 && normalizedNew.contains(normalizedExisting))) {
          return {'reason': 'similar_title', 'note': existing};
        }
      }
      return null;
    } catch (e) { return null; }
  }

  Future<bool> deleteNote(String id) async {
    try {
      await _supabase.from('notes').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error deleting note: $e');
      return false;
    }
  }

  Future<bool> saveNote({required String title, required String lecturerName, required int targetYear, required int semester, String? gDriveId, String? content, String? category, String? summary, int? fileSize}) async {
    try {
      await _supabase.from('notes').insert({
        'title': title,
        'lecturer_name': lecturerName,
        'target_year': targetYear,
        'semester': semester,
        'gdrive_id': gDriveId,
        'content': content ?? '',
        'category': category ?? 'Note',
        'summary': summary,
        'created_at': DateTime.now().toIso8601String(),
        'file_size': fileSize ?? 0
      });
      return true;
    } catch (e) { return false; }
  }

  Future<String> getAppDirectory() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}\\NotesCache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    try {
      final u = await _supabase.from('profiles').select('id').count(CountOption.exact);
      final n = await _supabase.from('notes').select('id').count(CountOption.exact);
      return {'totalUsers': u.count ?? 0, 'totalNotes': n.count ?? 0, 'storageUsed': '0.5 GB'};
    } catch (e) { return {'totalUsers': 0, 'totalNotes': 0, 'storageUsed': 'N/A'}; }
  }

  Future<Map<String, String>> getAppConfig() async {
    try {
      final List<dynamic> data = await _supabase.from('app_config').select();
      return {for (var item in data) item['key']: item['value']};
    } catch (e) { 
      return {
        'about_text': 'NotesCache v1.0.0',
        'terms_and_conditions': 'NOTESCACHE TERMS OF SERVICE:\n\n1. Guest Mode: Activity in Demo/Guest mode is temporary and not stored, with the EXCEPTIONS of uploaded Notes. Any academic materials uploaded by a guest will be permanently indexed in our library.\n2. Contributions: By uploading, you grant NotesCache a license to store and share your materials.\n3. Privacy: We do not sell your data.\n4. Chat Security: All communications are encrypted in transit and at rest using industry-standard protocols.',
        'privacy_policy': 'NOTESCACHE PRIVACY POLICY:\n\n1. Data Collection: We collect profile data for registered users. Guests remain anonymous.\n2. Note Storage: Notes uploaded by any user (including Guests) are stored permanently to benefit the student community.\n3. Security: We use Supabase for secure data management with enterprise-grade encryption.',
        'support_email': 'support@notescache.com',
        'support_phone': '+254700000000',
        'support_whatsapp': '254700000000',
        'mpesa_no': '123456'
      }; 
    }
  }

  Future<void> updateAppConfig(String k, String v) async {
    await _supabase.from('app_config').upsert({'key': k, 'value': v});
  }
}

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;
  Future<UserProfile?> findUserByCode(String c) async {
    final normalized = c.replaceAll('-', '').toUpperCase();
    final data = await _supabase.from('profiles').select().inFilter('friend_code', [normalized, _formatWithDash(normalized)]).maybeSingle();
    return data != null ? UserProfile.fromMap(data, data['email'] ?? '') : null;
  }

  String _formatWithDash(String c) {
    if (c.length == 6 && !c.contains('-')) return '${c.substring(0, 3)}-${c.substring(3)}';
    return c;
  }
  Future<bool> addFriend(String uid, String fid) async {
    try { await _supabase.from('friends').insert({'user_id': uid, 'friend_id': fid, 'status': 'accepted'}); return true; } catch (e) { return false; }
  }
  Stream<List<FriendRelation>> getFriendsStream(String uid) {
    return _supabase.from('friends').stream(primaryKey: ['id']).eq('user_id', uid).asyncMap((data) async {
      final List<FriendRelation> list = [];
      for (var item in data) {
        final prof = await _supabase.from('profiles').select().eq('id', item['friend_id']).single();
        list.add(FriendRelation(userId: uid, friendId: item['friend_id'], status: item['status'], friendProfile: UserProfile.fromMap(prof, prof['email'] ?? '')));
      }
      return list;
    });
  }
  Future<ChatRoom?> createChatRoom({required String creatorId, required String name, required bool isGroup, required List<String> members, bool isPublic = false, String? description}) async {
    final res = await _supabase.from('chat_rooms').insert({'name': name, 'is_group': isGroup, 'is_public': isPublic, 'description': description, 'member_ids': members, 'created_by': creatorId}).select().single();
    return ChatRoom.fromMap(res);
  }
  Stream<List<ChatRoom>> getChatRoomsStream(String uid) {
    return _supabase.from('chat_rooms').stream(primaryKey: ['id']).map((data) => data.where((item) => (item['member_ids'] as List).contains(uid)).map((item) => ChatRoom.fromMap(item)).toList());
  }
  Stream<ChatRoom> getRoomStream(String rid) {
    return _supabase.from('chat_rooms').stream(primaryKey: ['id']).eq('id', rid).map((data) => ChatRoom.fromMap(data.first));
  }
  Future<List<UserProfile>> getRoomMembers(List<String> uids) async {
    final List<dynamic> data = await _supabase.from('profiles').select().inFilter('id', uids);
    return data.map((item) => UserProfile.fromMap(item, item['email'] ?? '')).toList();
  }
  Future<List<ChatRoom>> getPublicChatRooms(String uid) async {
    final List<dynamic> data = await _supabase.from('chat_rooms').select().eq('is_public', true);
    return data.map((item) => ChatRoom.fromMap(item)).where((r) => !r.memberIds.contains(uid)).toList();
  }
  Future<bool> joinChatRoom(String rid, String uid) async {
    final room = await _supabase.from('chat_rooms').select().eq('id', rid).single();
    List<String> mems = List<String>.from(room['member_ids']);
    if (!mems.contains(uid)) { mems.add(uid); await _supabase.from('chat_rooms').update({'member_ids': mems}).eq('id', rid); }
    return true;
  }
  Future<UserProfile?> getOtherMemberProfile(ChatRoom r, String uid) async {
    if (r.isGroup) return null;
    final oid = r.memberIds.firstWhere((id) => id != uid, orElse: () => '');
    if (oid.isEmpty) return null;
    final data = await _supabase.from('profiles').select().eq('id', oid).single();
    return UserProfile.fromMap(data, data['email'] ?? '');
  }
  Future<bool> sendMessage(String rid, String sid, String c, String n) async {
    await _supabase.from('chat_messages').insert({'room_id': rid, 'sender_id': sid, 'content': c, 'sender_name': n});
    await _supabase.from('chat_rooms').update({'last_message': c, 'last_message_time': DateTime.now().toIso8601String()}).eq('id', rid);
    return true;
  }
  Stream<List<ChatMessage>> getMessagesStream(String rid) {
    return _supabase.from('chat_messages').stream(primaryKey: ['id']).eq('room_id', rid).order('created_at', ascending: true).map((data) => data.map((item) => ChatMessage.fromMap(item)).toList());
  }
  Future<int> bulkAddByCodes(String rid, List<String> codes) async {
    int added = 0;
    final room = await _supabase.from('chat_rooms').select().eq('id', rid).single();
    List<String> mems = List<String>.from(room['member_ids']);
    for (var c in codes) {
      final u = await findUserByCode(c.trim());
      if (u != null && !mems.contains(u.id)) { mems.add(u.id); added++; }
    }
    await _supabase.from('chat_rooms').update({'member_ids': mems}).eq('id', rid);
    return added;
  }

  Future<void> updateLastRead(String rid, String uid) async {
    await _supabase.from('room_member_metadata').upsert({
      'room_id': rid,
      'user_id': uid,
      'last_read_at': DateTime.now().toUtc().add(const Duration(seconds: 2)).toIso8601String()
    });
  }

  Future<int> getUnreadCount(String rid, String uid) async {
    final metaList = await _supabase.from('room_member_metadata').select().eq('room_id', rid).eq('user_id', uid);
    final msgs = await _supabase.from('chat_messages').select('created_at, sender_id').eq('room_id', rid);
    final otherMsgs = msgs.where((m) => m['sender_id'] != uid).toList();
    if (metaList.isEmpty) return otherMsgs.length;
    final lastRead = DateTime.parse(metaList.first['last_read_at']).toUtc();
    return otherMsgs.where((m) => DateTime.parse(m['created_at']).toUtc().isAfter(lastRead)).length;
  }

  Future<DateTime?> getLastReadAt(String rid, String uid) async {
    final data = await _supabase.from('room_member_metadata').select('last_read_at').eq('room_id', rid).eq('user_id', uid).maybeSingle();
    return data != null ? DateTime.parse(data['last_read_at']) : null;
  }
}

class AiChatService {
  final String _url = 'https://api.groq.com/openai/v1/chat/completions';
  
  Future<int> getGuestMessageCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('guest_ai_messages') ?? 0;
  }

  Future<void> incrementGuestMessageCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('guest_ai_messages') ?? 0;
    await prefs.setInt('guest_ai_messages', current + 1);
  }

  Future<String> getResponse(String msg, List<Map<String, String>> history, {String? imageBase64}) async {
    final key = dotenv.env['GROQ_API_KEY'];
    final body = jsonEncode({
      'model': 'llama-3.1-8b-instant', 
      'messages': [
        {'role': 'system', 'content': 'Study assistant...'}, 
        ...history, 
        {'role': 'user', 'content': imageBase64 != null ? 'Shared an image. $msg' : msg}
      ]
    });
    final res = await http.post(Uri.parse(_url), headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'}, body: body);
    if (res.statusCode == 200) return jsonDecode(res.body)['choices'][0]['message']['content'];
    throw Exception('AI error');
  }
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _windowsReady = false;

  Future<void> init() async {
    if (Platform.isWindows) {
      try {
        await localNotifier.setup(appName: 'NotesCache', shortcutPolicy: ShortcutPolicy.requireCreate);
        _windowsReady = true;
      } catch (e) {
        // Plugin not yet compiled into runner — requires a full `flutter run`, not hot restart
        debugPrint('⚠️ local_notifier not ready yet: $e. Do a full stop + run to enable Windows notifications.');
      }
      return;
    }
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _notifications.initialize(const InitializationSettings(android: android, iOS: ios));

      if (Platform.isAndroid) {
        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('⚠️ flutter_local_notifications init failed: $e');
    }
  }

  Future<void> showNotification({required String title, required String body}) async {
    debugPrint('🔔 NOTIFICATION TRIGGERED: $title - $body');
    if (Platform.isWindows) {
      if (!_windowsReady) {
        debugPrint('⚠️ Skipping notification — Windows notifier not ready (need full restart).');
        return;
      }
      try {
        LocalNotification notification = LocalNotification(title: title, body: body);
        notification.show();
      } catch (e) {
        debugPrint('⚠️ Windows notification failed: $e');
      }
      return;
    }
    try {
      const android = AndroidNotificationDetails('channel_id', 'channel_name', importance: Importance.max, priority: Priority.high);
      const ios = DarwinNotificationDetails();
      await _notifications.show(0, title, body, const NotificationDetails(android: android, iOS: ios));
    } catch (e) {
      debugPrint('⚠️ Notification show failed: $e');
    }
  }
}
