import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _betaPasswordController = TextEditingController();

  String _activeGroupTab = 'MY';
  bool _isGroupPublic = false;
  bool _isFriendBarExpanded = true;
  int _badgeRefreshKey = 0;
  bool _codeBlurred = false;
  bool _isSearching = false;
  String _filterChip = 'all';

  // Beta gate state
  bool _betaLocked = false;      // from app_config
  bool _betaUnlocked = false;    // from SharedPreferences (device-local)
  bool _betaLoading = true;
  String _betaPasswordError = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _checkBetaGate();
  }

  Future<void> _checkBetaGate() async {
    final noteService = context.read<NoteService>();
    final prefs = await SharedPreferences.getInstance();
    final config = await noteService.getAppConfig();
    final locked = config['chat_beta_locked'] == 'true';
    final unlocked = prefs.getBool('chat_beta_unlocked') ?? false;
    if (mounted) setState(() { _betaLocked = locked; _betaUnlocked = unlocked; _betaLoading = false; });
  }

  Future<void> _submitBetaPassword() async {
    final entered = _betaPasswordController.text.trim();
    if (entered == 'preview') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('chat_beta_unlocked', true);
      _betaPasswordController.clear();
      if (mounted) setState(() { _betaUnlocked = true; _betaPasswordError = ''; });
    } else {
      setState(() => _betaPasswordError = 'Incorrect password. Contact the dev for access.');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _groupNameController.dispose();
    _descriptionController.dispose();
    _bulkCodesController.dispose();
    _searchController.dispose();
    _betaPasswordController.dispose();
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

    // Beta gate — show blocker if locked and not unlocked on this device
    if (_betaLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_betaLocked && !_betaUnlocked) {
      return _buildBetaBlocker(theme, primaryColor, user);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── BAR 1: Friend code + search + eye ──────────────────────────
            _buildBar1(context, user, theme, primaryColor),

            // ── BAR 2: GROUPS | CHATS tabs (no back arrow — it's in Bar 1) ──
            Container(
              color: theme.colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                indicatorColor: primaryColor,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'GROUPS'),
                  Tab(text: 'CHATS'),
                ],
              ),
            ),

            // ── BAR 3: All | Unread | Archived filter chips ─────────────────
            _buildBar3(context, theme, primaryColor),

            // ── Content ─────────────────────────────────────────────────────
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

  // ── BETA BLOCKER ───────────────────────────────────────────────────────────
  Widget _buildBetaBlocker(ThemeData theme, Color primaryColor, UserProfile user) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Back button
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    // Construction icon
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.construction_rounded, size: 72, color: Colors.orange),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Under Construction',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The Communications feature is being polished and will be available soon.\n\nAre you a beta tester? Enter the access password below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 40),
                    // Password field
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primaryColor.withOpacity(0.15)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 18, color: primaryColor),
                              const SizedBox(width: 8),
                              Text('Beta Access', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor, letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _betaPasswordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: 'Enter beta password',
                              prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              errorText: _betaPasswordError.isEmpty ? null : _betaPasswordError,
                            ),
                            onSubmitted: (_) => _submitBetaPassword(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitBetaPassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Unlock Preview', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Contact the dev to get your beta access password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.35)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BAR 1 ──────────────────────────────────────────────────────────────────
  Widget _buildBar1(BuildContext context, UserProfile user, ThemeData theme, Color primaryColor) {
    String rawCode = (user.friendCode ?? '------').toUpperCase();
    if (rawCode.length == 6 && !rawCode.contains('-')) {
      rawCode = '${rawCode.substring(0, 3)}-${rawCode.substring(3)}';
    }

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Back arrow in top bar
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 4),
          // Friend code — tap to copy
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: rawCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Friend code copied!'), duration: Duration(seconds: 1)),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MY CODE  ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor, letterSpacing: 1.1)),
                ImageFiltered(
                  imageFilter: _codeBlurred
                      ? ImageFilter.blur(sigmaX: 6, sigmaY: 6)
                      : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Text(rawCode, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: theme.colorScheme.onSurface)),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Eye toggle
          IconButton(
            icon: Icon(_codeBlurred ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
            onPressed: () => setState(() => _codeBlurred = !_codeBlurred),
            tooltip: _codeBlurred ? 'Show code' : 'Hide code',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          // Search pill — compact, fits mobile
          GestureDetector(
            onTap: () => _showSearchPopup(context, user),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Text('Search', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSearchPopup(BuildContext context, UserProfile user) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final chatService = context.read<ChatService>();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
            alignment: Alignment.topCenter,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search groups, chats, people...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onChanged: (v) => setDialogState(() => query = v.toLowerCase()),
                  ),
                ),
                // Results
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: query.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.search, size: 48, color: theme.colorScheme.onSurface.withOpacity(0.15)),
                              const SizedBox(height: 12),
                              Text('Type to search groups and chats', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 13)),
                            ],
                          ),
                        )
                      : StreamBuilder<List<ChatRoom>>(
                          stream: chatService.getChatRoomsStream(user.id),
                          builder: (ctx2, snapshot) {
                            final allRooms = snapshot.data ?? [];
                            final filtered = allRooms.where((r) => r.name.toLowerCase().contains(query)).toList();
                            if (filtered.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text('No results for "$query"', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final room = filtered[i];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: primaryColor.withOpacity(0.1),
                                    child: Icon(room.isGroup ? Icons.groups : Icons.person, color: primaryColor, size: 20),
                                  ),
                                  title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(room.lastMessage ?? (room.isGroup ? 'Group' : 'Direct message'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _openRoom(room);
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── BAR 3 ──────────────────────────────────────────────────────────────────
  Widget _buildBar3(BuildContext context, ThemeData theme, Color primaryColor) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _filterChipWidget('all', 'All', theme, primaryColor),
          const SizedBox(width: 8),
          _filterChipWidget('unread', 'Unread', theme, primaryColor),
          const SizedBox(width: 8),
          _filterChipWidget('archived', 'Archived', theme, primaryColor),
        ],
      ),
    );
  }

  Widget _filterChipWidget(String value, String label, ThemeData theme, Color primaryColor) {
    final isSelected = _filterChip == value;
    return GestureDetector(
      onTap: () => setState(() => _filterChip = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? primaryColor : theme.dividerColor.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
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

        // Archived chip — no archive system yet
        if (_filterChip == 'archived') {
          return _buildEmptyState('No archived groups yet.', Icons.archive_outlined);
        }

        // Unread chip — use FutureBuilder to async-filter by unread count
        if (_filterChip == 'unread') {
          return FutureBuilder<List<ChatRoom>>(
            key: ValueKey('unread_groups_$_badgeRefreshKey'),
            future: Future.wait(
              groups.map((r) async {
                final count = await chatService.getUnreadCount(r.id, user.id);
                return count > 0 ? r : null;
              }),
            ).then((list) => list.whereType<ChatRoom>().toList()),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final unread = snap.data!;
              if (unread.isEmpty) return _buildEmptyState('No unread groups.', Icons.done_all_rounded);
              return _buildGroupList(unread, chatService, user, theme);
            },
          );
        }

        if (groups.isEmpty) {
          return _buildEmptyState('You haven\'t joined any groups yet.', Icons.groups_outlined);
        }
        return _buildGroupList(groups, chatService, user, theme);
      },
    );
  }

  Widget _buildGroupList(List<ChatRoom> groups, ChatService chatService, UserProfile user, ThemeData theme) {
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
            key: ValueKey('badge_${room.id}_$_badgeRefreshKey'),
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
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined ${room.name}!')));
                      // Switch to My Groups tab
                      _tabController.animateTo(0);
                      setState(() {});
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
      if (mounted) setState(() => _badgeRefreshKey++);
    });
  }

  Widget _buildFriendsTab(UserProfile user) {
    final chatService = context.read<ChatService>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Active DM conversations
        StreamBuilder<List<ChatRoom>>(
          stream: chatService.getDmRoomsStream(user.id),
          builder: (context, dmSnapshot) {
            final dmRooms = dmSnapshot.data ?? [];
            return Expanded(
              child: StreamBuilder<List<FriendRelation>>(
                stream: chatService.getFriendsStream(user.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && dmRooms.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final friends = snapshot.data ?? [];

                  // Show DM rooms with messages at top, then friends without a DM below
                  final dmRoomsByMembers = {
                    for (final r in dmRooms)
                      r.memberIds.firstWhere((id) => id != user.id, orElse: () => ''): r
                  };

                  if (friends.isEmpty && dmRooms.isEmpty) {
                    return _buildEmptyState('Add friends using their code!', Icons.people_outline_rounded);
                  }

                  // Archived chip — no archive system yet
                  if (_filterChip == 'archived') {
                    return _buildEmptyState('No archived chats yet.', Icons.archive_outlined);
                  }

                  // Merge: friends with a DM room get the room's last message shown
                  final friendIds = friends.map((f) => f.friendId).toSet();
                  // DM rooms with unknown friends (recipient added you but you haven't added them back)
                  final unknownDms = dmRooms.where((r) {
                    final otherId = r.memberIds.firstWhere((id) => id != user.id, orElse: () => '');
                    return otherId.isNotEmpty && !friendIds.contains(otherId);
                  }).toList();

                  // For Unread chip: only show friends/DMs with unread messages
                  // We use the last_message_read_by column stored in the room
                  List<FriendRelation> visibleFriends = friends;
                  List<ChatRoom> visibleUnknownDms = unknownDms;

                  if (_filterChip == 'unread') {
                    visibleFriends = friends.where((rel) {
                      final dmRoom = dmRoomsByMembers[rel.friendId];
                      if (dmRoom == null) return false;
                      // Unread = last_message_read_by does not contain this user
                      return !(dmRoom.lastMessageReadBy?.contains(user.id) ?? true);
                    }).toList();
                    visibleUnknownDms = unknownDms.where((r) {
                      return !(r.lastMessageReadBy?.contains(user.id) ?? true);
                    }).toList();
                    if (visibleFriends.isEmpty && visibleUnknownDms.isEmpty) {
                      return _buildEmptyState('All caught up! No unread chats.', Icons.done_all_rounded);
                    }
                  }

                  return ListView(
                    children: [
                      if (dmRooms.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('CONVERSATIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary, letterSpacing: 1.1)),
                        ),
                      // Friends with existing DM rooms
                      ...visibleFriends.map((rel) {
                        final friend = rel.friendProfile;
                        if (friend == null) return const SizedBox.shrink();
                        final dmRoom = dmRoomsByMembers[friend.id];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: friend.avatarUrl == null
                                ? null
                                : CachedNetworkImageProvider(friend.avatarUrl!),
                            child: friend.avatarUrl == null
                                ? Text(
                                    (friend.fullName ?? '?').isNotEmpty ? (friend.fullName![0].toUpperCase()) : '?',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                                  )
                                : null,
                          ),
                          title: Text(friend.fullName ?? 'Student', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            dmRoom?.lastMessage ?? (friend.hasRole(UserRole.lecturer) ? 'Lecturer' : 'Year ${friend.yearLevel}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(dmRoom?.lastMessage != null ? 0.7 : 0.4)),
                          ),
                          trailing: dmRoom != null
                              ? FutureBuilder<int>(
                                  key: ValueKey('dm_badge_${dmRoom.id}_$_badgeRefreshKey'),
                                  future: chatService.getUnreadCount(dmRoom.id, user.id),
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    return count > 0
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                                            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                          )
                                        : const Icon(Icons.chat_outlined, size: 20);
                                  },
                                )
                              : const Icon(Icons.chat_outlined, size: 20),
                          onTap: () async {
                            final existing = dmRoom ?? await chatService.findExistingDm(user.id, friend.id);
                            final room = existing ?? await chatService.createChatRoom(
                              creatorId: user.id,
                              name: friend.fullName ?? 'Chat',
                              isGroup: false,
                              members: [user.id, friend.id],
                            );
                            if (room != null && mounted) _openRoom(room);
                          },
                        );
                      }),
                      // DM rooms from people who messaged you but aren't in your friends list
                      ...visibleUnknownDms.map((room) {
                        final otherId = room.memberIds.firstWhere((id) => id != user.id, orElse: () => '');
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(room.lastMessage ?? 'New conversation', maxLines: 1),
                          trailing: FutureBuilder<int>(
                            key: ValueKey('unk_badge_${room.id}_$_badgeRefreshKey'),
                            future: chatService.getUnreadCount(room.id, user.id),
                            builder: (context, snap) {
                              final count = snap.data ?? 0;
                              return count > 0
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                                      child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  : const Icon(Icons.chat_outlined, size: 20);
                            },
                          ),
                          onTap: () => _openRoom(room),
                        );
                      }),
                      if (visibleFriends.isEmpty && visibleUnknownDms.isEmpty)
                        _buildEmptyState('Add friends using their code!', Icons.people_outline_rounded),
                    ],
                  );
                },
              ),
            );
          },
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
