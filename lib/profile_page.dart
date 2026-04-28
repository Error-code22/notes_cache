import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'services.dart';
import 'models.dart';
import 'admin_dashboard_page.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final authService = context.read<AuthService>();
    final user = authService.currentUser!;
    _bioController = TextEditingController(text: user.bio);
    _nameController = TextEditingController(text: user.fullName);
    
    // Generate code if missing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      authService.ensureFriendCode();
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
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null && mounted) {
        final authService = context.read<AuthService>();
        final success = await authService.updateProfileImage(File(result.files.single.path!));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? '✅ Profile photo updated!' : '❌ Failed to update photo'),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error picking image: $e'), backgroundColor: Colors.red),
        );
      }
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
              tooltip: 'Admin Panel',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminDashboardPage()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authService.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: Column(
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
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
                              image: user.avatarUrl != null 
                                  ? DecorationImage(image: NetworkImage(user.avatarUrl!), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: user.avatarUrl == null 
                                ? Icon(Icons.person, size: 40, color: primaryColor)
                                : null,
                          ),
                          Positioned(
                            bottom: -4,
                            right: -4,
                            child: InkWell(
                              onTap: _pickAndUploadImage,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: primaryColor,
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
                            Text(
                              user.fullName ?? 'Student',
                              style: TextStyle(
                                fontSize: 22, 
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              user.email,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(0.6), 
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildFriendCodeBadge(context, user.friendCode ?? '------'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Online • Synced with NotesCache',
                                    style: TextStyle(
                                      color: Colors.green, 
                                      fontSize: 12, 
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    user.bio ?? 'No bio set. Add one to tell others about yourself!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: user.bio == null 
                          ? theme.colorScheme.onSurface.withOpacity(0.5) 
                          : theme.colorScheme.onSurface.withOpacity(0.9),
                      fontStyle: user.bio == null ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                indicatorColor: primaryColor,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Edit Profile'),
                  Tab(text: 'Activity'),
                  Tab(text: 'Settings'),
                ],
              ),
            ),
            
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProfileEditTab(context),
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

  Widget _buildProfileEditTab(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputField(context, 'Full Name', _nameController, Icons.person_outline),
          const SizedBox(height: 20),
          _buildInputField(context, 'Bio / About Me', _bioController, Icons.edit_note_outlined, maxLines: 3),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                final authService = context.read<AuthService>();
                await authService.updateProfileDetails(
                  fullName: _nameController.text,
                  bio: _bioController.text,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Profile updated successfully!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab(BuildContext context, UserProfile user) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final noteService = context.read<NoteService>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPeriodChip('1 Day', const Duration(days: 1)),
              const SizedBox(width: 8),
              _buildPeriodChip('1 Week', const Duration(days: 7)),
              const SizedBox(width: 8),
              _buildPeriodChip('1 Month', const Duration(days: 30)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<UserActivity>>(
            future: noteService.getUserActivity(user.id, period: _selectedPeriod),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              final activities = snapshot.data ?? [];
              
              if (activities.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'No recent activity found.', 
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  final activity = activities[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: theme.cardColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: primaryColor.withOpacity(0.1),
                        child: Icon(
                          activity.type == 'upload' ? Icons.cloud_upload_outlined : Icons.edit_note_outlined,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                      title: Text(activity.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(activity.description, style: const TextStyle(fontSize: 12)),
                      trailing: Text(
                        _formatTimestamp(activity.timestamp),
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 10),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSettingsTab(BuildContext context, UserProfile user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsSectionTitle(context, 'Account Verification'),
          _buildSettingsItem(
            context,
            'Email Address',
            user.email,
            Icons.alternate_email_rounded,
            null,
          ),
          const SizedBox(height: 24),
          
          _buildSettingsSectionTitle(context, 'Academic Status'),
          _buildSettingsItem(
            context,
            'Current Year',
            'Year ${user.yearLevel ?? "1"}${user.yearChanged ? " (Locked)" : ""}',
            Icons.school_outlined,
            user.yearChanged ? null : () => _showYearChangeDialog(context, user),
            subtitle: user.yearChanged ? 'Permanently locked in.' : 'Tap to update (One-time change)',
          ),
          const SizedBox(height: 24),

          _buildSettingsSectionTitle(context, 'Privacy & Security'),
          _buildSettingsToggle(
            context,
            'Public Profile',
            'Allow others to see your friend code',
            _isProfilePublic,
            (val) => setState(() => _isProfilePublic = val),
          ),
          _buildSettingsItem(
            context,
            'Change Password',
            'Update your login credentials',
            Icons.lock_reset_rounded,
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reset link sent to your email!')),
              );
            },
          ),
          const SizedBox(height: 32),
          
          Center(
            child: TextButton(
              onPressed: () {},
              child: const Text('Delete Account', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  void _showYearChangeDialog(BuildContext context, UserProfile user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Permanent Year Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose your correct year level. WARNING: Once you save this, it will be PERMANENTLY LOCKED.'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [1, 2, 3, 4].map((y) => ChoiceChip(
                label: Text('Yr $y'),
                selected: false,
                onSelected: (_) async {
                  final authService = context.read<AuthService>();
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  
                  final success = await authService.updateYearLevel(y);
                  
                  if (success) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('✅ Year successfully locked to Year $y!')),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('❌ Failed to update. Please try again.')),
                    );
                  }
                },
              )).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ],
      ),
    );
  }

  Widget _buildSettingsSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface.withOpacity(0.4),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, String title, String value, IconData icon, VoidCallback? onTap, {String? subtitle}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle ?? value, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
        trailing: onTap != null ? const Icon(Icons.chevron_right_rounded, size: 20) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildSettingsToggle(BuildContext context, String title, String subtitle, bool value, Function(bool) onChanged) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
        value: value,
        onChanged: onChanged,
        activeColor: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildPeriodChip(String label, Duration period) {
    final isSelected = _selectedPeriod == period;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : theme.colorScheme.onSurface)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedPeriod = period);
        }
      },
      selectedColor: primaryColor,
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Widget _buildInputField(BuildContext context, String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label, 
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: 14,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.6)),
            filled: true,
            fillColor: theme.cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFriendCodeBadge(BuildContext context, String code) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isLoading = context.watch<AuthService>().isLoading;
    final isMissing = code == '------';

    return InkWell(
      onTap: isMissing ? null : () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend code copied!'), duration: Duration(seconds: 1)),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMissing && isLoading)
               SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
              )
            else
               Icon(Icons.qr_code_2_rounded, size: 18, color: primaryColor),
            const SizedBox(width: 8),
            Text(
              () {
                if (isMissing && isLoading) return 'GENERATING...';
                String c = code.toUpperCase();
                if (c.length == 6 && !c.contains('-')) return '${c.substring(0, 3)}-${c.substring(3)}';
                return c;
              }(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: isMissing ? 1.0 : 1.5,
                color: primaryColor,
              ),
            ),
            if (!isMissing) ...[
              const SizedBox(width: 8),
              Icon(Icons.copy_all_rounded, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.4)),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildPlaceholderTab(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            title, 
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.4), 
              fontSize: 18, 
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Coming soon from the Kotlin version!', 
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)),
          ),
        ],
      ),
    );
  }
}
