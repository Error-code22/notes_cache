import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'services.dart';
import 'models.dart';
import 'admin_dashboard_page.dart';
import 'feedback_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _bioController;
  late TextEditingController _nameController;
  Duration _selectedPeriod = const Duration(days: 7);
  bool _isProfilePublic = true;
  bool _isUploadingAvatar = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  Map<String, String> _appConfig = {};
  List<UserIdentity> _linkedIdentities = [];
  bool _loadingIdentities = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final authService = context.read<AuthService>();
    final user = authService.currentUser!;
    _bioController = TextEditingController(text: user.bio);
    _nameController = TextEditingController(text: user.fullName);
    _isProfilePublic = user.isProfilePublic;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      authService.ensureFriendCode();
      _loadAppConfig();
      _loadLinkedIdentities();
    });
  }

  Future<void> _loadAppConfig() async {
    final noteService = context.read<NoteService>();
    final config = await noteService.getAppConfig();
    if (mounted) setState(() => _appConfig = config);
  }

  Future<void> _loadLinkedIdentities() async {
    final authService = context.read<AuthService>();
    final identities = await authService.getLinkedProviders();
    if (mounted) setState(() {
      _linkedIdentities = identities;
      _loadingIdentities = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bioController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final authService = context.read<AuthService>();
    final online = await authService.isOnline();
    if (!online) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    try {
      final result = await FilePicker.pickFiles(type: FileType.image, allowMultiple: false);
      if (result != null && result.files.single.path != null && mounted) {
        setState(() => _isUploadingAvatar = true);
        final success = await authService.updateProfileImage(File(result.files.single.path!));
        if (mounted) {
          setState(() => _isUploadingAvatar = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(success ? 'Profile photo updated!' : 'Failed — max 2MB, JPG/PNG/WebP only'),
            backgroundColor: success ? Colors.green : Colors.red,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final authService = context.read<AuthService>();
    await authService.updateProfileDetails(fullName: _nameController.text, bio: _bioController.text);
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser!;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (user.hasRole(UserRole.admin))
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboardPage())),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context, authService),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              image: DecorationImage(
                                image: NetworkImage(user.avatarUrl ?? AuthService.getDefaultAvatarUrl(user.fullName, user.id)),
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: _isUploadingAvatar
                                ? Container(
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20)),
                                    child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: -4,
                            right: -4,
                            child: InkWell(
                              onTap: _isUploadingAvatar ? null : _pickAndUploadImage,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: _isUploadingAvatar ? Colors.grey : primaryColor,
                                child: const Icon(Icons.edit, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullName ?? 'Student', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                            Text(user.email, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: _getRoleColor(user).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(_getRoleLabel(user), style: TextStyle(fontSize: 11, color: _getRoleColor(user), fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 8),
                            _buildFriendCodeBadge(context, user.friendCode ?? '------'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(user.bio!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.8))),
                  ],
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: primaryColor,
              unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
              tabs: const [Tab(text: 'Edit'), Tab(text: 'Activity'), Tab(text: 'Settings')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProfileEditTab(context, user),
                  _buildActivityTab(context, user),
                  _buildAccountSettingsTab(context, user),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== EDIT TAB ====================

  Widget _buildProfileEditTab(BuildContext context, UserProfile user) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputField(context, 'Full Name', _nameController, Icons.person_outline),
          const SizedBox(height: 16),
          _buildInputField(context, 'Bio', _bioController, Icons.edit_note_outlined, maxLines: 3),
          const SizedBox(height: 16),
          // Year Level Selector
          Text('Year Level', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: user.yearLevel ?? 1,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.school_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Year 1')),
              DropdownMenuItem(value: 2, child: Text('Year 2')),
              DropdownMenuItem(value: 3, child: Text('Year 3')),
              DropdownMenuItem(value: 4, child: Text('Year 4')),
            ],
            onChanged: user.yearChanged ? null : (val) {
              if (val != null) _changeYearLevel(val);
            },
          ),
          if (user.yearChanged)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Year level can only be changed once', style: TextStyle(fontSize: 12, color: Colors.orange[700])),
            ),
          const SizedBox(height: 24),
          // Save Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Theme Settings
          _buildThemeSection(context),
        ],
      ),
    );
  }

  Widget _buildThemeSection(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final colors = [
      const Color(0xFF1A237E), const Color(0xFF1565C0), const Color(0xFF00838F),
      const Color(0xFF2E7D32), const Color(0xFF6A1B9A), const Color(0xFFC62828),
      const Color(0xFFE65100), const Color(0xFF4E342E),
    ];
    final fonts = ['Inter', 'Roboto', 'Poppins', 'Open Sans'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text('THEME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.colorScheme.onSurface.withOpacity(0.6))),
        const SizedBox(height: 12),
        // Theme Mode
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16), label: Text('Light')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16), label: Text('Auto')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16), label: Text('Dark')),
          ],
          selected: {themeProvider.themeMode},
          onSelectionChanged: (s) => themeProvider.setThemeMode(s.first),
        ),
        const SizedBox(height: 16),
        // Color Picker
        Text('Accent Color', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) {
            final selected = themeProvider.seedColor.value == c.value;
            return GestureDetector(
              onTap: () => themeProvider.setSeedColor(c),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: selected ? Border.all(color: theme.colorScheme.onSurface, width: 3) : null,
                  boxShadow: selected ? [BoxShadow(color: c.withOpacity(0.4), blurRadius: 8)] : null,
                ),
                child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // Font Picker
        Text('Font', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: fonts.map((f) {
            final selected = themeProvider.fontFamily == f;
            return ChoiceChip(
              label: Text(f),
              selected: selected,
              onSelected: (_) => themeProvider.setFontFamily(f),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _changeYearLevel(int year) async {
    final authService = context.read<AuthService>();
    final success = await authService.updateYearLevel(year);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? 'Year level updated!' : 'Year level can only be changed once'),
        backgroundColor: success ? Colors.green : Colors.orange,
      ));
    }
  }

  // ==================== ACTIVITY TAB ====================

  Widget _buildActivityTab(BuildContext context, UserProfile user) {
    final noteService = context.read<NoteService>();
    return Column(
      children: [
        // Period selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Show: '),
              ChoiceChip(label: const Text('7 days'), selected: _selectedPeriod == const Duration(days: 7), onSelected: (_) => setState(() => _selectedPeriod = const Duration(days: 7))),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('30 days'), selected: _selectedPeriod == const Duration(days: 30), onSelected: (_) => setState(() => _selectedPeriod = const Duration(days: 30))),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('All'), selected: _selectedPeriod == const Duration(days: 365), onSelected: (_) => setState(() => _selectedPeriod = const Duration(days: 365))),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<UserActivity>>(
            future: noteService.getUserActivity(user.id, period: _selectedPeriod),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No activity yet', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                );
              }
              final activities = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: activities.length,
                itemBuilder: (context, i) {
                  final a = activities[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getActivityColor(a.type).withOpacity(0.1),
                      child: Icon(_getActivityIcon(a.type), color: _getActivityColor(a.type), size: 20),
                    ),
                    title: Text(a.title),
                    subtitle: Text(a.description),
                    trailing: Text(_formatTime(a.timestamp), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== SETTINGS TAB ====================

  Widget _buildAccountSettingsTab(BuildContext context, UserProfile user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy & Security
          _sectionHeader('Privacy & Security'),
          _settingsTile(Icons.lock_outline, 'Change Password', 'Update your account password', () => _showChangePasswordDialog(context)),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('Public Profile'),
            subtitle: const Text('Allow others to find you by friend code'),
            value: _isProfilePublic,
            onChanged: (v) {
              setState(() => _isProfilePublic = v);
              context.read<AuthService>().updateProfilePublic(v);
            },
          ),
          _settingsTile(Icons.copy, 'Copy Friend Code', user.friendCode ?? '------', () {
            if (user.friendCode != null) {
              Clipboard.setData(ClipboardData(text: user.friendCode!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend code copied!')));
            }
          }),
          const Divider(height: 32),

          // Linked Accounts
          _sectionHeader('Linked Accounts'),
          _buildLinkedAccountsSection(context, user),
          const Divider(height: 32),

          // Help & Feedback
          _sectionHeader('Help & Feedback'),
          _settingsTile(Icons.bug_report_outlined, 'Report a Bug', 'Let us know if something is broken', () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const FeedbackPage()));
          }),
          _settingsTile(Icons.help_outline, 'Help Center', 'Get help using NotesCache', () {
            final url = _appConfig['help_center_url'];
            if (url != null && url.isNotEmpty) _launchUrl(url);
          }),
          _settingsTile(Icons.email_outlined, 'Contact Support', _appConfig['support_email'] ?? 'support@notescache.com', () {
            final email = _appConfig['support_email'] ?? 'support@notescache.com';
            _launchUrl('mailto:$email');
          }),
          _settingsTile(Icons.phone_outlined, 'Call Support', _appConfig['support_phone'] ?? '', () {
            final phone = _appConfig['support_phone'];
            if (phone != null && phone.isNotEmpty) _launchUrl('tel:$phone');
          }),
          _settingsTile(Icons.chat_outlined, 'WhatsApp Support', _appConfig['support_whatsapp'] ?? '', () {
            final wa = _appConfig['support_whatsapp'];
            if (wa != null && wa.isNotEmpty) _launchUrl('https://wa.me/$wa');
          }),
          _settingsTile(Icons.group_add, 'Join WhatsApp Group', 'Connect with other students', () {
            final link = _appConfig['whatsapp_group_link'];
            if (link != null && link.isNotEmpty) {
              _launchUrl(link);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No WhatsApp group link configured yet'), backgroundColor: Colors.orange),
              );
            }
          }),
          const Divider(height: 32),

          // About
          _sectionHeader('About'),
          _settingsTile(Icons.info_outline, 'About NotesCache', _appConfig['about_text'] ?? 'NotesCache v1.0.0', () => _showInfoDialog(context, 'About', _appConfig['about_text'] ?? 'NotesCache v1.0.0')),
          _settingsTile(Icons.description_outlined, 'Terms & Conditions', 'View our terms of service', () => _showInfoDialog(context, 'Terms & Conditions', _appConfig['terms_and_conditions'] ?? 'No terms available.')),
          _settingsTile(Icons.privacy_tip_outlined, 'Privacy Policy', 'How we handle your data', () => _showInfoDialog(context, 'Privacy Policy', _appConfig['privacy_policy'] ?? 'No policy available.')),
          const Divider(height: 32),

          // Danger Zone
          _sectionHeader('Danger Zone'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Delete Account', style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('Permanently delete your account and all data'),
            onTap: () => _showDeleteAccountDialog(context),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.grey[600])),
    );
  }

  Widget _settingsTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildLinkedAccountsSection(BuildContext context, UserProfile user) {
    final theme = Theme.of(context);
    if (_loadingIdentities) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final hasGoogle = _linkedIdentities.any((i) => i.provider == 'google');
    final hasEmail = _linkedIdentities.any((i) => i.provider == 'email');

    return Column(
      children: [
        // Email status
        ListTile(
          leading: Icon(Icons.email_outlined, color: hasEmail ? Colors.green : Colors.grey),
          title: Text('Email', style: TextStyle(fontWeight: FontWeight.w500, color: hasEmail ? null : Colors.grey)),
          subtitle: Text(hasEmail ? user.email : 'Not linked'),
          trailing: hasEmail
              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
              : null,
        ),
        // Google status
        ListTile(
          leading: Icon(Icons.g_mobiledata, color: hasGoogle ? Colors.blue : Colors.grey),
          title: Text('Google', style: TextStyle(fontWeight: FontWeight.w500, color: hasGoogle ? null : Colors.grey)),
          subtitle: Text(hasGoogle ? 'Linked' : 'Not linked'),
          trailing: hasGoogle
              ? TextButton(
                  onPressed: () => _confirmUnlinkGoogle(context),
                  child: const Text('Unlink', style: TextStyle(color: Colors.redAccent)),
                )
              : TextButton.icon(
                  onPressed: () => _linkGoogle(context),
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Link'),
                ),
        ),
        // Hint for Google-only users
        if (!hasEmail && hasGoogle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Set a password so you can also sign in without Google.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
      ],
    );
  }

  Future<void> _linkGoogle(BuildContext context) async {
    final authService = context.read<AuthService>();
    try {
      await authService.linkGoogle();
      await _loadLinkedIdentities();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google account linked!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to link Google: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmUnlinkGoogle(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Google?'),
        content: const Text('You\'ll need a password to sign in after unlinking. Set one first if you haven\'t.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final authService = context.read<AuthService>();
              final googleIdentity = _linkedIdentities.firstWhere((i) => i.provider == 'google');
              try {
                await authService.unlinkGoogle(googleIdentity);
                await _loadLinkedIdentities();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Google unlinked'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to unlink: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Unlink', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(BuildContext context, String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildFriendCodeBadge(BuildContext context, String code) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend code copied!'), duration: Duration(seconds: 1)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(code, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13)),
            const SizedBox(width: 6),
            Icon(Icons.copy, size: 14, color: Colors.blue[700]),
          ],
        ),
      ),
    );
  }

  String _getRoleLabel(UserProfile user) {
    if (user.hasRole(UserRole.admin)) return 'Admin';
    if (user.hasRole(UserRole.lecturer)) return 'Lecturer';
    if (user.hasRole(UserRole.moderator)) return 'Moderator';
    return 'Year ${user.yearLevel ?? 1} Student';
  }

  Color _getRoleColor(UserProfile user) {
    if (user.hasRole(UserRole.admin)) return Colors.red;
    if (user.hasRole(UserRole.lecturer)) return Colors.purple;
    if (user.hasRole(UserRole.moderator)) return Colors.orange;
    return Colors.blue;
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'upload': return Icons.upload_file;
      case 'chat': return Icons.chat;
      case 'search': return Icons.search;
      case 'ai': return Icons.smart_toy;
      default: return Icons.circle;
    }
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'upload': return Colors.green;
      case 'chat': return Colors.blue;
      case 'search': return Colors.orange;
      case 'ai': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _launchUrl(String url) async {
    try {
      // Ensure URL has a scheme
      String urlToLaunch = url;
      if (!url.contains('://')) {
        if (url.contains('@')) {
          urlToLaunch = 'mailto:$url';
        } else if (url.startsWith('+') || url.startsWith('0')) {
          urlToLaunch = 'tel:$url';
        } else {
          urlToLaunch = 'https://$url';
        }
      }
      final uri = Uri.parse(urlToLaunch);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: copy to clipboard
        if (mounted) {
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copied to clipboard: $url'), backgroundColor: Colors.blue),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied to clipboard: $url'), backgroundColor: Colors.blue),
        );
      }
    }
  }

  // ==================== DIALOGS ====================

  void _showLogoutDialog(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              authService.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();
    final formKey = GlobalKey<FormState>();

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
                decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 6) return 'Min 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder()),
                validator: (v) => v != newPwController.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final supabase = Supabase.instance.client;
                await supabase.auth.updateUser(UserAttributes(password: newPwController.text));
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password updated!'), backgroundColor: Colors.green),
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

  void _showDeleteAccountDialog(BuildContext context) {
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This action is permanent and cannot be undone. All your notes, chats, and data will be deleted.'),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: confirmController.text != 'DELETE' || _isDeleting ? null : () async {
                setDialogState(() => _isDeleting = true);
                final authService = context.read<AuthService>();
                final success = await authService.deleteAccount();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  if (success) {
                    Navigator.pushReplacementNamed(context, '/login');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to delete account. Please contact support.'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: _isDeleting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Delete Account', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
