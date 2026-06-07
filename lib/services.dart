import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
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

  Future<void> updateProfilePublic(bool isPublic) async {
    if (_currentUser == null) return;
    try {
      await _supabase.from('profiles').update({'is_profile_public': isPublic}).eq('id', _currentUser!.id);
      final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
    } catch (e) { debugPrint('updateProfilePublic error: $e'); }
  }

  Future<bool> deleteAccount() async {
    if (_currentUser == null) return false;
    try {
      // Delete avatar from storage
      try {
        final ext = ['jpg', 'jpeg', 'png', 'webp'];
        for (final e in ext) {
          await _supabase.storage.from('avatars').remove(['${_currentUser!.id}/avatar.$e']);
        }
      } catch (_) {}

      // Delete profile data
      await _supabase.from('profiles').delete().eq('id', _currentUser!.id);

      // Delete user notes
      await _supabase.from('notes').delete().eq('user_id', _currentUser!.id);

      // Delete chat messages sent by user
      await _supabase.from('chat_messages').delete().eq('sender_id', _currentUser!.id);

      // Delete AI usage
      await _supabase.from('user_ai_usage').delete().eq('user_id', _currentUser!.id);

      // Delete feedback
      await _supabase.from('app_feedback').delete().eq('user_id', _currentUser!.id);

      // Sign out
      await _supabase.auth.signOut();
      _currentUser = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      return false;
    }
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
      // Security: Validate file extension
      final ext = f.path.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
        debugPrint('updateProfileImage: Invalid file type: $ext');
        return false;
      }

      // Security: Check file size (2MB limit)
      final fileSize = await f.length();
      if (fileSize > 2 * 1024 * 1024) {
        debugPrint('updateProfileImage: File too large: ${fileSize ~/ 1024}KB');
        return false;
      }

      // Security: Validate MIME type by reading magic bytes
      final bytes = await f.openRead(0, 8).first;
      final magic = bytes.take(8).toList();
      final isValidImage = _isValidImageMagic(magic);
      if (!isValidImage) {
        debugPrint('updateProfileImage: Invalid image magic bytes');
        return false;
      }

      // Upload to Supabase Storage
      final userId = _currentUser!.id;
      final storagePath = '$userId/avatar.$ext';

      // Delete old avatar if exists (ignore errors)
      try {
        await _supabase.storage.from('avatars').remove([storagePath]);
      } catch (_) {}

      // Upload new avatar
      await _supabase.storage.from('avatars').upload(
        storagePath,
        f,
        fileOptions: const FileOptions(upsert: true),
      );

      // Get public URL
      final publicUrl = _supabase.storage.from('avatars').getPublicUrl(storagePath);

      // Update profile
      await _supabase.from('profiles').update({'avatar_url': publicUrl}).eq('id', userId);
      final data = await _supabase.from('profiles').select().eq('id', userId).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('updateProfileImage error: $e');
      return false;
    }
  }

  /// Check magic bytes to validate image file type
  bool _isValidImageMagic(List<int> bytes) {
    // JPEG: FF D8 FF
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG: 89 50 4E 47
    if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    // WebP: RIFF....WEBP
    if (bytes.length >= 4 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) return true;
    return false;
  }

  /// Generate a default DiceBear avatar URL for users without custom avatars
  static String getDefaultAvatarUrl(String? fullName, String userId) {
    final seed = Uri.encodeComponent(fullName ?? userId);
    return 'https://api.dicebear.com/8.x/initials/png?seed=$seed&backgroundColor=1a237e,1565c0,0277bd,00838f,2e7d32&fontSize=40';
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

  Future<bool> submitFeedback(String type, String content) async {
    if (_currentUser == null) return false;
    try {
      await _supabase.from('app_feedback').insert({
        'user_id': _currentUser!.id,
        'type': type,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) { return false; }
  }
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
    try {
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
    } catch (e) {
      // Schema may not have user_id column yet — return empty list gracefully
      debugPrint('getUserActivity error (user_id column may not exist): $e');
      return [];
    }
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

  Future<List<AppFeedback>> getAllFeedback() async {
    try {
      final List<dynamic> data = await _supabase
          .from('app_feedback')
          .select('*, profiles(full_name)')
          .order('created_at', ascending: false);
      return data.map((item) => AppFeedback.fromMap(item)).toList();
    } catch (e) {
      debugPrint('Error fetching feedback: $e');
      return [];
    }
  }

  Future<void> insertAppUpdate(String title, String content) async {
    try {
      await _supabase.from('app_updates').insert({'title': title, 'content': content});
    } catch (e) {
      debugPrint('Error inserting app update: $e');
    }
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
        'about_text': 'NotesCache v1.0.0\n\nYour campus study companion. Access lecture notes, chat with classmates, and get instant AI-powered help — all in one place.\n\nBuilt for students, by students.\n\n© 2026 NotesCache. All rights reserved.',
        'terms_and_conditions': 'NOTESCACHE TERMS OF SERVICE\n\nLast Updated: June 2026\n\n1. ACCEPTANCE OF TERMS\nBy accessing or using NotesCache ("the App"), you agree to be bound by these Terms of Service. If you do not agree, do not use the App.\n\n2. ELIGIBILITY\nYou must be a currently enrolled student or staff member at a recognized educational institution. You must provide accurate registration information.\n\n3. ACCOUNT RESPONSIBILITY\nYou are responsible for maintaining the confidentiality of your account. You agree to notify us immediately of any unauthorized use. One account per person.\n\n4. USER CONTENT\n4.1 By uploading notes, documents, or other materials ("User Content"), you grant NotesCache a non-exclusive, royalty-free license to store, display, and distribute such content within the App for educational purposes.\n4.2 You retain ownership of your User Content.\n4.3 You must not upload content that infringes copyright, contains malware, or violates any law.\n4.4 NotesCache reserves the right to remove any User Content at its discretion.\n\n5. AI SERVICES\n5.1 The App provides AI-powered assistance ("Notesy") for educational purposes only.\n5.2 AI responses may contain errors. Always verify information with official course materials.\n5.3 AI usage is subject to daily limits based on your subscription tier.\n5.4 Do not attempt to manipulate, reverse-engineer, or abuse the AI system.\n\n6. PROHIBITED USES\n- Sharing account credentials\n- Scraping or automated data collection\n- Harassment, spam, or abusive behavior in chat rooms\n- Uploading copyrighted material without authorization\n- Attempting to bypass security measures or rate limits\n- Using the App for commercial purposes without a Campus License\n\n7. SUBSCRIPTION & PAYMENTS\n7.1 Free tier is available at no cost with limited features.\n7.2 Paid subscriptions (Student Pro, Campus License) are billed via M-Pesa.\n7.3 Subscriptions auto-renew unless cancelled before the billing date.\n7.4 Refunds are available within 7 days of purchase if less than 10 AI queries were made.\n\n8. TERMINATION\nWe may suspend or terminate your account for violations of these Terms. Upon termination, your right to use the App ceases immediately.\n\n9. LIMITATION OF LIABILITY\nNotesCache is provided "as is" without warranties. We are not liable for any damages arising from use of the App, including but not limited to academic consequences from relying on AI-generated content.\n\n10. GOVERNING LAW\nThese Terms are governed by the laws of the Republic of Kenya.\n\n11. CONTACT\nFor questions about these Terms, contact: support@notescache.com',
        'privacy_policy': 'NOTESCACHE PRIVACY POLICY\n\nLast Updated: June 2026\n\n1. INFORMATION WE COLLECT\n1.1 Account Information: Name, email address, university, year of study, and profile photo (optional).\n1.2 User Content: Notes, documents, and materials you upload to the platform.\n1.3 Chat Messages: Messages you send in chat rooms and direct messages.\n1.4 AI Interactions: Questions asked to Notesy AI and the responses generated.\n1.5 Usage Data: App activity, feature usage, and session information.\n\n2. HOW WE USE YOUR INFORMATION\n2.1 To provide and improve the App\'s services.\n2.2 To power AI features (lecture search, question answering).\n2.3 To enable communication between users (chat rooms, friend system).\n2.4 To enforce usage limits and prevent abuse.\n2.5 To send important service announcements.\n\n3. DATA SHARING\n3.1 We do NOT sell your personal data to third parties.\n3.2 We use Supabase (supabase.com) for data storage and authentication. Their privacy policy applies to infrastructure-level data handling.\n3.3 We use Groq (groq.com) and Google AI (ai.google.dev) for AI processing. Questions sent to AI may be processed by these providers.\n3.4 We may disclose information if required by law or to protect our rights.\n\n4. DATA STORAGE & SECURITY\n4.1 All data is stored on Supabase servers with enterprise-grade encryption.\n4.2 Chat messages are encrypted in transit and at rest.\n4.3 We implement Row Level Security (RLS) to ensure users can only access their own data.\n4.4 Passwords are hashed and never stored in plain text.\n\n5. YOUR RIGHTS\n5.1 You can update your profile information at any time from the app.\n5.2 You can delete your account from Profile > Settings > Delete Account.\n5.3 Upon account deletion, your personal data, chat messages, and AI history are permanently removed.\n5.4 Notes you uploaded may be retained for the benefit of the student community.\n\n6. GUEST MODE\n6.1 Guest users can browse notes and use limited AI features.\n6.2 Guest activity is not linked to personal identity.\n6.3 Notes uploaded by guests are permanently stored in the library.\n\n7. CHILDREN\'S PRIVACY\nThe App is intended for users aged 16 and above. We do not knowingly collect data from children under 16.\n\n8. CHANGES TO THIS POLICY\nWe may update this Privacy Policy from time to time. We will notify users of significant changes via in-app announcements.\n\n9. CONTACT\nFor privacy-related inquiries, contact: support@notescache.com',
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
      if (data.isEmpty) return <FriendRelation>[];
      // Batch-fetch all friend profiles in one query instead of N individual calls
      final friendIds = data.map((item) => item['friend_id'] as String).toList();
      final profiles = await _supabase.from('profiles').select().inFilter('id', friendIds);
      final profileMap = {for (var p in profiles) p['id'] as String: p};
      return data.map((item) {
        final prof = profileMap[item['friend_id']];
        return FriendRelation(
          userId: uid,
          friendId: item['friend_id'],
          status: item['status'],
          friendProfile: prof != null ? UserProfile.fromMap(prof, prof['email'] ?? '') : null,
        );
      }).toList();
    });
  }

  /// Returns an existing DM room between [uid] and [friendId], or null if none exists.
  Future<ChatRoom?> findExistingDm(String uid, String friendId) async {
    try {
      final List<dynamic> data = await _supabase
          .from('chat_rooms')
          .select()
          .eq('is_group', false);
      for (final item in data) {
        final members = List<String>.from(item['member_ids'] ?? []);
        if (members.contains(uid) && members.contains(friendId) && members.length == 2) {
          return ChatRoom.fromMap(item);
        }
      }
      return null;
    } catch (e) {
      debugPrint('findExistingDm error: $e');
      return null;
    }
  }

  Future<ChatRoom?> createChatRoom({required String creatorId, required String name, required bool isGroup, required List<String> members, bool isPublic = false, String? description}) async {
    final res = await _supabase.from('chat_rooms').insert({'name': name, 'is_group': isGroup, 'is_public': isPublic, 'description': description, 'member_ids': members, 'created_by': creatorId}).select().single();
    return ChatRoom.fromMap(res);
  }
  Stream<List<ChatRoom>> getChatRoomsStream(String uid) {
    return _supabase.from('chat_rooms').stream(primaryKey: ['id']).map((data) => data.where((item) => (item['member_ids'] as List).contains(uid)).map((item) => ChatRoom.fromMap(item)).toList());
  }

  /// Streams DM (non-group) rooms where [uid] is a member.
  /// Uses a periodic poll because Supabase `.stream()` can't filter by array-contains.
  Stream<List<ChatRoom>> getDmRoomsStream(String uid) async* {
    while (true) {
      try {
        final data = await _supabase
            .from('chat_rooms')
            .select()
            .eq('is_group', false);
        final allRooms = (data as List)
            .map((item) => ChatRoom.fromMap(item))
            .where((r) => r.memberIds.contains(uid))
            .toList();

        // Deduplicate: if multiple DM rooms exist for the same pair, keep the newest
        final Map<String, ChatRoom> deduped = {};
        for (final room in allRooms) {
          final otherId = room.memberIds.firstWhere((id) => id != uid, orElse: () => '');
          if (otherId.isEmpty) continue;
          final existing = deduped[otherId];
          if (existing == null ||
              (room.lastMessageTime != null &&
               (existing.lastMessageTime == null ||
                room.lastMessageTime!.isAfter(existing.lastMessageTime!)))) {
            deduped[otherId] = room;
          }
        }
        yield deduped.values.toList();
      } catch (e) {
        debugPrint('getDmRoomsStream error: $e');
        yield [];
      }
      await Future.delayed(const Duration(seconds: 5));
    }
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
    // Only sender has read the latest message — matches Firebase pattern
    await _supabase.from('chat_rooms').update({
      'last_message': c,
      'last_message_time': DateTime.now().toIso8601String(),
      'last_message_read_by': [sid],
    }).eq('id', rid);
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
    // Add uid to last_message_read_by — same pattern as Firebase's arrayUnion
    try {
      final room = await _supabase.from('chat_rooms').select('last_message_read_by').eq('id', rid).single();
      final List<String> readers = List<String>.from(room['last_message_read_by'] ?? []);
      if (!readers.contains(uid)) {
        readers.add(uid);
        await _supabase.from('chat_rooms').update({'last_message_read_by': readers}).eq('id', rid);
      }
    } catch (e) {
      debugPrint('updateLastRead error: $e');
    }
  }

  Future<int> getUnreadCount(String rid, String uid) async {
    try {
      final room = await _supabase.from('chat_rooms').select('last_message_read_by, last_message').eq('id', rid).maybeSingle();
      if (room == null || room['last_message'] == null) return 0;
      final List<String> readers = List<String>.from(room['last_message_read_by'] ?? []);
      // Unread = uid not in readers AND there is a last message
      return readers.contains(uid) ? 0 : 1;
    } catch (e) {
      debugPrint('getUnreadCount error: $e');
      return 0;
    }
  }

  Future<DateTime?> getLastReadAt(String rid, String uid) async {
    // Not needed with the new pattern — return null to suppress the NEW MESSAGES separator
    return null;
  }

  /// Deletes a chat room and all its messages. Only the creator should call this.
  Future<bool> deleteRoom(String rid) async {
    try {
      // Delete all messages first
      await _supabase.from('chat_messages').delete().eq('room_id', rid);
      // Delete the room
      await _supabase.from('chat_rooms').delete().eq('id', rid);
      return true;
    } catch (e) {
      debugPrint('deleteRoom error: $e');
      return false;
    }
  }

  // ============================================================
  // CHAT MESSAGE ARCHIVING
  // Keeps DB under 500MB by moving old messages to Supabase Storage
  // ============================================================
  static const int _maxMessagesPerRoom = 50; // Keep last 50 in DB
  static const int _archiveThreshold = 60; // Trigger archive at 60

  /// Archive old messages for a room if it exceeds the threshold
  Future<void> archiveOldMessages(String roomId) async {
    try {
      // Count messages in room
      final countResult = await _supabase
          .from('chat_messages')
          .select('id')
          .eq('room_id', roomId);

      if (countResult.length <= _archiveThreshold) return; // Not enough to archive

      // Get messages to archive (oldest first, keep last 50)
      final messagesToArchive = await _supabase
          .from('chat_messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .limit(countResult.length - _maxMessagesPerRoom);

      if (messagesToArchive.isEmpty) return;

      // Get existing archive path
      final existingArchive = await _supabase
          .from('chat_archives')
          .select('archive_path, message_count')
          .eq('room_id', roomId)
          .maybeSingle();

      String archivePath;
      List<Map<String, dynamic>> existingMessages = [];

      if (existingArchive != null) {
        archivePath = existingArchive['archive_path'];
        // Download existing archive
        try {
          final bytes = await _supabase.storage
              .from('chat-archives')
              .download(archivePath);
          final content = String.fromCharCodes(bytes);
          existingMessages = List<Map<String, dynamic>>.from(
            (jsonDecode(content) as List).map((m) => Map<String, dynamic>.from(m))
          );
        } catch (_) {
          // Archive file doesn't exist yet, start fresh
        }
      } else {
        archivePath = '$roomId/archive_${DateTime.now().millisecondsSinceEpoch}.json';
      }

      // Merge with existing archived messages
      existingMessages.addAll(messagesToArchive);

      // Upload to Supabase Storage
      final jsonContent = jsonEncode(existingMessages);
      final bytes = utf8.encode(jsonContent);

      await _supabase.storage
          .from('chat-archives')
          .uploadBinary(archivePath, bytes);

      // Delete archived messages from DB
      final idsToDelete = messagesToArchive.map((m) => m['id']).toList();
      for (var i = 0; i < idsToDelete.length; i += 50) {
        final batch = idsToDelete.sublist(i, (i + 50).clamp(0, idsToDelete.length));
        await _supabase
            .from('chat_messages')
            .delete()
            .inFilter('id', batch);
      }

      // Update or create archive record
      await _supabase.from('chat_archives').upsert({
        'room_id': roomId,
        'archive_path': archivePath,
        'message_count': existingMessages.length,
        'last_archived_at': DateTime.now().toIso8601String(),
      });

      debugPrint('Archived ${messagesToArchive.length} messages for room $roomId');
    } catch (e) {
      debugPrint('archiveOldMessages error: $e');
    }
  }

  /// Load archived messages for a room (when scrolling up)
  Future<List<Map<String, dynamic>>> loadArchivedMessages(String roomId) async {
    try {
      final archive = await _supabase
          .from('chat_archives')
          .select('archive_path')
          .eq('room_id', roomId)
          .maybeSingle();

      if (archive == null) return [];

      final bytes = await _supabase.storage
          .from('chat-archives')
          .download(archive['archive_path']);

      final content = String.fromCharCodes(bytes);
      return List<Map<String, dynamic>>.from(
        (jsonDecode(content) as List).map((m) => Map<String, dynamic>.from(m))
      );
    } catch (e) {
      debugPrint('loadArchivedMessages error: $e');
      return [];
    }
  }

  /// Run archiving for all rooms that need it (call periodically)
  Future<void> archiveAllRooms() async {
    try {
      final rooms = await _supabase.from('chat_rooms').select('id');
      for (final room in rooms) {
        await archiveOldMessages(room['id']);
      }
    } catch (e) {
      debugPrint('archiveAllRooms error: $e');
    }
  }
}

class AiChatService {
  Future<int> getGuestMessageCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('guest_ai_messages') ?? 0;
  }

  Future<void> incrementGuestMessageCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getGuestMessageCount();
    await prefs.setInt('guest_ai_messages', current + 1);
  }

  Future<int> getDailyMessageCount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    return prefs.getInt('ai_daily_${userId}_$today') ?? 0;
  }

  Future<void> incrementDailyMessageCount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final current = await getDailyMessageCount(userId);
    await prefs.setInt('ai_daily_${userId}_$today', current + 1);
  }

  // --- AI Chat History (Supabase) ---
  static const int _maxHistoryMessages = 50; // Keep last 50 in DB
  static const int _contextMessages = 5; // Send last 5 to Groq

  Future<List<Map<String, String>>> loadChatHistory(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      final result = await supabase
          .from('ai_chat_history')
          .select('messages')
          .eq('user_id', userId)
          .maybeSingle();

      if (result != null && result['messages'] != null) {
        final List<dynamic> messages = result['messages'];
        return messages.map((m) => Map<String, String>.from(m)).toList();
      }
    } catch (e) {
      debugPrint('Load AI history error: $e');
    }
    return [];
  }

  Future<void> saveChatHistory(String userId, List<Map<String, String>> messages) async {
    try {
      final supabase = Supabase.instance.client;
      // Keep only last N messages
      final toSave = messages.length > _maxHistoryMessages
          ? messages.sublist(messages.length - _maxHistoryMessages)
          : messages;

      await supabase.from('ai_chat_history').upsert({
        'user_id': userId,
        'messages': toSave,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Save AI history error: $e');
    }
  }

  Future<void> clearChatHistory(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('ai_chat_history').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('Clear AI history error: $e');
    }
  }

  /// Get last N messages for sending to Groq (context window)
  List<Map<String, String>> getContextMessages(List<Map<String, String>> allMessages) {
    if (allMessages.length <= _contextMessages) return allMessages;
    return allMessages.sublist(allMessages.length - _contextMessages);
  }

  Future<String> getResponse(String msg, List<Map<String, String>> history, {String? imageBase64}) async {
    final user = Supabase.instance.client.auth.currentUser;
    final response = await Supabase.instance.client.functions.invoke(
      'notesy',
      body: {
        'message': msg,
        'history': history,
        'userId': user?.id ?? 'guest_user',
        if (imageBase64 != null) 'imageBase64': imageBase64,
      },
    );

    final data = response.data;
    if (data is Map && data['content'] is String) return data['content'];
    if (data is Map && data['error'] is String) throw Exception(data['error']);
    throw Exception('AI service is temporarily unavailable. Please try again later.');
  }
}

