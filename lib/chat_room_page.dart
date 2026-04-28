import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (_hasUpdatedRead) return;
    final chatService = context.read<ChatService>();
    final authService = context.read<AuthService>();
    await chatService.updateLastRead(widget.room.id, authService.currentUser!.id);
    if (mounted) setState(() => _hasUpdatedRead = true);
  }

  @override
  void dispose() {
    try {
      final chatService = context.read<ChatService>();
      final authService = context.read<AuthService>();
      if (authService.currentUser != null) {
        chatService.updateLastRead(widget.room.id, authService.currentUser!.id);
      }
    } catch (_) {}
    
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
    _markAsRead();
    _scrollToBottom();
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
                final title = room.isGroup ? room.name : (otherUser?.fullName ?? room.name);
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
          if (widget.room.isGroup && widget.room.createdBy == user.id)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: _showBulkAddDialog,
              tooltip: 'Bulk Add Members',
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
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

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
                          backgroundImage: m.avatarUrl != null ? NetworkImage(m.avatarUrl!) : null,
                          child: m.avatarUrl == null ? const Icon(Icons.person) : null,
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
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, shift: false): () => _sendMessage(chatService, user),
              },
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
