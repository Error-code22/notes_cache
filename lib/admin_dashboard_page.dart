import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services.dart';
import 'models.dart';
import 'user_manager_page.dart';
import 'pricing_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // AI Settings
  String _selectedModel = 'llama-3.3-70b-versatile';
  bool _webSearchEnabled = true;
  final _textLimitController = TextEditingController();
  final _imageLimitController = TextEditingController();

  // Feature Gates
  bool _chatBetaLocked = true;

  // Support & Links
  final _helpUrlController = TextEditingController();
  final _supportEmailController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _whatsappGroupController = TextEditingController();
  final _mpesaNoController = TextEditingController();

  // Content
  final _aboutController = TextEditingController();
  final _termsController = TextEditingController();
  final _privacyController = TextEditingController();

  // App Update
  final _updateTitleController = TextEditingController();
  final _updateContentController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final noteService = context.read<NoteService>();
    final config = await noteService.getAppConfig();
    if (mounted) {
      setState(() {
        // AI
        _selectedModel = config['ai_model'] ?? 'llama-3.3-70b-versatile';
        _webSearchEnabled = config['ai_web_search'] != 'false';
        _textLimitController.text = config['ai_daily_text_limit'] ?? '50';
        _imageLimitController.text = config['ai_daily_image_limit'] ?? '10';
        // Feature gates
        _chatBetaLocked = config['chat_beta_locked'] != 'false';
        // Support
        _helpUrlController.text = config['help_center_url'] ?? '';
        _supportEmailController.text = config['support_email'] ?? '';
        _supportPhoneController.text = config['support_phone'] ?? '';
        _whatsappController.text = config['support_whatsapp'] ?? '';
        _whatsappGroupController.text = config['whatsapp_group_link'] ?? '';
        _mpesaNoController.text = config['mpesa_no'] ?? '';
        // Content
        _aboutController.text = config['about_text'] ?? 'NotesCache v1.0.0';
        _termsController.text = config['terms_and_conditions'] ?? '';
        _privacyController.text = config['privacy_policy'] ?? '';
      });
    }
  }

  Future<void> _saveConfig(String key, String value) async {
    final noteService = context.read<NoteService>();
    await noteService.updateAppConfig(key, value);
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    final configs = {
      'ai_daily_text_limit': _textLimitController.text,
      'ai_daily_image_limit': _imageLimitController.text,
      'help_center_url': _helpUrlController.text,
      'support_email': _supportEmailController.text,
      'support_phone': _supportPhoneController.text,
      'support_whatsapp': _whatsappController.text,
      'whatsapp_group_link': _whatsappGroupController.text,
      'mpesa_no': _mpesaNoController.text,
      'about_text': _aboutController.text,
      'terms_and_conditions': _termsController.text,
      'privacy_policy': _privacyController.text,
    };
    for (final entry in configs.entries) {
      await _saveConfig(entry.key, entry.value);
    }
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All settings saved!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  void dispose() {
    _textLimitController.dispose();
    _imageLimitController.dispose();
    _helpUrlController.dispose();
    _supportEmailController.dispose();
    _supportPhoneController.dispose();
    _whatsappController.dispose();
    _whatsappGroupController.dispose();
    _mpesaNoController.dispose();
    _aboutController.dispose();
    _termsController.dispose();
    _privacyController.dispose();
    _updateTitleController.dispose();
    _updateContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Command Center'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAll,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save All'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== AI SETTINGS =====
          _sectionCard(theme, Icons.smart_toy, 'AI Settings', [
            Text('Model', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'llama-3.3-70b-versatile', label: Text('70B'), icon: Icon(Icons.speed)),
                ButtonSegment(value: 'llama-3.1-8b-instant', label: Text('8B'), icon: Icon(Icons.bolt)),
              ],
              selected: {_selectedModel},
              onSelectionChanged: (Set<String> selection) {
                setState(() => _selectedModel = selection.first);
                _saveConfig('ai_model', selection.first);
              },
            ),
            const SizedBox(height: 4),
            Text(
              _selectedModel == 'llama-3.3-70b-versatile'
                  ? '70B: Smarter, slower, better for complex questions'
                  : '8B: Faster, lighter, good for quick answers',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Web Search'),
              subtitle: const Text('Let AI search the internet when notes don\'t have the answer'),
              value: _webSearchEnabled,
              onChanged: (val) {
                setState(() => _webSearchEnabled = val);
                _saveConfig('ai_web_search', val.toString());
              },
              secondary: Icon(Icons.language, color: _webSearchEnabled ? Colors.green : Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _numberField('Daily Text Limit', _textLimitController)),
                const SizedBox(width: 12),
                Expanded(child: _numberField('Daily Image Limit', _imageLimitController)),
              ],
            ),
          ]),

          const SizedBox(height: 12),

          // ===== SUPPORT & CONTACT =====
          _sectionCard(theme, Icons.support_agent, 'Support & Contact', [
            _textField('Help Center URL', _helpUrlController, Icons.link, 'https://your-help-page.com'),
            const SizedBox(height: 12),
            _textField('Support Email', _supportEmailController, Icons.email, 'support@notescache.com'),
            const SizedBox(height: 12),
            _textField('Support Phone', _supportPhoneController, Icons.phone, '+254700000000'),
            const SizedBox(height: 12),
            _textField('WhatsApp Number', _whatsappController, Icons.chat, '254700000000'),
            const SizedBox(height: 12),
            _textField('WhatsApp Group Link', _whatsappGroupController, Icons.group_add, 'https://chat.whatsapp.com/xxxxx'),
            const SizedBox(height: 12),
            _textField('M-Pesa Number', _mpesaNoController, Icons.payment, '123456'),
          ]),

          const SizedBox(height: 12),

          // ===== APP CONTENT =====
          _sectionCard(theme, Icons.edit_note, 'App Content', [
            _multilineField('About Text', _aboutController, 'NotesCache v1.0.0 — Your campus study companion'),
            const SizedBox(height: 12),
            _multilineField('Terms & Conditions', _termsController, 'Enter your terms of service...'),
            const SizedBox(height: 12),
            _multilineField('Privacy Policy', _privacyController, 'Enter your privacy policy...'),
          ]),

          const SizedBox(height: 12),

          // ===== FEATURE GATES =====
          _sectionCard(theme, Icons.toggle_on_outlined, 'Feature Gates', [
            SwitchListTile(
              title: const Text('Communications Page — Beta Lock'),
              subtitle: Text(
                _chatBetaLocked
                    ? 'Locked: users see "Under Construction" + password gate'
                    : 'Unlocked: all users can access Communications',
                style: const TextStyle(fontSize: 12),
              ),
              value: _chatBetaLocked,
              onChanged: (val) {
                setState(() => _chatBetaLocked = val);
                _saveConfig('chat_beta_locked', val.toString());
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(val ? 'Communications locked (beta only)' : 'Communications unlocked for all users'),
                    backgroundColor: val ? Colors.orange : Colors.green,
                  ),
                );
              },
              secondary: Icon(
                _chatBetaLocked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                color: _chatBetaLocked ? Colors.orange : Colors.green,
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // ===== ADMIN ACTIONS =====
          _sectionCard(theme, Icons.admin_panel_settings, 'Admin Actions', [
            _buildAdminAction(context, 'Manage Users', 'Promote, demote, or remove accounts', Icons.manage_accounts, Colors.blue),
            _buildAdminAction(context, 'Storage Explorer', 'Manage your Google Drive Pool', Icons.folder_shared, Colors.orange),
            _buildAdminAction(context, 'Feedback Explorer', 'View user bug reports and suggestions', Icons.feedback_outlined, Colors.teal),
            _buildAdminAction(context, 'Push Update', 'Send an announcement to all users', Icons.campaign, Colors.purple),
            _buildAdminAction(context, 'Pricing & Plans', 'View and manage subscription tiers', Icons.monetization_on, Colors.amber),
            _buildAdminAction(context, 'Archive Chats', 'Move old messages to storage to free DB space', Icons.archive, Colors.brown),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _archiveChats(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Old Messages'),
        content: const Text('This will move messages older than 50 per room to Supabase Storage. Recent messages stay in the database. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archive Now')),
        ],
      ),
    );

    if (confirmed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archiving started...'), backgroundColor: Colors.blue),
      );
      try {
        final chatService = ChatService();
        await chatService.archiveAllRooms();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Archiving complete! Old messages moved to storage.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Archive error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ===== Reusable Widgets =====

  Widget _sectionCard(ThemeData theme, IconData icon, String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller, IconData icon, String hint) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _multilineField(String label, TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  Widget _buildAdminAction(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        if (title == 'Manage Users') Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagerPage()));
        else if (title == 'Feedback Explorer') Navigator.push(context, MaterialPageRoute(builder: (context) => const FeedbackExplorerPage()));
        else if (title == 'Push Update') _showPushUpdateDialog(context);
        else if (title == 'Pricing & Plans') Navigator.push(context, MaterialPageRoute(builder: (context) => const PricingPage()));
        else if (title == 'Archive Chats') _archiveChats(context);
      },
    );
  }

  void _showPushUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Push Announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _updateTitleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _updateContentController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final noteService = context.read<NoteService>();
              await noteService.insertAppUpdate(_updateTitleController.text, _updateContentController.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _updateTitleController.clear();
              _updateContentController.clear();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Announcement sent!'), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class FeedbackExplorerPage extends StatelessWidget {
  const FeedbackExplorerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final noteService = context.read<NoteService>();
    return Scaffold(
      appBar: AppBar(title: const Text('User Feedback Explorer')),
      body: FutureBuilder<List<AppFeedback>>(
        future: noteService.getAllFeedback(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final feedbackList = snapshot.data!;
          if (feedbackList.isEmpty) return const Center(child: Text('No feedback yet.'));
          return ListView.builder(
            itemCount: feedbackList.length,
            itemBuilder: (context, i) {
              final fb = feedbackList[i];
              return ListTile(
                leading: Icon(fb.type == 'bug' ? Icons.bug_report : Icons.lightbulb, color: fb.type == 'bug' ? Colors.red : Colors.blue),
                title: Text(fb.content),
                subtitle: Text('By: ${fb.userName ?? fb.userId}'),
              );
            },
          );
        },
      ),
    );
  }
}
