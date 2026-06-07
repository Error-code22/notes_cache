import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'services.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _StudyAction {
  final IconData icon;
  final String label;
  final String prompt;

  const _StudyAction({
    required this.icon,
    required this.label,
    required this.prompt,
  });
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  bool _privateStudyMode = false;
  int _dailyMessageCount = 0;
  final int _guestLimit = 3;
  final int _userDailyLimit = 20;
  static const List<_StudyAction> _studyActions = [
    _StudyAction(
      icon: Icons.psychology_alt_outlined,
      label: 'Memory hooks',
      prompt: 'Turn this into memorable hooks, analogies, acronyms, and quick recall cues:',
    ),
    _StudyAction(
      icon: Icons.search_outlined,
      label: 'Find notes',
      prompt: 'Search my accessible NotesCache notes for this topic, list the most relevant notes, and suggest what to study first:',
    ),
    _StudyAction(
      icon: Icons.lightbulb_outline,
      label: 'Explain simply',
      prompt: 'Explain this in simple student-friendly language, then give a tiny example:',
    ),
    _StudyAction(
      icon: Icons.style_outlined,
      label: 'Flashcards',
      prompt: 'Create concise flashcards with front/back answers for:',
    ),
    _StudyAction(
      icon: Icons.quiz_outlined,
      label: 'Quiz me',
      prompt: 'Quiz me one question at a time, wait for my answer, then correct me on:',
    ),
    _StudyAction(
      icon: Icons.account_tree_outlined,
      label: 'Mind map',
      prompt: 'Create a clear text mind map with hierarchy and connections for:',
    ),
    _StudyAction(
      icon: Icons.repeat_outlined,
      label: 'Recall drill',
      prompt: 'Run an active recall drill. Ask short questions from easy to hard about:',
    ),
    _StudyAction(
      icon: Icons.calendar_month_outlined,
      label: 'Revision plan',
      prompt: 'Make a spaced revision plan with daily tasks and checkpoints for:',
    ),
  ];

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthService>().currentUser?.id;
    _loadDailyCount();
    _loadChatHistory();
  }

  Future<void> _loadDailyCount() async {
    final aiService = AiChatService();
    final user = context.read<AuthService>().currentUser!;
    final count = user.isGuest
        ? await aiService.getGuestMessageCount()
        : await aiService.getDailyMessageCount(user.id);
    if (mounted) setState(() => _dailyMessageCount = count);
  }

  Future<void> _loadChatHistory() async {
    try {
      if (_currentUserId == null) return;
      final aiService = AiChatService();
      final history = await aiService.loadChatHistory(_currentUserId!);
      if (mounted && history.isNotEmpty) {
        setState(() {
          _messages.clear();
          _messages.addAll(history);
        });
      }
    } catch (e) {
      debugPrint('Load chat history error: $e');
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      if (_currentUserId == null) return;
      final aiService = AiChatService();
      await aiService.saveChatHistory(_currentUserId!, _messages);
    } catch (e) {
      debugPrint('Save chat history error: $e');
    }
  }

  Future<void> _clearChatHistory() async {
    try {
      if (_currentUserId != null) {
        final aiService = AiChatService();
        await aiService.clearChatHistory(_currentUserId!);
      }
      setState(() => _messages.clear());
    } catch (e) {
      debugPrint('Clear chat history error: $e');
    }
  }

  @override
  void dispose() {
    // Don't save here — already saved after each message exchange
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
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _isLoading) return;

    final user = context.read<AuthService>().currentUser!;
    final limit = user.isGuest ? _guestLimit : _userDailyLimit;
    if (_dailyMessageCount >= limit && !user.hasRole(UserRole.admin)) return;

    setState(() { _messages.add({'role': 'user', 'content': text}); _controller.clear(); _isLoading = true; });
    _scrollToBottom();
    try {
      final aiService = AiChatService();
      if (user.isGuest) {
        await aiService.incrementGuestMessageCount();
      } else {
        await aiService.incrementDailyMessageCount(user.id);
      }
      await _loadDailyCount();

      // Send only last 5 messages to Groq for context (keeps quota low)
      final allHistory = _messages.take(_messages.length - 1).toList();
      final contextHistory = aiService.getContextMessages(allHistory);
      final response = await aiService.getResponse(text, contextHistory);
      setState(() { _messages.add({'role': 'assistant', 'content': response}); _isLoading = false; });
      _saveChatHistory();
      _scrollToBottom();
    } catch (e) {
      setState(() { _isLoading = false; _messages.add({'role': 'assistant', 'content': 'Error: $e'}); });
      _saveChatHistory();
      _scrollToBottom();
    }
  }

  Future<void> _runStudyAction(_StudyAction action) async {
    final topic = _controller.text.trim();
    final prompt = topic.isEmpty
        ? '${action.prompt} Use my accessible NotesCache notes if a relevant topic is clear from our conversation. If not, ask me what topic to use.'
        : '${action.prompt}\n\n$topic';
    await _sendText(prompt);
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md', 'dart', 'js', 'py']);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final fileName = result.files.single.name;
        setState(() { _messages.add({'role': 'user', 'content': 'Shared file: $fileName\n\n$content'}); _isLoading = true; });
        _scrollToBottom();
        final aiSvc = AiChatService();
        final ctx = aiSvc.getContextMessages(_messages.take(_messages.length - 1).toList());
        final response = await aiSvc.getResponse('Shared file "$fileName".', ctx);
        setState(() { _messages.add({'role': 'assistant', 'content': response}); _isLoading = false; });
        _saveChatHistory();
        _scrollToBottom();
      }
    } catch (e) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1024);
      if (image != null) {
        final base64Image = base64Encode(await image.readAsBytes());
        setState(() { _messages.add({'role': 'user', 'content': 'Shared an image.'}); _isLoading = true; });
        _scrollToBottom();
        final aiSvc = AiChatService();
        final ctx = aiSvc.getContextMessages(_messages.take(_messages.length - 1).toList());
        final response = await aiSvc.getResponse('Analyze image.', ctx, imageBase64: base64Image);
        setState(() { _messages.add({'role': 'assistant', 'content': response}); _isLoading = false; });
        _saveChatHistory();
        _scrollToBottom();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = _privateStudyMode ? Colors.deepOrange : theme.colorScheme.primary;
    final user = context.watch<AuthService>().currentUser!;
    final isGuest = user.isGuest;
    final limit = isGuest ? _guestLimit : _userDailyLimit;
    final isLimitReached = _dailyMessageCount >= limit && !user.hasRole(UserRole.admin);

    return Scaffold(
      backgroundColor: _privateStudyMode
          ? Color.alphaBlend(Colors.deepOrange.withOpacity(0.05), theme.scaffoldBackgroundColor)
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Study Assistant'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (_messages.isNotEmpty)
            Tooltip(
              message: 'Clear chat history',
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear Chat'),
                      content: const Text('Delete all chat history? This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _clearChatHistory();
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Clear', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Tooltip(
            message: _privateStudyMode ? 'End private study session' : 'Start private study session',
            child: IconButton(
              icon: Icon(_privateStudyMode ? Icons.lock_clock : Icons.lock_outline),
              color: _privateStudyMode ? Colors.deepOrange : null,
              onPressed: _togglePrivateStudyMode,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_privateStudyMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.deepOrange.withOpacity(0.12),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock, size: 16, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Private study session: this chat stays on this screen and is cleared when you leave.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          if (isLimitReached || (limit - _dailyMessageCount <= 5))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isLimitReached ? Colors.red.withOpacity(0.1) : theme.colorScheme.primary.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(isLimitReached ? Icons.block : Icons.info_outline, size: 16, color: isLimitReached ? Colors.red : theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLimitReached
                          ? (isGuest ? 'Demo limit reached! Sign up for more.' : 'Daily limit reached! Come back tomorrow.')
                          : '${isGuest ? "Guest" : "Daily"} Limit: ${(limit - _dailyMessageCount).clamp(0, limit)} messages remaining.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isLimitReached ? Colors.red : theme.colorScheme.primary),
                    ),
                  ),
                  if (isLimitReached && isGuest)
                    TextButton(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                      child: const Text('SIGN UP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme, isEnabled: !isLimitReached)
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

  Widget _buildEmptyState(ThemeData theme, {required bool isEnabled}) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      children: [
        Icon(Icons.auto_awesome_rounded, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        const Center(
          child: Text('Hi, I\'m Notesy!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Text(
          'Pick a study tool below or ask for homework help, summaries, quizzes, revision plans, and note-based explanations.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.65)),
        ),
        const SizedBox(height: 28),
        _buildMemoryPanel(theme, isEnabled: isEnabled && !_isLoading),
      ],
    );
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
          borderRadius: BorderRadius.circular(14),
        ),
        child: isUser
            ? Text(msg['content']!, style: const TextStyle(color: Colors.white, fontSize: 15))
            : MarkdownBody(
                data: msg['content']!,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15, height: 1.35),
                  listBullet: TextStyle(color: theme.colorScheme.primary),
                  strong: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700),
                ),
              ),
      ),
    );
  }

  Widget _buildMemoryPanel(ThemeData theme, {required bool isEnabled}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Memorise Faster',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Paste a topic, note title, or paragraph, then tap a tool. Notesy will turn it into recall-friendly study material.',
            style: TextStyle(fontSize: 13, height: 1.35, color: theme.colorScheme.onSurface.withOpacity(0.68)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _studyActions.map((action) => _studyActionChip(action, theme, isEnabled: isEnabled)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _studyActionChip(_StudyAction action, ThemeData theme, {required bool isEnabled}) {
    return ActionChip(
      avatar: Icon(action.icon, size: 18),
      label: Text(action.label),
      tooltip: action.label,
      onPressed: isEnabled ? () => _runStudyAction(action) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.18)),
    );
  }

  Widget _buildInputArea(ThemeData theme, Color primaryColor) {
    final user = context.watch<AuthService>().currentUser!;
    final limit = user.isGuest ? _guestLimit : _userDailyLimit;
    final isLimitReached = _dailyMessageCount >= limit && !user.hasRole(UserRole.admin);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _studyActions
                  .map((action) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _studyActionChip(action, theme, isEnabled: !isLimitReached && !_isLoading),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !isLimitReached,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: isLimitReached
                      ? 'Limit reached'
                      : (_privateStudyMode ? 'Private study question...' : 'Paste a topic, note title, or homework question...'),
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: isLimitReached ? null : (_) => _sendMessage(),
              ),
            ),
            Tooltip(
              message: 'Attach text file',
              child: IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: (user.isGuest || isLimitReached) ? () => _showGuestNotice(context) : _pickFile,
              ),
            ),
            Tooltip(
              message: 'Scan image',
              child: IconButton(
                icon: const Icon(Icons.camera_alt),
                onPressed: (user.isGuest || isLimitReached) ? () => _showGuestNotice(context) : () => _pickImage(ImageSource.camera),
              ),
            ),
            Tooltip(
              message: 'Send',
              child: IconButton(
                icon: Icon(Icons.send_rounded, color: isLimitReached ? Colors.grey : primaryColor),
                onPressed: isLimitReached ? null : _sendMessage,
              ),
            ),
          ]),
        ],
      ),
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

  void _togglePrivateStudyMode() {
    if (!_privateStudyMode && _messages.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start private study session?'),
          content: const Text('Your current Notesy chat will be cleared so this session stays separate.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _messages.clear();
                  _privateStudyMode = true;
                });
              },
              child: const Text('Start'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      if (_privateStudyMode) _messages.clear();
      _privateStudyMode = !_privateStudyMode;
    });
  }
}
