import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';
import 'services.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  bool _privateStudyMode = false;
  int _dailyMessageCount = 0;
  final int _guestLimit = 3;
  final int _userDailyLimit = 20;
  static const int _maxImages = 3;
  static const String _vaultPinKey = 'vault_pin';

  // --- conversations (signed-in users) ---
  List<Map<String, dynamic>> _conversations = [];
  int? _currentConversationId;
  bool _loadingConversations = true;

  // --- vault mode ---
  bool _vaultLocked = false;       // decoy showing, real chat hidden
  bool _vaultConversation = false; // current conversation is a vault chat
  String _decoyTitle = '';

  // --- pending images (up to 3) ---
  final List<String> _pendingImageBase64s = [];
  final List<Uint8List> _pendingImageBytesList = [];

  /// Decoded image bytes per base64 string — avoids re-decoding on every
  /// rebuild of the messages list.
  final Map<String, Uint8List> _decodedImageCache = {};

  String? _currentUserId;

  Uint8List? _decodeImage(String base64) {
    var cached = _decodedImageCache[base64];
    if (cached != null) return cached;
    try {
      cached = base64Decode(base64);
      _decodedImageCache[base64] = cached;
      return cached;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = context.read<AuthService>().currentUser?.id;
    _loadDailyCount();
    _loadConversations();
    _maybeShowBetaNotice();
  }

  /// One-time "beta" disclaimer popup on first Notesy open.
  Future<void> _maybeShowBetaNotice() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'notesy_beta_notice_shown';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.science_outlined, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('Notesy is in beta', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Notesy is still in development and can be unpredictable.\n\n'
            'It may make mistakes, misread notes, or give incomplete answers — '
            'always double-check important information with your course materials or lecturer.\n\n'
            'Thanks for being an early tester!',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Auto-lock the vault chat when the app leaves the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_vaultConversation && !_vaultLocked && !_privateStudyMode) {
        _applyDecoy();
      }
    }
  }

  // ==================== CONVERSATIONS ====================

  Future<void> _loadConversations() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.isGuest) {
      if (mounted) setState(() => _loadingConversations = false);
      _loadLegacyGuestHistory();
      return;
    }
    final aiService = AiChatService();
    var convs = await aiService.getConversations(user.id);
    if (convs.isEmpty) {
      final id = await aiService.createConversation(user.id);
      if (id != null) convs = await aiService.getConversations(user.id);
    }
    if (!mounted) return;
    setState(() {
      _conversations = convs;
      _loadingConversations = false;
    });
    if (convs.isNotEmpty) {
      await _openConversation(convs.first['id'].toString());
    }
  }

  Future<void> _openConversation(String convId) async {
    final aiService = AiChatService();
    final msgs = await aiService.loadConversationMessages(convId);
    final conv = _conversations.firstWhere((c) => c['id'].toString() == convId, orElse: () => const {});
    if (!mounted) return;
    setState(() {
      _currentConversationId = int.tryParse(convId);
      _messages
        ..clear()
        ..addAll(msgs);
      _vaultConversation = conv['locked'] == true;
      _vaultLocked = false;
      _privateStudyMode = false;
    });
    _scrollToBottom();
  }

  Future<void> _newConversation() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.isGuest) {
      setState(() {
        _messages.clear();
        _currentConversationId = null;
        _vaultConversation = false;
        _vaultLocked = false;
      });
      return;
    }
    final id = await AiChatService().createConversation(user.id);
    if (id == null || !mounted) return;
    await _loadConversations();
    await _openConversation(id.toString());
  }

  Future<void> _pinConversation(Map<String, dynamic> conv, bool pinned) async {
    await AiChatService().pinConversation(conv['id'].toString(), pinned);
    await _loadConversations();
  }

  Future<void> _renameConversation(Map<String, dynamic> conv) async {
    final controller = TextEditingController(text: conv['title']?.toString() ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null || newTitle.isEmpty) return;
    await AiChatService().renameConversation(conv['id'].toString(), newTitle);
    await _loadConversations();
  }

  Future<void> _deleteConversation(Map<String, dynamic> conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('All messages in this chat will be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiChatService().deleteConversation(conv['id'].toString());
    if (_currentConversationId?.toString() == conv['id'].toString()) {
      await _newConversation();
    } else {
      await _loadConversations();
    }
  }

  // ==================== LEGACY GUEST HISTORY ====================

  Future<void> _loadLegacyGuestHistory() async {
    final aiService = AiChatService();
    if (_currentUserId == null) return;
    final history = await aiService.loadChatHistory(_currentUserId!);
    if (mounted && history.isNotEmpty) {
      setState(() => _messages.addAll(history));
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      if (_currentUserId == null) return;
      final aiService = AiChatService();
      final user = context.read<AuthService>().currentUser;
      // Signed-in users persist per-conversation; guests use legacy prefs.
      if (user != null && !user.isGuest && _currentConversationId != null) {
        return; // handled in _sendText via appendConversationMessages
      }
      await aiService.saveChatHistory(_currentUserId!, _messages);
    } catch (e) {
      debugPrint('Save chat history error: $e');
    }
  }

  // ==================== VAULT MODE ====================

  Future<bool> _authenticate() async {
    try {
      final localAuth = LocalAuthentication();
      final canBiometrics = await localAuth.canCheckBiometrics;
      final hasDeviceSupport = await localAuth.isDeviceSupported();
      if (canBiometrics && hasDeviceSupport) {
        final ok = await localAuth.authenticate(
          localizedReason: 'Unlock your private chat',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (ok) return true;
      }
    } catch (e) {
      debugPrint('Biometrics error: $e');
    }
    // Fallback: PIN
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_vaultPinKey);
    if (pin == null) {
      // First time — set a PIN
      return _setVaultPin(prefs);
    }
    return _enterVaultPin(prefs, pin);
  }

  Future<bool> _setVaultPin(SharedPreferences prefs) async {
    final pinController = TextEditingController();
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set a vault PIN'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(labelText: '4-6 digit PIN', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, pinController.text.trim()), child: const Text('Set PIN')),
        ],
      ),
    );
    // Dispose after the pop animation finishes (controller still in use during it)
    Future<void>.delayed(const Duration(milliseconds: 400), pinController.dispose);
    if (ok == null || ok.isEmpty || ok.length < 4) return false;
    await prefs.setString(_vaultPinKey, ok);
    return true;
  }

  Future<bool> _enterVaultPin(SharedPreferences prefs, String pin) async {
    final pinController = TextEditingController();
    var attempts = 0;
    while (attempts < 3) {
      final entered = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter vault PIN'),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, pinController.text.trim()), child: const Text('Unlock')),
          ],
        ),
      );
      pinController.clear();
      if (entered == null) return false;
      if (entered == pin) {
        Future<void>.delayed(const Duration(milliseconds: 400), pinController.dispose);
        return true;
      }
      attempts++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wrong PIN (${3 - attempts} attempts left)'), backgroundColor: Colors.red),
        );
      }
    }
    pinController.dispose();
    return false;
  }

  /// Loads a random decoy chat from the bundled asset and swaps it in.
  Future<void> _applyDecoy() async {
    try {
      final raw = await rootBundle.loadString('assets/data/decoy_chats.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final decoys = (data['decoys'] as List).cast<Map<String, dynamic>>();
      if (decoys.isEmpty) return;
      final pick = decoys[Random().nextInt(decoys.length)];
      final decoyMsgs = (pick['messages'] as List)
          .map((m) => Map<String, String>.from(m as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _decoyTitle = pick['title']?.toString() ?? 'New chat';
        _messages
          ..clear()
          ..addAll(decoyMsgs);
        _vaultLocked = true;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Decoy load error: $e');
    }
  }

  /// Unlock the vault: biometrics/PIN → restore real messages from DB.
  Future<void> _unlockVault() async {
    if (!await _authenticate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    if (_currentConversationId != null) {
      final msgs = await AiChatService().loadConversationMessages(_currentConversationId!.toString());
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(msgs);
          _vaultLocked = false;
        });
        _scrollToBottom();
      }
    }
  }

  /// Start a vault conversation: biometrics first, then create a locked chat.
  Future<void> _startVaultChat() async {
    if (!await _authenticate()) return;
    // Let the auth dialog finish its exit animation before touching state —
    // continuing immediately deactivates the dialog's elements mid-pop.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to use the vault.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final id = await AiChatService().createConversation(user.id, title: 'Private chat');
    if (id == null) return;
    await AiChatService().renameConversation(id.toString(), 'Private chat');
    // Mark locked
    try {
      await Supabase.instance.client.from('ai_conversations').update({'locked': true}).eq('id', id);
    } catch (e) {
      debugPrint('Mark vault error: $e');
    }
    await _loadConversations();
    await _openConversation(id.toString());
    if (mounted) {
      setState(() => _vaultConversation = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault chat started — it will hide as a decoy when locked.'), backgroundColor: Colors.deepPurple),
      );
    }
  }

  /// Lock now: show the decoy immediately.
  void _lockVaultNow() {
    if (!_vaultConversation) return;
    _applyDecoy();
  }
  /// Shield short press: if in a vault chat, re-lock it (show decoy).
  /// If not in one, open a new vault chat showing a decoy (no PIN needed —
  /// safe to glance at).
  Future<void> _onShieldTap() async {
    if (_vaultConversation) {
      _lockVaultNow();
      return;
    }
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to use the vault.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final id = await AiChatService().createConversation(user.id, title: 'Private chat');
    if (id == null || !mounted) return;
    try {
      await Supabase.instance.client.from('ai_conversations').update({'locked': true}).eq('id', id);
    } catch (e) {
      debugPrint('Mark vault error: $e');
    }
    await _loadConversations();
    await _openConversation(id.toString());
    if (!mounted) return;
    setState(() => _vaultConversation = true);
    await _applyDecoy(); // show a random decoy chat immediately
  }

  /// Shield long press: open the vault PIN/biometrics gate.
  Future<void> _onShieldLongPress() async {
    if (_vaultConversation) {
      await _unlockVault();
    } else {
      await _startVaultChat();
    }
  }

  // ==================== SEND / IMAGES ====================

  Future<void> _loadDailyCount() async {
    final aiService = AiChatService();
    final user = context.read<AuthService>().currentUser!;
    final count = user.isGuest
        ? await aiService.getGuestMessageCount()
        : await aiService.getDailyMessageCount(user.id);
    if (mounted) setState(() => _dailyMessageCount = count);
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
    } catch (e) {
      debugPrint('Error picking or processing file: $e');
    }
  }

  /// Paperclip menu (Gemini-style): Photos / Camera / File.
  void _showAttachMenu() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(backgroundColor: Colors.purple.withValues(alpha: 0.1), child: const Icon(Icons.photo_outlined, color: Colors.purple)),
                title: const Text('Photos'),
                subtitle: Text(_pendingImageBytesList.length >= _maxImages
                    ? 'Up to $_maxImages images allowed'
                    : 'Pick images from your gallery (up to $_maxImages)'),
                onTap: () { Navigator.pop(ctx); _pickImages(ImageSource.gallery); },
              ),
              ListTile(
                leading: CircleAvatar(backgroundColor: Colors.red.withValues(alpha: 0.1), child: const Icon(Icons.camera_alt_outlined, color: Colors.red)),
                title: const Text('Camera'),
                subtitle: Text(_pendingImageBytesList.length >= _maxImages
                    ? 'Up to $_maxImages images allowed'
                    : 'Take a photo to share'),
                onTap: () { Navigator.pop(ctx); _pickImages(ImageSource.camera); },
              ),
              ListTile(
                leading: CircleAvatar(backgroundColor: Colors.blue.withValues(alpha: 0.1), child: const Icon(Icons.insert_drive_file_outlined, color: Colors.blue)),
                title: const Text('File'),
                subtitle: const Text('Share a text file (txt, md, code)'),
                onTap: () { Navigator.pop(ctx); _pickFile(); },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Picks one image and adds it to the pending list (up to 3 total).
  Future<void> _pickImages(ImageSource source) async {
    if (_pendingImageBytesList.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $_maxImages images per message.'), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      final XFile? image = await ImagePicker().pickImage(source: source, imageQuality: 60, maxWidth: 640);
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pendingImageBase64s.add(base64Encode(bytes));
          _pendingImageBytesList.add(bytes);
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _sendText(String text) async {
    if (_isLoading) return;
    final hasImages = _pendingImageBytesList.isNotEmpty;
    final trimmed = text.trim();
    if (trimmed.isEmpty && !hasImages) return;

    final user = context.read<AuthService>().currentUser!;
    final limit = user.isGuest ? _guestLimit : _userDailyLimit;
    if (_dailyMessageCount >= limit && !user.hasRole(UserRole.admin)) return;

    final images = List<String>.from(_pendingImageBase64s);
    setState(() {
      _messages.add({
        'role': 'user',
        'content': trimmed.isEmpty ? (hasImages ? 'Shared ${images.length} image${images.length > 1 ? 's' : ''}.' : '') : trimmed,
        if (images.isNotEmpty) 'image': images.join('|'),
      });
      _controller.clear();
      _pendingImageBase64s.clear();
      _pendingImageBytesList.clear();
      _isLoading = true;
    });
    _scrollToBottom();
    try {
      final aiService = AiChatService();
      if (user.isGuest) {
        await aiService.incrementGuestMessageCount();
      } else {
        await aiService.incrementDailyMessageCount(user.id);
      }
      await _loadDailyCount();

      final allHistory = _messages.take(_messages.length - 1).toList();
      final contextHistory = aiService.getContextMessages(allHistory);
      final prompt = trimmed.isEmpty ? 'Analyze the image${images.length > 1 ? 's' : ''}.' : trimmed;
      final response = await aiService.getResponse(prompt, contextHistory,
          imageBase64s: images.isEmpty ? null : images);

      final assistantMsg = {'role': 'assistant', 'content': response};
      setState(() {
        _messages.add(assistantMsg);
        _isLoading = false;
      });
      // Persist per-conversation for signed-in users
      final signedIn = !user.isGuest;
      if (signedIn && _currentConversationId != null) {
        await aiService.appendConversationMessages(
          user.id,
          _currentConversationId!.toString(),
          _messages[_messages.length - 2],
          assistantMsg,
        );
        // Update title from first user message
        if (_messages.length == 2) {
          await aiService.renameConversation(
            _currentConversationId!.toString(),
            aiService.titleFromMessage(trimmed.isEmpty ? 'Images' : trimmed),
          );
          await _loadConversations();
        }
      } else {
        await _saveChatHistory();
      }
      _scrollToBottom();
    } catch (e) {
      setState(() { _isLoading = false; _messages.add({'role': 'assistant', 'content': 'Error: $e'}); });
      _saveChatHistory();
      _scrollToBottom();
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = _privateStudyMode ? Colors.deepOrange : theme.colorScheme.primary;
    final user = context.watch<AuthService>().currentUser!;
    final isGuest = user.isGuest;
    final limit = isGuest ? _guestLimit : _userDailyLimit;
    final isLimitReached = _dailyMessageCount >= limit && !user.hasRole(UserRole.admin);
    final title = _vaultLocked ? _decoyTitle : (_privateStudyMode ? 'Private Study' : 'Notesy');

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _privateStudyMode
          ? Color.alphaBlend(Colors.deepOrange.withOpacity(0.05), theme.scaffoldBackgroundColor)
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (title == 'Notesy') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'BETA',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.deepPurple),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (!isGuest)
            Tooltip(
              message: _privateStudyMode ? 'End private study session' : 'Start private study session',
              child: IconButton(
                icon: Icon(_privateStudyMode ? Icons.lock_clock : Icons.lock_outline),
                color: _privateStudyMode ? Colors.deepOrange : null,
                onPressed: _togglePrivateStudyMode,
              ),
            ),
          if (!isGuest)
            Tooltip(
              message: 'Shield: tap for quick view · hold to unlock vault',
              child: _VaultButton(
                locked: _vaultLocked,
                inVault: _vaultConversation,
                onTap: _onShieldTap,
                onLongPress: _onShieldLongPress,
              ),
            ),
        ],
      ),
      drawer: isGuest ? null : _buildHistoryDrawer(theme),
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
          if (_vaultLocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.withOpacity(0.12),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Private chat — hold the shield to unlock.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
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

  /// Side slider with all conversations: tap to open, long-press for
  /// pin / rename / delete, "+" for a new chat.
  Widget _buildHistoryDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Chat History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'New chat',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _newConversation,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loadingConversations
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _conversations.isEmpty
                      ? const Center(child: Text('No chats yet.'))
                      : _buildConversationList(theme),
            ),
          ],
        ),
      ),
    );
  }

  /// Conversation list split into normal chats and private (shield) chats.
  Widget _buildConversationList(ThemeData theme) {
    final normal = _conversations.where((c) => c['locked'] != true).toList();
    final vault = _conversations.where((c) => c['locked'] == true).toList();

    Widget tile(Map<String, dynamic> conv) {
      final isCurrent = _currentConversationId?.toString() == conv['id'].toString();
      final isPinned = conv['pinned'] == true;
      final isLocked = conv['locked'] == true;
      return ListTile(
        selected: isCurrent,
        selectedTileColor: isLocked
            ? Colors.blue.withOpacity(0.12)
            : theme.colorScheme.primary.withOpacity(0.08),
        leading: Icon(
          isLocked ? Icons.shield_outlined : (isPinned ? Icons.push_pin : Icons.chat_bubble_outline),
          size: 20,
          color: isLocked ? Colors.blue : null,
        ),
        title: Text(
          conv['title']?.toString() ?? 'Chat',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _formatConvTime(conv['updated_at']?.toString()),
          style: const TextStyle(fontSize: 11),
        ),
        onTap: () {
          Navigator.pop(context);
          _openConversation(conv['id'].toString());
        },
        onLongPress: () {
          showModalBottomSheet<void>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                    title: Text(isPinned ? 'Unpin' : 'Pin'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pinConversation(conv, !isPinned);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Rename'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _renameConversation(conv);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('Delete', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteConversation(conv);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Widget sectionHeader(String label, Color color) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: color),
        ),
      );
    }

    return ListView(
      children: [
        if (normal.isNotEmpty) ...[
          sectionHeader('Chats', theme.colorScheme.primary),
          ...normal.map(tile),
        ],
        if (vault.isNotEmpty) ...[
          sectionHeader('Private', Colors.blue),
          ...vault.map(tile),
        ],
      ],
    );
  }

  String _formatConvTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
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
          'Ask me anything about your notes, homework, or study topics.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.65)),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '⚠ Beta — answers can be imperfect. Double-check important info.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.deepPurple[400]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Map<String, String> msg, ThemeData theme, Color primaryColor) {
    final isUser = msg['role'] == 'user';
    final hasImage = msg['image'] != null && msg['image']!.isNotEmpty;
    // Multiple images are stored pipe-separated in the in-memory message.
    final imageList = hasImage ? msg['image']!.split('|').where((s) => s.isNotEmpty).toList() : <String>[];
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: hasImage ? 8 : 14),
        decoration: BoxDecoration(
          color: isUser ? primaryColor : theme.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageList.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: imageList.map((b64) {
                  return GestureDetector(
                    onTap: () => _showFullImage(b64),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _decodeImage(b64) ?? Uint8List(0),
                        width: 100,
                        height: 100,
                        cacheWidth: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 100,
                          height: 80,
                          child: Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (hasImage && msg['content']!.isNotEmpty) const SizedBox(height: 8),
            if (msg['content']!.isNotEmpty)
              isUser
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
          ],
        ),
      ),
    );
  }

  /// Fullscreen image viewer with a close button (Gemini-style).
  void _showFullImage(String base64Image) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    _decodeImage(base64Image) ?? Uint8List(0),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, Color primaryColor) {
    final user = context.watch<AuthService>().currentUser!;
    final limit = user.isGuest ? _guestLimit : _userDailyLimit;
    final isLimitReached = _dailyMessageCount >= limit && !user.hasRole(UserRole.admin);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pending image previews (up to 3): thumbs + X to remove
            if (_pendingImageBytesList.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      for (var i = 0; i < _pendingImageBytesList.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _pendingImageBytesList[i],
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: -10,
                                right: -10,
                                child: Material(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => setState(() {
                                      _pendingImageBase64s.removeAt(i);
                                      _pendingImageBytesList.removeAt(i);
                                    }),
                                    child: const Padding(
                                      padding: EdgeInsets.all(5),
                                      child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_pendingImageBytesList.length < _maxImages)
                        IconButton(
                          tooltip: 'Add image (${_pendingImageBytesList.length}/$_maxImages)',
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                          onPressed: (user.isGuest || isLimitReached) ? () => _showGuestNotice(context) : () => _pickImages(ImageSource.gallery),
                        ),
                    ],
                  ),
                ),
              ),
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
                    isDense: true,
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
                message: 'Attach photo, image, or file',
                child: IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: (user.isGuest || isLimitReached) ? () => _showGuestNotice(context) : _showAttachMenu,
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

