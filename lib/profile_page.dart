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
  bool _isProfilePublic = true;
  bool _isDeleting = false;
  Map<String, String> _appConfig = {};
  List<UserIdentity> _linkedIdentities = [];
  bool _loadingIdentities = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final authService = context.read<AuthService>();
    final user = authService.currentUser!;
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
    super.dispose();
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
                      // Avatar + Edit pill stacked under the image
                      Column(
                        mainAxisSize: MainAxisSize.min,
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
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 80,
                            height: 28,
                            child: OutlinedButton(
                              onPressed: _showEditProfileDialog,
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(color: primaryColor.withOpacity(0.5)),
                                foregroundColor: primaryColor,
                              ),
                              child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
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
              tabs: const [Tab(text: 'Activity'), Tab(text: 'Settings')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
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

  // ==================== EDIT PROFILE DIALOG ====================

  void _showEditProfileDialog() {
    final authService = context.read<AuthService>();
    final user = authService.currentUser!;
    final nameController = TextEditingController(text: user.fullName);
    final bioController = TextEditingController(text: user.bio);
    var selectedYear = user.yearLevel ?? 1;
    var saving = false;
    var uploadingAvatar = false;
    var dialogAvatarUrl = user.avatarUrl; // live-updates when picker/upload changes it
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with change button — whole image is tappable
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: uploadingAvatar
                            ? null
                            : () async {
                                setDialogState(() => uploadingAvatar = true);
                                final online = await authService.isOnline();
                                if (!online) {
                                  if (dialogCtx.mounted) {
                                    setDialogState(() => uploadingAvatar = false);
                                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                      const SnackBar(content: Text('No internet connection'), backgroundColor: Colors.orange),
                                    );
                                  }
                                  return;
                                }
                                try {
                                  final result = await FilePicker.pickFiles(type: FileType.image, allowMultiple: false);
                                  if (result != null && result.files.single.path != null && dialogCtx.mounted) {
                                    final success = await authService.updateProfileImage(File(result.files.single.path!));
                                    if (dialogCtx.mounted) {
                                      setDialogState(() {
                                        uploadingAvatar = false;
                                        // Keep the dialog avatar in sync with the upload
                                        dialogAvatarUrl = authService.currentUser?.avatarUrl;
                                      });
                                      ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                                        content: Text(success ? 'Profile photo updated!' : 'Failed — max 2MB, JPG/PNG/WebP only'),
                                        backgroundColor: success ? Colors.green : Colors.red,
                                      ));
                                    }
                                  } else if (dialogCtx.mounted) {
                                    setDialogState(() => uploadingAvatar = false);
                                  }
                                } catch (e) {
                                  if (dialogCtx.mounted) {
                                    setDialogState(() => uploadingAvatar = false);
                                    ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                                  }
                                }
                              },
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                image: DecorationImage(
                                  image: NetworkImage(dialogAvatarUrl ?? AuthService.getDefaultAvatarUrl(user.fullName, user.id)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: uploadingAvatar
                                  ? Container(
                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20)),
                                      child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Center(child: Icon(Icons.camera_alt, color: Colors.white, size: 24)),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tap to change photo',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                          const SizedBox(width: 8),
                          // DiceBear picker
                          Tooltip(
                            message: 'Pick a DiceBear avatar',
                            child: InkWell(
                              onTap: () => _showDiceBearPicker(
                                dialogCtx,
                                onAvatarChanged: (url) => setDialogState(() => dialogAvatarUrl = url),
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.casino_outlined, size: 16, color: primaryColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Random',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildInputField(dialogCtx, 'Full Name', nameController, Icons.person_outline),
                const SizedBox(height: 14),
                _buildInputField(dialogCtx, 'Bio', bioController, Icons.edit_note_outlined, maxLines: 3),
                const SizedBox(height: 14),
                Text('Year Level', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedYear,
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
                    if (val != null) setDialogState(() => selectedYear = val);
                  },
                ),
                if (user.yearChanged)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Year level can only be changed once', style: TextStyle(fontSize: 12, color: Colors.orange[700])),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      await authService.updateProfileDetails(
                        fullName: nameController.text,
                        bio: bioController.text,
                      );
                      if (selectedYear != (user.yearLevel ?? 1) && !user.yearChanged) {
                        await authService.updateYearLevel(selectedYear);
                      }
                      if (dialogCtx.mounted) {
                        setDialogState(() => saving = false);
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green),
                        );
                      }
                    },
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
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

  /// DiceBear avatar picker: shows a grid of generated avatars (same seed,
  /// different styles) + a shuffle button to randomize the seed. Tapping one
  /// saves it as the profile avatar immediately.
  void _showDiceBearPicker(BuildContext dialogCtx, {required void Function(String url) onAvatarChanged}) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser!;
    const styles = [
      'initials', 'adventurer', 'avataaars', 'bottts', 'fun-emoji',
      'personas', 'big-ears', 'micah', 'notionists', 'open-peeps',
      'thumbs', 'lorelei', 'miniavs', 'shapes',
    ];
    final seedBase = (user.fullName ?? user.id).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    var seed = seedBase;
    var saving = false;

    String urlFor(String style) =>
        'https://api.dicebear.com/8.x/$style/png?seed=$seed&backgroundColor=1a237e,1565c0,0277bd,00838f,2e7d32,6a1b9a,c62828,e65100&fontSize=40';

    showModalBottomSheet<void>(
      context: dialogCtx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Choose an avatar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    // Shuffle: randomize the seed
                    TextButton.icon(
                      onPressed: saving ? null : () {
                        setSheetState(() {
                          seed = '${seedBase}${DateTime.now().millisecondsSinceEpoch % 100000}';
                        });
                      },
                      icon: const Icon(Icons.casino_outlined, size: 18),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (final style in styles)
                        InkWell(
                          onTap: saving ? null : () async {
                            setSheetState(() => saving = true);
                            final ok = await authService.updateAvatarUrl(urlFor(style));
                            if (sheetCtx.mounted) {
                              setSheetState(() => saving = false);
                              Navigator.pop(sheetCtx);
                              // Keep the edit dialog's avatar in sync
                              if (ok && dialogCtx.mounted) {
                                onAvatarChanged(urlFor(style));
                              }
                              if (dialogCtx.mounted) {
                                ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                                  content: Text(ok ? 'Avatar updated!' : 'Failed to update avatar.'),
                                  backgroundColor: ok ? Colors.green : Colors.red,
                                ));
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Image.network(
                              urlFor(style),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.person_outline, size: 20)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Want your own photo instead? Close this and tap the profile picture.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== ACTIVITY TAB ====================

  Widget _buildActivityTab(BuildContext context, UserProfile user) {
    return _ActivityBody(userId: user.id);
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

          // Appearance (moved here from the old Edit tab)
          _buildThemeSection(context),
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
      final linked = await authService.linkGoogle();
      if (!linked) return;
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

/// Self-contained Activity tab: owns its period state + future so the rest of
/// the profile page never rebuilds on chip taps or list refreshes, and the
/// DB query only fires once per period selection (not on every parent build).
class _ActivityBody extends StatefulWidget {
  final String userId;
  const _ActivityBody({required this.userId});

  @override
  State<_ActivityBody> createState() => _ActivityBodyState();
}

class _ActivityBodyState extends State<_ActivityBody> {
  Duration _selectedPeriod = const Duration(days: 7);
  Future<List<UserActivity>>? _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<NoteService>().getUserActivity(widget.userId, period: _selectedPeriod);
  }

  void _setPeriod(Duration period) {
    if (period == _selectedPeriod) return;
    setState(() {
      _selectedPeriod = period;
      _future = context.read<NoteService>().getUserActivity(widget.userId, period: period);
    });
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Show: '),
              ChoiceChip(label: const Text('7 days'), selected: _selectedPeriod == const Duration(days: 7), onSelected: (_) => _setPeriod(const Duration(days: 7))),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('30 days'), selected: _selectedPeriod == const Duration(days: 30), onSelected: (_) => _setPeriod(const Duration(days: 30))),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('All'), selected: _selectedPeriod == const Duration(days: 365), onSelected: (_) => _setPeriod(const Duration(days: 365))),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<UserActivity>>(
            future: _future,
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
}
