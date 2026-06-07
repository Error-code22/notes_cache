import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services.dart';
import 'models.dart';

class ChatRoomPage extends StatefulWidget {
  final ChatRoom room;
  const ChatRoomPage({super.key, required this.room});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _bulkCodesController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Per-chat local settings (stored in state — could be persisted to SharedPreferences later)
  bool _notificationsEnabled = true;
  bool _mediaAutoDownload = true;
  String _chatWallpaper = 'default'; // 'default' | 'dots' | 'dark'

  int _refreshCounter = 0;
  DateTime? _lastReadAt;
  bool _hasUpdatedRead = false;

  @override
  void initState() {
    super.initState();
    _loadLastRead();
    _scrollController.addListener(_onScroll);
    // Automatically mark as read after a short delay if the user is in the room
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_hasUpdatedRead) _markAsRead();
    });
  }

  Future<void> _loadLastRead() async {
    final chatService = context.read<ChatService>();
    final authService = context.read<AuthService>();
    final dt = await chatService.getLastReadAt(widget.room.id, authService.currentUser!.id);
    if (mounted) setState(() => _lastReadAt = dt);
  }

  void _onScroll() {
    if (!_hasUpdatedRead && _scrollController.hasClients && _scrollController.offset > 100) {
      _markAsRead();
    }
  }

  Future<void> _markAsRead() async {
    // Always update last-read so new messages after the initial read are also cleared
    final chatService = context.read<ChatService>();
    final authService = context.read<AuthService>();
    await chatService.updateLastRead(widget.room.id, authService.currentUser!.id);
    if (mounted) setState(() => _hasUpdatedRead = true);
  }

  @override
  void dispose() {
    // Mark as read on exit — use cached services before widget tree teardown
    _messageController.dispose();
    _bulkCodesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showBulkAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Members in Bulk'),
        content: TextField(
          controller: _bulkCodesController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter friend codes (comma separated)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final codes = _bulkCodesController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              if (codes.isEmpty) return;

              final chatService = context.read<ChatService>();
              final count = await chatService.bulkAddByCodes(widget.room.id, codes);
              
              Navigator.pop(context);
              _bulkCodesController.clear();
              
              if (count > 0 && mounted) {
                setState(() {
                  _refreshCounter++; // Force a UI refresh
                });
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added $count new members!')),
              );
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(ChatService chatService, UserProfile user) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await chatService.sendMessage(widget.room.id, user.id, text, user.fullName ?? 'User');
    // Always mark as read after sending — we're clearly up to date
    final authService = context.read<AuthService>();
    await chatService.updateLastRead(widget.room.id, authService.currentUser!.id);
    _scrollToBottom();

    // Trigger archiving if room has too many messages (async, don't await)
    chatService.archiveOldMessages(widget.room.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final chatService = context.read<ChatService>();
    final user = context.watch<AuthService>().currentUser!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: StreamBuilder<ChatRoom>(
          key: ValueKey('room_stream_$_refreshCounter'),
          stream: chatService.getRoomStream(widget.room.id),
          builder: (context, snapshot) {
            final room = snapshot.data ?? widget.room;
            return FutureBuilder<UserProfile?>(
              future: chatService.getOtherMemberProfile(room, user.id),
              builder: (context, snapshot) {
                final otherUser = snapshot.data;
                // For DMs: always use the resolved other user's name, never the stored room name
                final title = room.isGroup
                    ? room.name
                    : (otherUser?.fullName ?? '...');
                final sub = room.isGroup
                    ? '${room.memberIds.length} members'
                    : (otherUser?.hasRole(UserRole.lecturer) ?? false ? 'Lecturer' : 'Student');

                return InkWell(
                  onTap: () => _showRoomDetails(room, chatService),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(sub, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                );
              },
            );
          },
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _showRoomSettings(context, chatService, user),
            tooltip: 'Chat Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: chatService.getMessagesStream(widget.room.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!;
                // Only scroll to bottom on initial load, not on every update
                if (messages.isNotEmpty && _scrollController.hasClients) {
                  final pos = _scrollController.position;
                  final nearBottom = pos.maxScrollExtent - pos.pixels < 120;
                  if (nearBottom || pos.maxScrollExtent == 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                  }
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == user.id;
                    
                    bool showNewSeparator = false;
                    if (!_hasUpdatedRead && _lastReadAt != null && msg.timestamp.isAfter(_lastReadAt!)) {
                       // Show separator if this is the first unread message
                       if (index == 0 || messages[index-1].timestamp.isBefore(_lastReadAt!)) {
                         showNewSeparator = true;
                       }
                    }

                    return Column(
                      children: [
                        if (showNewSeparator) _buildNewMessagesSeparator(theme),
                        _buildMessageBubble(msg, isMe, theme, primaryColor),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _buildInputArea(theme, primaryColor, chatService, user),
        ],
      ),
    );
  }

  Widget _buildNewMessagesSeparator(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.colorScheme.primary.withOpacity(0.2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'NEW MESSAGES',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary, letterSpacing: 1.2),
            ),
          ),
          Expanded(child: Divider(color: theme.colorScheme.primary.withOpacity(0.2))),
        ],
      ),
    );
  }

  void _showRoomSettings(BuildContext context, ChatService chatService, UserProfile user) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isCreator = widget.room.isGroup && widget.room.createdBy == user.id;
    final screenWidth = MediaQuery.of(context).size.width;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return SlideTransition(
          position: slide,
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: screenWidth * 0.82,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(-4, 0))],
                ),
                child: StatefulBuilder(
                  builder: (ctx2, setSheetState) => SafeArea(
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.3))),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: primaryColor.withOpacity(0.1),
                                child: Icon(widget.room.isGroup ? Icons.groups_rounded : Icons.person_rounded, color: primaryColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.room.isGroup ? widget.room.name : 'Chat Settings', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    Text(widget.room.isGroup ? '${widget.room.memberIds.length} members' : 'Direct message', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                  ],
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx2)),
                            ],
                          ),
                        ),

                        // Settings list
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [

                              // ── INFO ────────────────────────────────────
                              _settingsSection('INFO', theme),
                              _settingsTile(
                                icon: Icons.info_outline_rounded,
                                color: primaryColor,
                                title: widget.room.isGroup ? 'Group Info' : 'View Profile',
                                subtitle: widget.room.isGroup ? 'Members, description, creator' : 'User details',
                                theme: theme,
                                onTap: () { Navigator.pop(ctx2); _showRoomDetails(widget.room, chatService); },
                              ),
                              if (isCreator)
                                _settingsTile(
                                  icon: Icons.person_add_alt_1_rounded,
                                  color: Colors.green,
                                  title: 'Add Members',
                                  subtitle: 'Invite via friend code',
                                  theme: theme,
                                  onTap: () { Navigator.pop(ctx2); _showBulkAddDialog(); },
                                ),

                              const SizedBox(height: 8),
                              // ── NOTIFICATIONS ────────────────────────────
                              _settingsSection('NOTIFICATIONS', theme),
                              _settingsSwitchTile(
                                icon: Icons.notifications_outlined,
                                color: Colors.orange,
                                title: 'Notifications',
                                subtitle: _notificationsEnabled ? 'You will be notified' : 'Muted',
                                value: _notificationsEnabled,
                                theme: theme,
                                onChanged: (v) => setSheetState(() => _notificationsEnabled = v),
                              ),
                              _settingsSwitchTile(
                                icon: Icons.download_outlined,
                                color: Colors.blue,
                                title: 'Auto-download Media',
                                subtitle: 'Automatically save shared files',
                                value: _mediaAutoDownload,
                                theme: theme,
                                onChanged: (v) => setSheetState(() => _mediaAutoDownload = v),
                              ),

                              const SizedBox(height: 8),
                              // ── APPEARANCE ───────────────────────────────
                              _settingsSection('APPEARANCE', theme),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Chat Wallpaper', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.colorScheme.onSurface)),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _wallpaperChip('default', 'Plain', theme, setSheetState),
                                        const SizedBox(width: 8),
                                        _wallpaperChip('dots', 'Dots', theme, setSheetState),
                                        const SizedBox(width: 8),
                                        _wallpaperChip('dark', 'Dark', theme, setSheetState),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),
                              // ── PRIVACY ──────────────────────────────────
                              _settingsSection('PRIVACY', theme),
                              _settingsTile(
                                icon: Icons.search_outlined,
                                color: Colors.purple,
                                title: 'Search in Chat',
                                subtitle: 'Find specific messages',
                                theme: theme,
                                onTap: () {
                                  Navigator.pop(ctx2);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search in chat coming soon')));
                                },
                              ),
                              _settingsTile(
                                icon: Icons.block_rounded,
                                color: Colors.deepOrange,
                                title: widget.room.isGroup ? 'Leave Group' : 'Block User',
                                subtitle: widget.room.isGroup ? 'Remove yourself from this group' : 'Stop receiving messages',
                                theme: theme,
                                onTap: () {
                                  Navigator.pop(ctx2);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.room.isGroup ? 'Leave group coming soon' : 'Block user coming soon')));
                                },
                              ),

                              // ── DANGER ZONE ──────────────────────────────
                              if (isCreator) ...[
                                const SizedBox(height: 8),
                                _settingsSection('DANGER ZONE', theme, color: Colors.red),
                                _settingsTile(
                                  icon: Icons.delete_forever_rounded,
                                  color: Colors.red,
                                  title: 'Delete Group',
                                  subtitle: 'Permanently delete for everyone',
                                  theme: theme,
                                  titleColor: Colors.red,
                                  onTap: () { Navigator.pop(ctx2); _confirmDeleteGroup(chatService); },
                                ),
                              ],

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _settingsSection(String title, ThemeData theme, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: color ?? theme.colorScheme.primary)),
    );
  }

  Widget _settingsTile({required IconData icon, required Color color, required String title, required String subtitle, required ThemeData theme, required VoidCallback onTap, Color? titleColor}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: titleColor)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: onTap,
    );
  }

  Widget _settingsSwitchTile({required IconData icon, required Color color, required String title, required String subtitle, required bool value, required ThemeData theme, required ValueChanged<bool> onChanged}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Widget _wallpaperChip(String value, String label, ThemeData theme, StateSetter setSheetState) {
    final isSelected = _chatWallpaper == value;
    return GestureDetector(
      onTap: () => setSheetState(() { _chatWallpaper = value; setState(() {}); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? theme.colorScheme.primary : theme.dividerColor.withOpacity(0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.7))),
      ),
    );
  }

  void _confirmDeleteGroup(ChatService chatService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Delete Group?'),
          ],
        ),
        content: Text(
          'This will permanently delete "${widget.room.name}" and all its messages. This cannot be undone.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await chatService.deleteRoom(widget.room.id);
              if (mounted) {
                if (success) {
                  Navigator.pop(context); // Back to chat list
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Group deleted'), backgroundColor: Colors.red),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete group'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _showRoomDetails(ChatRoom room, ChatService chatService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<List<UserProfile>>(
              future: chatService.getRoomMembers([room.createdBy ?? '']),
              builder: (context, snapshot) {
                final creatorName = snapshot.data?.first.fullName ?? 'Unknown';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Created by: $creatorName', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(room.description ?? 'No description provided.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
            const Divider(height: 32),
            const Text('MEMBERS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Flexible(
              child: FutureBuilder<List<UserProfile>>(
                future: () async {
                   final ids = List<String>.from(room.memberIds);
                   if (room.createdBy != null && !ids.contains(room.createdBy!)) {
                     ids.insert(0, room.createdBy!);
                   }
                   return chatService.getRoomMembers(ids);
                }(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final members = snapshot.data!;
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final m = members[index];
                      final isCreator = m.id == room.createdBy;
                      String code = m.friendCode ?? '---';
                      if (code.length == 6 && !code.contains('-')) {
                        code = '${code.substring(0, 3)}-${code.substring(3)}';
                      }
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: NetworkImage(m.avatarUrl ?? AuthService.getDefaultAvatarUrl(m.fullName, m.id)),
                        ),
                        title: Row(
                          children: [
                            Text(m.fullName ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (isCreator) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('CREATOR', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text('[${code.toUpperCase()}]', style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.account_circle_outlined, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 8),
                Text(
                  'LOGGED IN AS: ${context.read<AuthService>().currentUser?.fullName?.toUpperCase() ?? 'UNKNOWN'}',
                  style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe, ThemeData theme, Color primaryColor) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && widget.room.isGroup)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(msg.senderName ?? 'User', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMe ? primaryColor : theme.cardColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 16),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Text(
              msg.content,
              style: TextStyle(
                color: isMe ? Colors.white : theme.colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, Color primaryColor, ChatService chatService, UserProfile user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              maxLines: null,
              style: TextStyle(color: theme.colorScheme.onSurface),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(chatService, user),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _sendMessage(chatService, user),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
