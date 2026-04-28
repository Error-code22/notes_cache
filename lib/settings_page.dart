import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  // ignore: unused_field
  bool _emailUpdates = false;
  Map<String, String> _appConfig = {};

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final noteService = context.read<NoteService>();
    final config = await noteService.getAppConfig();
    if (mounted) {
      setState(() => _appConfig = config);
    }
  }

  Future<void> _clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Cache cleared successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error clearing cache: $e')),
        );
      }
    }
  }

  void _testNotification() {
    final notificationService = context.read<NotificationService>();
    notificationService.showNotification(
      title: 'NotesCache Test',
      body: 'Notifications are working perfectly! 🚀',
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
              Text('Contact Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              const SizedBox(height: 8),
              const Text('We usually respond within 24 hours', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 24),
              _buildContactButton(Icons.email_outlined, 'Email Us', email, () => _launchUrl('mailto:$email')),
              const SizedBox(height: 12),
              _buildContactButton(Icons.chat_outlined, 'WhatsApp', 'Chat instantly', () => _launchUrl('https://wa.me/$whatsapp')),
              const SizedBox(height: 12),
              _buildContactButton(Icons.phone_android_rounded, 'Call Support', phone, () => _launchUrl('tel:$phone')),
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
            const Expanded(child: Text('Support NotesCache', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your support helps us keep the servers running and the library growing for all students.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Text('M-PESA TILL / PAYBILL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 8),
                  Text(mpesaNo, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _launchUrl('tel:*334#'), // Opens M-Pesa USSD
                icon: const Icon(Icons.send_to_mobile_rounded),
                label: const Text('OPEN M-PESA MENU'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Widget _buildContactButton(IconData icon, String title, String subtitle, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: theme.dividerColor.withOpacity(0.1)), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_outward_rounded, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
          _buildSectionHeader('Appearance'),
          _buildSettingsCard([
            _buildThemeModeTile(themeProvider),
            const Divider(height: 1),
            _buildColorTile(themeProvider),
            const Divider(height: 1),
            _buildFontTile(themeProvider),
          ]),
          const SizedBox(height: 24),
          
          _buildSectionHeader('Notifications'),
          _buildSettingsCard([
            SwitchListTile(
              title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('Receive updates about new notes', style: TextStyle(fontSize: 12)),
              value: _notificationsEnabled,
              activeColor: themeProvider.seedColor,
              onChanged: (val) {
                setState(() => _notificationsEnabled = val);
                if (val) _testNotification();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.notification_important_outlined, color: themeProvider.seedColor),
              title: const Text('Test Notification'),
              subtitle: const Text('Send a test ping to this device', style: TextStyle(fontSize: 12)),
              onTap: _testNotification,
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionHeader('Support & About'),
          _buildSettingsCard([
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
              'Buy us a coffee via M-Pesa',
              Icons.favorite_rounded,
              Colors.red,
              _showMpesaSupport,
            ),
            const Divider(height: 1),
            _buildActionTile(
              'Privacy Policy',
              'View terms of service',
              Icons.privacy_tip_outlined,
              Colors.indigo,
              () => _showConfigDialog('Privacy Policy', _appConfig['privacy_policy'] ?? ''),
            ),
            const Divider(height: 1),
            _buildActionTile(
              'About NotesCache',
              'Version 1.0.0+1 - Academic Storage',
              Icons.info_outline_rounded,
              Colors.grey,
              () => _showConfigDialog('About', _appConfig['about_text'] ?? ''),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionHeader('System'),
          _buildSettingsCard([
            _buildActionTile(
              'Clear Cache',
              'Free up local storage',
              Icons.cleaning_services_rounded,
              Colors.orange,
              _clearCache,
            ),
          ]),
          const SizedBox(height: 40),
          
          Center(
            child: Text(
              'NotesCache v1.0.0+1',
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

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
      title: const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(provider.themeMode.name.toUpperCase(), style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showSelectionDialog('Select Theme', ['light', 'dark', 'system'], (val) {
        if (val == 'light') provider.setThemeMode(ThemeMode.light);
        else if (val == 'dark') provider.setThemeMode(ThemeMode.dark);
        else provider.setThemeMode(ThemeMode.system);
      }),
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
      title: const Text('Primary Color', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: const Text('Personalize your workspace', style: TextStyle(fontSize: 12)),
      trailing: CircleAvatar(radius: 12, backgroundColor: provider.seedColor),
      onTap: () => _showSelectionDialog('Select Color', colors.keys.toList(), (val) {
        provider.setSeedColor(colors[val]!);
      }),
    );
  }

  Widget _buildFontTile(ThemeProvider provider) {
    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: const Text('App Font', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(provider.fontFamily, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showSelectionDialog('Select Font', ['Inter', 'Roboto', 'Open Sans', 'Lato', 'Caveat', 'Indie Flower'], (val) {
        provider.setFontFamily(val);
      }),
    );
  }

  Widget _buildActionTile(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showSelectionDialog(String title, List<String> options, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...options.map((opt) => ListTile(
              title: Text(opt, textAlign: TextAlign.center),
              onTap: () {
                onSelect(opt);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showConfigDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
        ],
      ),
    );
  }
}
