import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services.dart';
import 'models.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _bioController;
  late TextEditingController _nameController;

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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header Card (Replicating Kotlin)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(20), // Replicating Rounded Square option
                        image: user.avatarUrl != null 
                            ? DecorationImage(image: NetworkImage(user.avatarUrl!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: user.avatarUrl == null 
                          ? const Icon(Icons.person, size: 40, color: Color(0xFF1A237E))
                          : null,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName ?? 'User',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            user.email,
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          // Friend Code Section
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
                              const Text(
                                'Online • Synced with NotesCache',
                                style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Bio
                Text(
                  user.bio ?? 'No bio set. Add one to tell others about yourself!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: user.bio == null ? Colors.grey : Colors.black87,
                    fontStyle: user.bio == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                const SizedBox(height: 16),
                // Interests (Chips)
                if (user.interests != null && user.interests!.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: user.interests!.map((interest) => Chip(
                      label: Text(interest, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.indigo.shade50,
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
              ],
            ),
          ),
          
          // TabBar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1A237E),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1A237E),
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Activity'),
                Tab(text: 'Settings'),
              ],
            ),
          ),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProfileEditTab(),
                _buildPlaceholderTab('Activity Feed'),
                _buildPlaceholderTab('Account Settings'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileEditTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputField('Display Name', _nameController, Icons.person_outline),
          const SizedBox(height: 20),
          _buildInputField('Bio', _bioController, Icons.edit_note_outlined, maxLines: 3),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                final authService = context.read<AuthService>();
                await authService.updateProfile(
                  fullName: _nameController.text,
                  bio: _bioController.text,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated successfully!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFriendCodeBadge(BuildContext context, String code) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend code copied!'), duration: Duration(seconds: 1)),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A237E).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFF1A237E)),
            const SizedBox(width: 8),
            Text(
              code,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.copy_all_rounded, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Coming soon from the Kotlin version!', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