/// Monitors internet connectivity and exposes [isOnline] as a [ValueNotifier].
/// Call [start] once (e.g. in [DashboardPage.initState]) and [dispose] when done.
class ConnectivityService {
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  Timer? _timer;

  void start() {
    _check(); // immediate first check
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    isOnline.dispose();
  }

  Future<void> _check() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (isOnline.value != online) isOnline.value = online;
    } catch (_) {
      if (isOnline.value) isOnline.value = false;
    }
  }
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _windowsReady = false;

  // Channel constants — must match between init() and showNotification()
  static const String _channelId = 'notescache_main';
  static const String _channelName = 'NotesCache Notifications';

  Future<void> init() async {
    if (Platform.isWindows) {
      try {
        await localNotifier.setup(appName: 'NotesCache', shortcutPolicy: ShortcutPolicy.requireCreate);
        _windowsReady = true;
      } catch (e) {
        // Plugin not yet compiled into runner; requires a full `flutter run`, not hot restart.
        debugPrint('local_notifier not ready yet: $e. Do a full stop + run to enable Windows notifications.');
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
        // Pre-register the notification channel so it exists before any notification is shown.
        // On Android 8+ (API 26+) a channel must be registered before use.
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          importance: Importance.max,
        );
        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);

        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('flutter_local_notifications init failed: $e');
    }
  }

  Future<void> showNotification({required String title, required String body}) async {
    debugPrint('NOTIFICATION TRIGGERED: $title - $body');
    if (Platform.isWindows) {
      if (!_windowsReady) {
        debugPrint('Skipping notification; Windows notifier not ready (need full restart).');
        return;
      }
      try {
        LocalNotification notification = LocalNotification(title: title, body: body);
        notification.show();
      } catch (e) {
        debugPrint('Windows notification failed: $e');
      }
      return;
    }
    try {
      // Reference the pre-registered channel by its constant ID
      const android = AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.max,
        priority: Priority.high,
      );
      const ios = DarwinNotificationDetails();
      await _notifications.show(0, title, body, const NotificationDetails(android: android, iOS: ios));
    } catch (e) {
      debugPrint('Notification show failed: $e');
    }
  }
}
