import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services.dart';
import 'models.dart';
import 'chat_room_page.dart';

class ChatsListPage extends StatefulWidget {
  const ChatsListPage({super.key});

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _bulkCodesController = TextEditingController();
  
  String _activeGroupTab = 'MY'; // 'MY' or 'PUBLIC'
  bool _isGroupPublic = false;
  bool _isFriendBarExpanded = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _groupNameController.dispose();
    _descriptionController.dispose();
    _bulkCodesController.dispose();
    super.dispose();
  }

  void _showAddFriendDialog() {
    final authService = context.read<AuthService>();
    if (authService.currentUser?.isGuest ?? true) {
      _showGuestNotice(context, 'Social Hub');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: _codeController,
          inputFormatters: [FriendCodeFormatter()],
          decoration: const InputDecoration(
            hintText: 'Enter friend code (e.g. ABC-123)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final code = _codeController.text.trim();
              if (code.isEmpty) return;

              final chatService = context.read<ChatService>();
              final authService = context.read<AuthService>();
              final user = await chatService.findUserByCode(code);

              if (user != null) {
                if (user.id == authService.currentUser?.id) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot add yourself!')));
                   return;
                }
                final success = await chatService.addFriend(authService.currentUser!.id, user.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? 'Friend added!' : 'Already added or error occurred')),
                );
                _codeController.clear();
                setState(() {});
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found')));
              }
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    final authService = context.read<AuthService>();
    if (authService.currentUser?.isGuest ?? true) {
      _showGuestNotice(context, 'Study Groups');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Study Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _groupNameController,
                  decoration: const InputDecoration(labelText: 'Group Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Purpose / Description', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Make Public', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Allow anyone to discover and join', style: TextStyle(fontSize: 12)),
                  value: _isGroupPublic,
                  onChanged: (val) => setDialogState(() => _isGroupPublic = val),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bulkCodesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Invite Members (Codes)',
                    hintText: 'ABC-123, DEF-456',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                final name = _groupNameController.text.trim();
                final codes = _bulkCodesController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                
                if (name.isEmpty) return;

                final chatService = context.read<ChatService>();
                final authService = context.read<AuthService>();
                
                final room = await chatService.createChatRoom(
                  creatorId: authService.currentUser!.id,
                  name: name,
                  isGroup: true,
                  isPublic: _isGroupPublic,
                  description: _descriptionController.text.trim(),
                  members: [authService.currentUser!.id], // Added creator as first member
                );

                if (room != null) {
                  if (codes.isNotEmpty) {
                    await chatService.bulkAddByCodes(room.id, codes);
                  }
                  Navigator.pop(context);
                  _groupNameController.clear();
                  _descriptionController.clear();
                  _bulkCodesController.clear();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group created!')));
                }
              },
              child: const Text('CREATE'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final user = context.watch<AuthService>().currentUser!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Unified Header
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      labelColor: primaryColor,
                      unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                      indicatorColor: primaryColor,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(text: 'GROUPS'),
                        Tab(text: 'FRIENDS'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48), // Balancing space for the back button
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGroupsTab(user),
                  _buildFriendsTab(user),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showCreateGroupDialog();
          } else {
            _showAddFriendDialog();
          }
        },
        backgroundColor: primaryColor,
        child: Icon(_tabController.index == 0 ? Icons.group_add : Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildGroupsTab(UserProfile user) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        _buildVerticalSectionHeader(context, 'MY GROUPS'),
        _buildMyGroups(user),
        const SizedBox(height: 32),
        _buildVerticalSectionHeader(context, 'PUBLIC GROUPS'),
        _buildPublicGroups(user),
      ],
    );
  }

  Widget _buildVerticalSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSubTab(String label, bool isSelected, VoidCallback onTap) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.4),
              letterSpacing: 1.1,
            ),
          ),
          if (isSelected)
            Container(
              margin: const EdgeInsets.only(top: 4),
              height: 2,
              width: 20,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyGroups(UserProfile user) {
    final chatService = context.read<ChatService>();
    final theme = Theme.of(context);

    return StreamBuilder<List<ChatRoom>>(
      stream: chatService.getChatRoomsStream(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rooms = snapshot.data ?? [];
        final groups = rooms.where((r) => r.isGroup).toList();

        if (groups.isEmpty) {
          return _buildEmptyState('You haven\'t joined any groups yet.', Icons.groups_outlined);
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final room = groups[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Icon(Icons.groups, color: theme.colorScheme.primary),
              ),
              title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(room.lastMessage ?? room.description ?? 'No activity yet', maxLines: 1),
              trailing: FutureBuilder<int>(
                future: chatService.getUnreadCount(room.id, user.id),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(height: 4),
                      const Icon(Icons.chevron_right_rounded, size: 20),
                    ],
                  );
                },
              ),
              onTap: () => _openRoom(room),
            );
          },
        );
      },
    );
  }

  Widget _buildPublicGroups(UserProfile user) {
    final chatService = context.read<ChatService>();
    final theme = Theme.of(context);

    return FutureBuilder<List<ChatRoom>>(
      future: chatService.getPublicChatRooms(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rooms = snapshot.data ?? [];
        
        if (rooms.isEmpty) {
          return _buildEmptyState('No public groups found. Create one!', Icons.explore_outlined);
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
              child: ListTile(
                title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(room.description ?? 'Community Study Group'),
                trailing: ElevatedButton(
                  onPressed: user.isGuest ? () => _showGuestNotice(context, 'Public Groups') : () async {
                    final success = await chatService.joinChatRoom(room.id, user.id);
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined ${room.name}!')));
                      setState(() => _activeGroupTab = 'MY');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('JOIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openRoom(ChatRoom room) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatRoomPage(room: room)),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _buildFriendsTab(UserProfile user) {
    final chatService = context.read<ChatService>();
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildCollapsibleFriendBar(user),
        Expanded(
          child: StreamBuilder<List<FriendRelation>>(
            stream: chatService.getFriendsStream(user.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final friends = snapshot.data ?? [];
              if (friends.isEmpty) {
                return _buildEmptyState('Add friends using their code!', Icons.people_outline_rounded);
              }
              return ListView.builder(
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final friend = friends[index].friendProfile!;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: friend.avatarUrl != null ? NetworkImage(friend.avatarUrl!) : null,
                      child: friend.avatarUrl == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(friend.fullName ?? 'Student', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(friend.hasRole(UserRole.lecturer) ? 'Lecturer' : 'Year ${friend.yearLevel}'),
                    trailing: const Icon(Icons.chat_outlined, size: 20),
                    onTap: () async {
                       final room = await chatService.createChatRoom(
                         creatorId: user.id,
                         name: friend.fullName ?? 'Chat',
                         isGroup: false,
                         members: [user.id, friend.id],
                       );
                       if (room != null && mounted) {
                         _openRoom(room);
                       }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsibleFriendBar(UserProfile user) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: double.infinity,
      height: _isFriendBarExpanded ? 80 : 40,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0), // Swapped margin to push it below tabs
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: primaryColor.withOpacity(0.1)),
      ),
      child: _isFriendBarExpanded
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MY FRIEND CODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor, letterSpacing: 1.1)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () {
                           String code = (user.friendCode ?? '').toUpperCase();
                           // Auto-insert dash if it's a 6-char code without one
                           if (code.length == 6 && !code.contains('-')) {
                             code = '${code.substring(0, 3)}-${code.substring(3)}';
                           }
                           Clipboard.setData(ClipboardData(text: code));
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend code copied!'), duration: Duration(seconds: 1)));
                        },
                        child: Text(
                          () {
                            String code = (user.friendCode ?? '------').toUpperCase();
                            if (code.length == 6 && !code.contains('-')) {
                              return '${code.substring(0, 3)}-${code.substring(3)}';
                            }
                            return code;
                          }(),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddFriendDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('ADD'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: () => setState(() => _isFriendBarExpanded = false),
                  tooltip: 'Collapse',
                ),
              ],
            )
          : InkWell(
              onTap: () => setState(() => _isFriendBarExpanded = true),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('MY CODE: ${() {
                      String c = (user.friendCode ?? '------').toUpperCase();
                      if (c.length == 6 && !c.contains('-')) return '${c.substring(0, 3)}-${c.substring(3)}';
                      return c;
                    }()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.onSurface.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
        ],
      ),
    );
  }

  void _showGuestNotice(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is for registered students. Sign up to join the community!'),
        backgroundColor: Colors.indigo,
        action: SnackBarAction(
          label: 'SIGN UP',
          textColor: Colors.white,
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
        ),
      ),
    );
  }
}

class FriendCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase().replaceAll('-', '');
    if (text.length > 6) return oldValue;
    
    String formatted = text;
    if (text.length > 3) {
      formatted = '${text.substring(0, 3)}-${text.substring(3)}';
    }
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
