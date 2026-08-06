import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services.dart';
import 'feedback_page.dart';
import 'profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Toggle states
  bool _notificationsEnabled = true;
  bool _emailUpdates = true;
  bool _notificationSound = true;
  bool _autoBackup = false;
  bool _profilePublic = true;

  // Text scaling
  double _textScale = 1.0;

  // Data
  Map<String, String> _appConfig = {};
  String _cacheSize = 'Calculating...';

  // Services
  late AuthService _authService;
  late NoteService _noteService;

  static const String _prefNotifications = 'settings_notifications';
  static const String _prefEmailUpdates = 'settings_email_updates';
  static const String _prefNotificationSound = 'settings_notification_sound';
  static const String _prefAutoBackup = 'settings_auto_backup';

  @override
  void initState() {
    super.initState();
    _authService = context.read<AuthService>();
    _noteService = context.read<NoteService>();
    final themeProvider = context.read<ThemeProvider>();
    _textScale = themeProvider.textScale;
    _loadSettings();
    _loadConfig();
    _calculateCacheSize();
    _syncProfilePublic();
  }

  Future<void> _syncProfilePublic() async {
    final user = _authService.currentUser;
    if (user != null && mounted) {
      setState(() => _profilePublic = user.isProfilePublic);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool(_prefNotifications) ?? true;
        _emailUpdates = prefs.getBool(_prefEmailUpdates) ?? true;
        _notificationSound = prefs.getBool(_prefNotificationSound) ?? true;
        _autoBackup = prefs.getBool(_prefAutoBackup) ?? false;
      });
    }
  }

  Future<void> _loadConfig() async {
    final config = await _noteService.getAppConfig();
    if (mounted) {
      setState(() => _appConfig = config);
    }
  }

  Future<void> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        int totalSize = 0;
        await for (final entity in tempDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
        final size = totalSize < 1024
            ? '$totalSize B'
            : totalSize < 1024 * 1024
                ? '${(totalSize / 1024).toStringAsFixed(1)} KB'
                : '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
        if (mounted) setState(() => _cacheSize = size);
      } else {
        if (mounted) setState(() => _cacheSize = 'Empty');
      }
    } catch (_) {
      if (mounted) setState(() => _cacheSize = 'Unknown');
    }
  }

  // ─── Persistence helpers ──────────────────────────────────────────

  Future<void> _setBoolPref(String key, bool value) async {
    (await SharedPreferences.getInstance()).setBool(key, value);
  }

  // ─── Actions ──────────────────────────────────────────────────────

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text('This removes downloaded files and temporary data from this device. Your notes, backups and account are not affected. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing cache: $e')),
        );
      }
    }
  }

  void _testNotification() {
    final notificationService = context.read<NotificationService>();
    notificationService.showNotification(
      title: 'NotesCache Test',
      body: 'Notifications are working perfectly!',
    );
  }

  /// Exports the user's notes and profile as a shareable JSON file.
  Future<void> _exportMyData() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = _authService.currentUser;
      if (user == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Sign in to export your data.'), backgroundColor: Colors.orange));
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('Preparing your export...'), backgroundColor: Colors.blue));
      final notes = await _noteService.getNotesForUser(user);
      final data = {
        'exported_at': DateTime.now().toIso8601String(),
        'user': {
          'id': user.id,
          'email': user.email,
          'full_name': user.fullName,
          'year_level': user.yearLevel,
        },
        'notes': notes
            .map((n) => {
                  'title': n.title,
                  'lecturer': n.lecturerName,
                  'year': n.targetYear,
                  'semester': n.semester,
                  'category': n.category,
                  'summary': n.summary,
                  'file_url': n.gDriveId,
                })
            .toList(),
      };
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/notescache_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')], text: 'NotesCache data export');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  /// Shows the user's AI usage against their daily limits.
  Future<void> _showUsageStats() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to see your usage.'), backgroundColor: Colors.orange));
      return;
    }
    final ai = AiChatService();
    final todayLocal = await ai.getDailyMessageCount(user.id);

    var serverText = 0;
    var serverImage = 0;
    try {
      final usage = await Supabase.instance.client
          .from('user_ai_usage')
          .select('text_count, image_count')
          .eq('user_id', user.id)
          .maybeSingle();
      serverText = (usage?['text_count'] as num?)?.toInt() ?? 0;
      serverImage = (usage?['image_count'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    final textLimit = int.tryParse(_appConfig['ai_daily_text_limit'] ?? '') ?? 50;
    final imageLimit = int.tryParse(_appConfig['ai_daily_image_limit'] ?? '') ?? 10;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI Usage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _usageRow('Text messages today', serverText, textLimit),
            const SizedBox(height: 12),
            _usageRow('Image analyses today', serverImage, imageLimit),
            const Divider(height: 32),
            Text('Local counter (this device): $todayLocal', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('Limits reset daily.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _usageRow(String label, int used, int limit) {
    final fraction = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            Text('$used / $limit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.grey.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(fraction >= 0.8 ? Colors.red : Colors.teal),
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSupportHub() {
    final theme = Theme.of(context);
    final email = _appConfig['support_email'] ?? 'support@notescache.com';
    final phone = _appConfig['support_phone'] ?? '+254700000000';
    final whatsapp = _appConfig['support_whatsapp'] ?? '254700000000';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Contact Support',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We usually respond within 24 hours',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              _buildContactTile(
                Icons.email_outlined,
                'Email Us',
                email,
                () => _launchUrl('mailto:$email'),
              ),
              const SizedBox(height: 12),
              _buildContactTile(
                Icons.chat_outlined,
                'WhatsApp',
                'Chat instantly',
                () => _launchUrl('https://wa.me/$whatsapp'),
              ),
              const SizedBox(height: 12),
              _buildContactTile(
                Icons.phone_android_rounded,
                'Call Support',
                phone,
                () => _launchUrl('tel:$phone'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showMpesaSupport() {
    final theme = Theme.of(context);
    final mpesaNo = _appConfig['mpesa_no'] ?? '123456';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.red, size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Support NotesCache', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your support helps us keep the servers running and the library growing for all students.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'M-PESA TILL / PAYBILL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mpesaNo,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _launchUrl('tel:*334#'),
                icon: const Icon(Icons.send_to_mobile_rounded),
                label: const Text('OPEN M-PESA MENU'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final formKey = GlobalKey<FormState>();
    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentPwController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPwController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.length < 6 ? 'At least 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmPwController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v != newPwController.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(password: newPwController.text),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password updated!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            'Delete Account',
            style: TextStyle(color: Colors.red),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This action is irreversible. All your data — notes, messages, '
                'and profile — will be permanently deleted.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Type "DELETE" to confirm:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'DELETE',
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: confirmController.text == 'DELETE'
                  ? () async {
                      Navigator.pop(ctx);
                      final success = await _authService.deleteAccount();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? 'Account deleted successfully' : 'Failed to delete account'),
                            backgroundColor: success ? Colors.green : Colors.red,
                          ),
                        );
                        if (success) Navigator.of(context).pushReplacementNamed('/login');
                      }
                    }
                  : null,
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleProfileVisibility(bool value) async {
    setState(() => _profilePublic = value);
    await _authService.updateProfilePublic(value);
  }

  void _showResetDefaultsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will reset all settings to their original values. '
          'Your account data and notes will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _resetToDefaults();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNotifications);
    await prefs.remove(_prefEmailUpdates);
    await prefs.remove(_prefNotificationSound);
    await prefs.remove(_prefAutoBackup);

    // Reset theme to system default
    final themeProvider = context.read<ThemeProvider>();
    await themeProvider.setThemeMode(ThemeMode.system);
    await themeProvider.setSeedColor(const Color(0xFF1A237E));
    await themeProvider.setFontFamily('Inter');
    await themeProvider.setTextScale(1.0);

    setState(() {
      _notificationsEnabled = true;
      _emailUpdates = true;
      _notificationSound = true;
      _autoBackup = false;
      _textScale = 1.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings reset to defaults'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ─── UI Builders ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('App Settings'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Appearance ────────────────────────────────────────────
          _buildSectionHeader('Appearance'),
          _buildSettingsCard([
            _buildThemeModeTile(themeProvider),
            const Divider(height: 1),
            _buildColorTile(themeProvider),
            const Divider(height: 1),
            _buildFontTile(themeProvider),
            const Divider(height: 1),
            _buildTextScaleTile(themeProvider),
          ]),
          const SizedBox(height: 24),

          // ── Account ───────────────────────────────────────────────
          if (_authService.currentUser != null) ...[
            _buildSectionHeader('Account'),
            _buildSettingsCard([
              _buildActionTile(
                'Edit Profile',
                'Update your name, bio, and avatar',
                Icons.person_outline,
                Colors.blue,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                ),
              ),
              const Divider(height: 1),
              _buildActionTile(
                'Change Password',
                'Update your account password',
                Icons.lock_outline,
                Colors.orange,
                _showChangePasswordDialog,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text(
                  'Public Profile',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  'Let others find you by name',
                  style: TextStyle(fontSize: 12),
                ),
                value: _profilePublic,
                activeColor: themeProvider.seedColor,
                onChanged: _toggleProfileVisibility,
              ),
              const Divider(height: 1),
              _buildActionTile(
                'Delete Account',
                'Permanently remove your account and data',
                Icons.delete_forever_outlined,
                Colors.red,
                _showDeleteAccountDialog,
              ),
            ]),
            const SizedBox(height: 24),
          ],

          // ── Notifications ─────────────────────────────────────────
          _buildSectionHeader('Notifications'),
          _buildSettingsCard([
            SwitchListTile(
              title: const Text(
                'Push Notifications',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Receive updates about new notes',
                style: TextStyle(fontSize: 12),
              ),
              value: _notificationsEnabled,
              activeColor: themeProvider.seedColor,
              onChanged: (val) {
                setState(() => _notificationsEnabled = val);
                _setBoolPref(_prefNotifications, val);
                if (val) _testNotification();
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text(
                'Email Updates',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Notifications via email for important updates',
                style: TextStyle(fontSize: 12),
              ),
              value: _emailUpdates,
              activeColor: themeProvider.seedColor,
              onChanged: (val) {
                setState(() => _emailUpdates = val);
                _setBoolPref(_prefEmailUpdates, val);
                if (val && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Email updates enabled'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text(
                'Notification Sound',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Play sound when notifications arrive',
                style: TextStyle(fontSize: 12),
              ),
              value: _notificationSound,
              activeColor: themeProvider.seedColor,
              onChanged: (val) {
                setState(() => _notificationSound = val);
                _setBoolPref(_prefNotificationSound, val);
              },
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Test Notification',
              'Send a test ping to this device',
              Icons.notification_important_outlined,
              Colors.indigo,
              _testNotification,
            ),
          ]),
          const SizedBox(height: 24),

          // ── AI & Usage ────────────────────────────────────────────
          _buildSectionHeader('AI & Usage'),
          _buildSettingsCard([
            _buildInfoTile(
              Icons.auto_awesome,
              'Notesy AI',
              'Ask questions, get summaries, study help',
              Colors.purple,
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Usage Statistics',
              'View your AI query history and limits',
              Icons.bar_chart_rounded,
              Colors.teal,
              _showUsageStats,
            ),
          ]),
          const SizedBox(height: 24),

          // ── Data & Storage ────────────────────────────────────────
          _buildSectionHeader('Data & Storage'),
          _buildSettingsCard([
            _buildInfoTile(
              Icons.storage_rounded,
              'Cached Data',
              _cacheSize,
              Colors.blueGrey,
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Clear Cache',
              'Free up local storage space',
              Icons.cleaning_services_rounded,
              Colors.orange,
              _clearCache,
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text(
                'Auto Backup',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Automatically backup your data',
                style: TextStyle(fontSize: 12),
              ),
              value: _autoBackup,
              activeColor: themeProvider.seedColor,
              onChanged: (val) {
                setState(() => _autoBackup = val);
                _setBoolPref(_prefAutoBackup, val);
                if (val && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Auto backup enabled'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Export My Data',
              'Download a copy of your notes and activity',
              Icons.file_download_outlined,
              Colors.green,
              _exportMyData,
            ),
          ]),
          const SizedBox(height: 24),

          // ── Support & About ───────────────────────────────────────
          _buildSectionHeader('Support & About'),
          _buildSettingsCard([
            _buildActionTile(
              'Report a Bug',
              'Tell us what is not working',
              Icons.bug_report_outlined,
              Colors.red,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FeedbackPage()),
              ),
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Help Centre',
              'Contact our support team',
              Icons.support_agent_rounded,
              Colors.green,
              _showSupportHub,
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Support NotesCache',
              'Contribute via M-Pesa',
              Icons.favorite_rounded,
              Colors.red,
              _showMpesaSupport,
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Privacy Policy',
              'How we handle your data',
              Icons.privacy_tip_outlined,
              Colors.indigo,
              () => _showConfigDialog(
                'Privacy Policy',
                _appConfig['privacy_policy'] ??
                    'NOTESCACHE PRIVACY POLICY\n\n'
                    'We value your privacy. NotesCache collects only the '
                    'information you provide — your name, email, academic year, '
                    'and uploaded notes — solely for the purpose of providing '
                    'our study companion service.\n\n'
                    'Your data is stored securely on Supabase with encryption '
                    'at rest. We never share your personal information with '
                    'third parties.\n\n'
                    'You may request data deletion at any time via the '
                    'Delete Account option in Settings.',
              ),
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Terms of Service',
              'Rules and guidelines for using NotesCache',
              Icons.description_outlined,
              Colors.brown,
              () => _showConfigDialog(
                'Terms of Service',
                _appConfig['terms_and_conditions'] ??
                    'NOTESCACHE TERMS OF SERVICE\n\n'
                    'Last Updated: June 2026\n\n'
                    '1. By using NotesCache you agree to these terms.\n\n'
                    '2. You must be a currently enrolled student or staff '
                    'member at a recognized educational institution.\n\n'
                    '3. You are responsible for your account and its content.\n\n'
                    '4. Notes uploaded remain your property but are shared '
                    'within the app for educational purposes.\n\n'
                    '5. AI responses (Notesy) are for guidance only — always '
                    'verify with official course materials.\n\n'
                    '6. We reserve the right to remove content that violates '
                    'these terms.',
              ),
            ),
            const Divider(height: 1),
            _buildActionTile(
              'About NotesCache',
              'Version 1.0.0+1 — Campus Study Companion',
              Icons.info_outline_rounded,
              Colors.grey,
              () => _showConfigDialog(
                'About',
                _appConfig['about_text'] ??
                    'NotesCache v1.0.0\n\n'
                    'Your campus study companion. Access lecture notes, chat '
                    'with classmates, and get instant AI-powered help — all in '
                    'one place.\n\n'
                    'Built for students, by students.\n\n'
                    '© 2026 NotesCache. All rights reserved.\n\n'
                    'Powered by Supabase, Groq AI, and Flutter.',
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // ── System ────────────────────────────────────────────────
          _buildSectionHeader('System'),
          _buildSettingsCard([
            _buildActionTile(
              'Reset to Defaults',
              'Restore all settings to their original values',
              Icons.restart_alt_rounded,
              Colors.red,
              _showResetDefaultsDialog,
            ),
          ]),
          const SizedBox(height: 40),

          Center(
            child: Text(
              'NotesCache v1.0.0+1',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Reusable Widgets ─────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildThemeModeTile(ThemeProvider provider) {
    return ListTile(
      leading: const Icon(Icons.brightness_4_outlined),
      title: const Text(
        'Theme Mode',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        provider.themeMode.name.toUpperCase(),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showSelectionDialog(
        'Select Theme',
        ['light', 'dark', 'system'],
        (val) {
          if (val == 'light') provider.setThemeMode(ThemeMode.light);
          else if (val == 'dark') provider.setThemeMode(ThemeMode.dark);
          else provider.setThemeMode(ThemeMode.system);
        },
      ),
    );
  }

  Widget _buildColorTile(ThemeProvider provider) {
    final colors = {
      'Deep Navy': const Color(0xFF1A237E),
      'Royal Purple': const Color(0xFF673AB7),
      'Forest Green': const Color(0xFF2E7D32),
      'Crimson Red': const Color(0xFFC62828),
      'Amber Gold': const Color(0xFFFFA000),
      'Slate Grey': const Color(0xFF455A64),
    };

    return ListTile(
      leading: Icon(Icons.palette_outlined, color: provider.seedColor),
      title: const Text(
        'Primary Color',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: const Text(
        'Personalize your workspace',
        style: TextStyle(fontSize: 12),
      ),
      trailing: CircleAvatar(radius: 12, backgroundColor: provider.seedColor),
      onTap: () => _showSelectionDialog(
        'Select Color',
        colors.keys.toList(),
        (val) => provider.setSeedColor(colors[val]!),
      ),
    );
  }

  Widget _buildFontTile(ThemeProvider provider) {
    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: const Text(
        'App Font',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        provider.fontFamily,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showSelectionDialog(
        'Select Font',
        [
          'Inter',
          'Roboto',
          'Open Sans',
          'Lato',
          'Caveat',
          'Indie Flower',
        ],
        (val) => provider.setFontFamily(val),
      ),
    );
  }

  Widget _buildTextScaleTile(ThemeProvider provider) {
    return ListTile(
      leading: const Icon(Icons.text_fields_rounded),
      title: const Text(
        'Text Size',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${_textScale.toStringAsFixed(1)}x — ${_textScale < 1.0 ? 'Smaller' : _textScale > 1.0 ? 'Larger' : 'Default'}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: SizedBox(
        width: 120,
        child: Slider(
          value: _textScale,
          min: 0.7,
          max: 1.5,
          divisions: 8,
          activeColor: provider.seedColor,
          label: '${_textScale.toStringAsFixed(1)}x',
          onChanged: (val) {
            setState(() => _textScale = val);
            provider.setTextScale(val);
          },
        ),
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildContactTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.dividerColor.withOpacity(0.1),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_outward_rounded,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────────

  void _showSelectionDialog(
    String title,
    List<String> options,
    Function(String) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...options.map(
              (opt) => ListTile(
                title: Text(opt, textAlign: TextAlign.center),
                onTap: () {
                  onSelect(opt);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfigDialog(String title, String content) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: content.contains('\n')
              ? SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                )
              : Text(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}