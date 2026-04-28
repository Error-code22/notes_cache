import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'services.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  int _guestMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadGuestCount();
  }

  Future<void> _loadGuestCount() async {
    final aiService = AiChatService();
    final count = await aiService.getGuestMessageCount();
    if (mounted) setState(() => _guestMessageCount = count);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    final user = context.read<AuthService>().currentUser!;
    if (user.isGuest && _guestMessageCount >= 3) return;

    setState(() { _messages.add({'role': 'user', 'content': text}); _controller.clear(); _isLoading = true; });
    _scrollToBottom();
    try {
      final aiService = AiChatService();
      if (user.isGuest) {
        await aiService.incrementGuestMessageCount();
        await _loadGuestCount();
      }

      final history = _messages.take(_messages.length - 1).toList();
      final response = await aiService.getResponse(text, history);
      setState(() { _messages.add({'role': 'assistant', 'content': response}); _isLoading = false; });
      _scrollToBottom();
    } catch (e) {
      setState(() { _isLoading = false; _messages.add({'role': 'assistant', 'content': 'Error: $e'}); });
      _scrollToBottom();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md', 'dart', 'js', 'py']);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final fileName = result.files.single.name;
        setState(() { _messages.add({'role': 'user', 'content': '📎 Shared File: $fileName\n\n$content'}); _isLoading = true; });
        _scrollToBottom();
        final response = await AiChatService().getResponse('Shared file "$fileName".', _messages.take(_messages.length - 1).toList());
        setState(() { _messages.add({'role': 'assistant', 'content': response}); _isLoading = false; });
        _scrollToBottom();
      }
    } catch (e) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1024);
      if (image != null) {
        final base64Image = base64Encode(await image.readAsBytes());
        setState(() { _messages.add({'role': 'user', 'content': '📸 Shared an image.'}); _isLoading = true; });
        _scrollToBottom();
        final response = await AiChatService().getResponse('Analyze image.', _messages.take(_messages.length - 1).toList(), imageBase64: base64Image);
        setState(() { _messages.add({'role': 'assistant', 'content': response}); _isLoading = false; });
        _scrollToBottom();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final user = context.watch<AuthService>().currentUser!;
    final isGuest = user.isGuest;
    final isLimitReached = isGuest && _guestMessageCount >= 3;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Study Assistant'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (isGuest)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.primary.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLimitReached 
                          ? 'Demo limit reached! Sign up for unlimited AI.' 
                          : 'Guest Mode: ${3 - _guestMessageCount} messages remaining.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                  ),
                  if (isLimitReached)
                    TextButton(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                      child: const Text('SIGN UP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _buildMessageBubble(msg, theme, primaryColor);
                    },
                  ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor.withOpacity(0.5))),
                  const SizedBox(width: 8),
                  Text('Thinking...', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ],
              ),
            ),
          _buildInputArea(theme, primaryColor),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.auto_awesome_rounded, size: 64, color: theme.colorScheme.primary),
      const SizedBox(height: 32),
      const Text('Hi, I\'m Notesy!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    ]));
  }

  Widget _buildMessageBubble(Map<String, String> msg, ThemeData theme, Color primaryColor) {
    final isUser = msg['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isUser ? primaryColor : theme.cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(msg['content']!, style: TextStyle(color: isUser ? Colors.white : theme.colorScheme.onSurface, fontSize: 15)),
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, Color primaryColor) {
    final user = context.watch<AuthService>().currentUser!;
    final isBlocked = user.isGuest && _guestMessageCount >= 3;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !isBlocked,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: isBlocked ? 'Trial ended. Sign up!' : 'Ask me anything...', 
              border: InputBorder.none
            ),
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.attach_file), 
          onPressed: (user.isGuest || isBlocked) ? () => _showGuestNotice(context) : _pickFile
        ),
        IconButton(
          icon: const Icon(Icons.camera_alt), 
          onPressed: (user.isGuest || isBlocked) ? () => _showGuestNotice(context) : () => _pickImage(ImageSource.camera)
        ),
        IconButton(
          icon: Icon(Icons.send_rounded, color: isBlocked ? Colors.grey : primaryColor), 
          onPressed: isBlocked ? null : _sendMessage
        ),
      ]),
    );
  }

  void _showGuestNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Media uploads are for registered users. Sign up to unlock!'),
        backgroundColor: Colors.indigo,
      ),
    );
  }
}