/// Shield action button: short press fires [onTap] (quick decoy view),
/// holding for [holdDuration] fires [onLongPress] (unlock vault).
/// Shows a progress ring while held so the user knows the hold is registering.
class _VaultButton extends StatefulWidget {
  final bool locked;
  final bool inVault;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _VaultButton({
    required this.locked,
    required this.inVault,
    required this.onTap,
    required this.onLongPress,
  });

  static const Duration holdDuration = Duration(milliseconds: 3500);

  @override
  State<_VaultButton> createState() => _VaultButtonState();
}

class _VaultButtonState extends State<_VaultButton> {
  Timer? _holdTimer;
  double _holdProgress = 0.0;
  bool _holding = false;
  bool _longPressFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (_holding) return;
    setState(() {
      _holding = true;
      _holdProgress = 0.0;
    });
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final next = _holdProgress + 50 / _VaultButton.holdDuration.inMilliseconds;
      if (next >= 1.0) {
        t.cancel();
        _holdTimer = null;
        setState(() {
          _holding = false;
          _holdProgress = 0.0;
        });
        // Prevent the release (onTapUp) from ALSO firing the tap action.
        _longPressFired = true;
        widget.onLongPress();
      } else {
        setState(() => _holdProgress = next);
      }
    });
  }

  void _release() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_longPressFired) {
      // Long press already handled it — swallow this release.
      _longPressFired = false;
      setState(() {
        _holding = false;
        _holdProgress = 0.0;
      });
      return;
    }
    setState(() {
      _holding = false;
      _holdProgress = 0.0;
    });
    widget.onTap();
  }

  void _cancel() {
    _holdTimer?.cancel();
    _holdTimer = null;
    setState(() {
      _holding = false;
      _holdProgress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.locked || widget.inVault ? Colors.blue : null;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _release(),
        onTapCancel: _cancel,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Static thin ring; only shows progress while actually holding.
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  value: _holding ? _holdProgress : 0,
                  strokeWidth: 2.5,
                  color: Colors.blue,
                  backgroundColor: Colors.blue.withValues(alpha: 0.1),
                ),
              ),
              Icon(
                widget.locked ? Icons.lock_open : Icons.shield_outlined,
                size: 22,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
