import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class AuthService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  UserProfile? _currentUser;
  bool _isLoading = false;

  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  AuthService() {
    // Attempt to recover session on startup
    _recoverSession();
  }

  Future<void> _recoverSession() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _fetchUserProfile(session.user);
    }
  }

  Future<void> signIn(String email, String password) async {
    _setLoading(true);
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        await _fetchUserProfile(response.user!);
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signUp(String email, String password, String fullName, int yearLevel) async {
    _setLoading(true);
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'year_level': yearLevel,
          'role': 'student', // Default to student
        },
      );
      
      // Note: In Supabase, profiles are often created via a Trigger. 
      // If no trigger exists, we would manually insert here.
      if (response.user != null) {
        await _fetchUserProfile(response.user!);
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _fetchUserProfile(User user) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      
      _currentUser = UserProfile.fromMap(data, user.email!);
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      // If profile doesn't exist, create a temporary one or handle error
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> ensureFriendCode() async {
    if (_currentUser == null || _currentUser!.friendCode != null) return;

    final noteService = NoteService();
    final newCode = noteService.generateFriendCode();

    try {
      await _supabase.from('profiles').update({'friend_code': newCode}).eq('id', _currentUser!.id);
      
      // Refresh local user profile
      final updatedData = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(updatedData, _currentUser!.email);
      notifyListeners();
    } catch (e) {
      debugPrint('Error generating friend code: $e');
    }
  }

  Future<void> updateProfile({String? fullName, String? bio, List<String>? interests}) async {
    if (_currentUser == null) return;
    
    _setLoading(true);
    try {
      final updates = {
        if (fullName != null) 'full_name': fullName,
        if (bio != null) 'bio': bio,
        if (interests != null) 'interests': interests,
      };

      await _supabase.from('profiles').update(updates).eq('id', _currentUser!.id);
      
      // Refresh local user
      final data = await _supabase.from('profiles').select().eq('id', _currentUser!.id).single();
      _currentUser = UserProfile.fromMap(data, _currentUser!.email);
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

class NoteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String generateFriendCode() {
    final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No confusing 0, O, 1, I
    final random = DateTime.now().millisecondsSinceEpoch;
    return '${chars[random % 32]}${chars[(random ~/ 32) % 32]}${chars[(random ~/ 1024) % 32]}-${chars[(random ~/ 32768) % 32]}${chars[(random ~/ 1048576) % 32]}${chars[(random ~/ 33554432) % 32]}';
  }

  Future<List<Note>> getNotesForUser(UserProfile user) async {
    try {
      // Real database query filtered by year level
      // Note: We use .rpc or .select() based on your Supabase structure
      var query = _supabase.from('notes').select();

      // If student, filter by their year level
      if (user.role == UserRole.student && user.yearLevel != null) {
        query = query.eq('target_year', user.yearLevel!);
      }

      final List<dynamic> data = await query;
      
      return data.map((item) => Note(
        id: item['id'].toString(),
        title: item['title'],
        content: item['content'],
        lecturerName: item['lecturer_name'],
        targetYear: item['target_year'],
        createdAt: DateTime.parse(item['created_at']),
        semester: item['semester'],
      )).toList();
    } catch (e) {
      debugPrint('Error fetching notes: $e');
      return [];
    }
  }

  Future<bool> saveNote({
    required String title,
    required String lecturerName,
    required int targetYear,
    required int semester,
    String? gDriveId,
    String? content,
  }) async {
    try {
      await _supabase.from('notes').insert({
        'title': title,
        'lecturer_name': lecturerName,
        'target_year': targetYear,
        'semester': semester,
        'gdrive_id': gDriveId,
        'content': content ?? '',
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error saving note: $e');
      return false;
    }
  }

  Future<String> getDocumentsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
}
