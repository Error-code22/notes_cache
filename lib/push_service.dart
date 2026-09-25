import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles Firebase Cloud Messaging: token registration, foreground
/// messages, and token refresh. Works even when the app is killed —
/// the server (Edge Function) sends pushes via this token.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;

  Future<void> init() async {
    if (kIsWeb) return; // Web push not implemented yet
    if (_initialized) {
      // Already initialized — just re-fetch token (may have rotated while dead)
      try {
        final token = await _fcm.getToken();
        if (token != null) await _registerToken(token);
      } catch (e) {
        debugPrint('Push token refresh error: $e');
      }
      return;
    }
    try {
      // Request permission (Android 13+, iOS)
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: permission denied by user');
        return;
      }

      // Foreground messages — show as local notification
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Token refresh — re-register so server always has current token
      _fcm.onTokenRefresh.listen(_onTokenRefresh);

      // Get initial token and register
      final token = await _fcm.getToken();
      if (token != null) await _registerToken(token);

      // On Android, also get the APNs token equivalent (FCM token works for both)
      _initialized = true;
      debugPrint('Push: initialized, token=${token?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('Push init error: $e');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    await _registerToken(token);
  }

  /// Saves the FCM token to device_tokens table for this user.
  Future<void> _registerToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('device_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'last_seen_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'token',
      );
    } catch (e) {
      debugPrint('Push token register error: $e');
    }
  }

  /// Remove token on logout so dead devices stop receiving pushes.
  Future<void> unregisterToken() async {
    final token = await _fcm.getToken();
    if (token == null) return;
    try {
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('token', token);
    } catch (e) {
      debugPrint('Push token unregister error: $e');
    }
  }

  /// Show a foreground FCM message as a local notification.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('Push foreground: ${message.notification?.title}');
    // The local NotificationService handles rendering —
    // we route through it so settings gates (sound off etc) are respected.
    final title = message.notification?.title ?? message.data['title'] as String?;
    final body = message.notification?.body ?? message.data['body'] as String?;
    if (title != null || body != null) {
      // Use the existing notification channel
      // (NotificationService is provided via Provider — but PushService
      // is a singleton, so we fire a platform channel directly.)
      // Simplest: use flutter_local_notifications through a static hook.
      _onPushReceived?.call(title ?? '', body ?? '');
    }
  }

  /// Set by NotificationService during init so foreground FCM messages
  /// render through the same local notification pipeline (settings-aware).
  void Function(String title, String body)? _onPushReceived;
  void setOnPushReceived(void Function(String, String) fn) {
    _onPushReceived = fn;
  }
}
