import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UserRole { student, lecturer, admin, moderator }

class UserProfile {
  final String id;
  final String email;
  final String? fullName;
  final List<UserRole> roles;
  final int? yearLevel;
  final String? bio;
  final List<String>? interests;
  final String? avatarUrl;
  final String? friendCode;
  final bool isGuest;
  final bool yearChanged;
  final DateTime? lastYearUpdate;
  
  // Theme Preferences
  final String themeMode; // 'light', 'dark', 'system'
  final int themeColor;   // Seed color value
  final String themeFont;
  final bool isProfilePublic;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    required this.roles,
    this.yearLevel,
    this.bio,
    this.interests,
    this.avatarUrl,
    this.friendCode,
    this.isGuest = false,
    this.yearChanged = false,
    this.lastYearUpdate,
    this.themeMode = 'system',
    this.themeColor = 0xFF1A237E,
    this.themeFont = 'Inter',
    this.isProfilePublic = true,
  });

  bool hasRole(UserRole r) => roles.contains(r);

  factory UserProfile.fromMap(Map<String, dynamic> map, String email) {
    final roleRaw = (map['role'] as String? ?? 'student').toLowerCase();
    final roleList = roleRaw.split(',').map((s) => s.trim()).toList();
    
    List<UserRole> roles = [];
    for (var r in roleList) {
      if (r == 'admin') roles.add(UserRole.admin);
      else if (r == 'lecturer') roles.add(UserRole.lecturer);
      else if (r == 'moderator') roles.add(UserRole.moderator);
      else roles.add(UserRole.student);
    }
    if (roles.isEmpty) roles.add(UserRole.student);

    return UserProfile(
      id: map['id'],
      email: email,
      fullName: map['full_name'],
      roles: roles,
      yearLevel: map['year_level'],
      bio: map['bio'],
      interests: map['interests'] != null ? List<String>.from(map['interests']) : null,
      avatarUrl: map['avatar_url'],
      friendCode: map['friend_code'],
      isGuest: map['is_guest'] ?? false,
      yearChanged: map['year_changed'] ?? false,
      lastYearUpdate: map['last_year_update'] != null ? DateTime.parse(map['last_year_update']) : null,
      themeMode: map['theme_mode'] ?? 'system',
      themeColor: map['theme_color'] ?? 0xFF1A237E,
      themeFont: map['theme_font'] ?? 'Inter',
      isProfilePublic: map['is_profile_public'] ?? true,
    );
  }
}

class Note {
  final String id;
  final String title;
  final String content;
  final String lecturerName;
  final int targetYear;
  final DateTime createdAt;
  final int semester;
  final String? gDriveId;
  final String? category;
  final String? summary;
  final bool isFromCache;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.lecturerName,
    required this.targetYear,
    required this.createdAt,
    required this.semester,
    this.gDriveId,
    this.category,
    this.summary,
    this.isFromCache = false,
  });

  factory Note.fromMap(Map<String, dynamic> map, {bool isFromCache = false}) {
    return Note(
      id: map['id'].toString(),
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      lecturerName: map['lecturer_name'] ?? '',
      targetYear: map['target_year'] ?? 1,
      createdAt: DateTime.parse(map['created_at']),
      semester: map['semester'] ?? 1,
      gDriveId: map['gdrive_id'],
      category: map['category'],
      summary: map['summary'],
      isFromCache: isFromCache,
    );
  }
}

class UserActivity {
  final String id;
  final String title;
  final String description;
  final DateTime timestamp;
  final String type;

  UserActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.type,
  });
}

class ChatRoom {
  final String id;
  final String name;
  final bool isGroup;
  final bool isPublic;
  final String? description;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? imageUrl;
  final List<String> memberIds;
  final String? createdBy;
  final List<String>? lastMessageReadBy;

  ChatRoom({
    required this.id,
    required this.name,
    required this.isGroup,
    this.isPublic = false,
    this.description,
    this.lastMessage,
    this.lastMessageTime,
    this.imageUrl,
    required this.memberIds,
    this.createdBy,
    this.lastMessageReadBy,
  });

  factory ChatRoom.fromMap(Map<String, dynamic> map) {
    return ChatRoom(
      id: map['id'],
      name: map['name'] ?? 'Chat',
      isGroup: map['is_group'] ?? false,
      isPublic: map['is_public'] ?? false,
      description: map['description'],
      lastMessage: map['last_message'],
      lastMessageTime: map['last_message_time'] != null ? DateTime.parse(map['last_message_time']) : null,
      imageUrl: map['image_url'],
      memberIds: List<String>.from(map['member_ids'] ?? []),
      createdBy: map['created_by'],
      lastMessageReadBy: map['last_message_read_by'] != null
          ? List<String>.from((map['last_message_read_by'] as List).map((e) => e.toString()))
          : null,
    );
  }
}

class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final String? senderName;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.senderName,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'].toString(),
      roomId: map['room_id'],
      senderId: map['sender_id'],
      content: map['content'],
      timestamp: DateTime.parse(map['created_at']),
      senderName: map['sender_name'],
    );
  }
}

class FriendRelation {
  final String userId;
  final String friendId;
  final String status; // 'pending', 'accepted'
  final UserProfile? friendProfile;

  FriendRelation({
    required this.userId,
    required this.friendId,
    required this.status,
    this.friendProfile,
  });
}

class AppFeedback {
  final String id;
  final String userId;
  final String type; // 'bug' or 'feature'
  final String content;
  final DateTime createdAt;
  String? userName;

  AppFeedback({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    required this.createdAt,
    this.userName,
  });

  factory AppFeedback.fromMap(Map<String, dynamic> map) {
    return AppFeedback(
      id: map['id'].toString(),
      userId: map['user_id'],
      type: map['type'] ?? 'bug',
      content: map['content'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      userName: map['profiles'] != null ? map['profiles']['full_name'] : null,
    );
  }
}
