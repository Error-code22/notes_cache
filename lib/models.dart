import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UserRole { student, lecturer, admin }

class UserProfile {
  final String id;
  final String email;
  final String? fullName;
  final UserRole role;
  final int? yearLevel;
  final String? bio;
  final List<String>? interests;
  final String? avatarUrl;
  final String? friendCode;

  UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    required this.role,
    this.yearLevel,
    this.bio,
    this.interests,
    this.avatarUrl,
    this.friendCode,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, String email) {
    final roleStr = (map['role'] as String? ?? 'student').toLowerCase();
    UserRole role = UserRole.student;
    if (roleStr == 'admin') role = UserRole.admin;
    if (roleStr == 'lecturer') role = UserRole.lecturer;

    return UserProfile(
      id: map['id'],
      email: email,
      fullName: map['full_name'],
      role: role,
      yearLevel: map['year_level'],
      bio: map['bio'],
      interests: map['interests'] != null ? List<String>.from(map['interests']) : null,
      avatarUrl: map['avatar_url'],
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

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.lecturerName,
    required this.targetYear,
    required this.createdAt,
    required this.semester,
  });
}
