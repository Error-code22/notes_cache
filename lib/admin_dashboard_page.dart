import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  // Cloudinary usage tracking
  Map<String, dynamic>? _cloudinaryUsage;
  bool _usageLoading = true;

  // Backup coverage
  int _backedUpCount = 0;
  int _totalNoteCount = 0;

  // Usage charts (from DB)
  List<Map<String, dynamic>> _downloadStats = [];
  List<Map<String, dynamic>> _storageGrowth = [];
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCloudinaryUsage();
    _loadUsageCharts();
    _loadBackupCoverage();
  }

  Future<void> _loadBackupCoverage() async {
    final notes = await context.read<NoteService>().fetchAllNotes();
    if (!mounted) return;
    setState(() {
      _totalNoteCount = notes.length;
      _backedUpCount = notes.where((n) => n['telegram_file_id'] != null).length;
    });
  }

  Future<void> _loadCloudinaryUsage() async {
    try {
      final response = await Supabase.instance.client.functions.invoke('cloudinary-usage');
      final data = response.data;
      if (!mounted) return;
      setState(() {
        _cloudinaryUsage = data is Map ? Map<String, dynamic>.from(data) : null;
        _usageLoading = false;
      });
    } catch (e) {
      debugPrint('Cloudinary usage fetch error: $e');
      if (mounted) setState(() => _usageLoading = false);
    }
  }

  Future<void> _loadUsageCharts() async {
    final noteService = context.read<NoteService>();
    final downloads = await noteService.getDownloadStats();
    final growth = await noteService.getStorageGrowth();
    if (!mounted) return;
    setState(() {
      _downloadStats = downloads;
      _storageGrowth = growth;
      _statsLoading = false;
    });
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

          // ===== CLOUDINARY STORAGE =====
          _sectionCard(theme, Icons.cloud_outlined, 'Cloudinary Storage', [
            if (_usageLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_cloudinaryUsage == null || _cloudinaryUsage!['error'] != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _cloudinaryUsage?['error']?.toString() ?? 'Could not load usage data.',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _usageLoading = true);
                        _loadCloudinaryUsage();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else ...[
              _usageBar(
                'Monthly credits used',
                '${(_cloudinaryUsage!['creditsUsedPercent'] ?? 0).toStringAsFixed(2)}%',
                (_cloudinaryUsage!['creditsUsedPercent'] ?? 0).toDouble() / 100,
                Icons.account_balance_wallet_outlined,
                Colors.indigo,
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Free tier = 25 credits/month. Each credit = 1GB storage OR 1GB bandwidth (shared pool).',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              _usageBar(
                'Storage',
                '${((_cloudinaryUsage!['storageBytes'] ?? 0) / 1000000000).toStringAsFixed(2)} GB',
                (_cloudinaryUsage!['storageCreditsPercent'] ?? 0).toDouble() / 100,
                Icons.storage_rounded,
                Colors.blue,
              ),
              const SizedBox(height: 16),
              _usageBar(
                'Bandwidth (this month)',
                '${((_cloudinaryUsage!['bandwidthBytes'] ?? 0) / 1000000000).toStringAsFixed(2)} GB',
                (_cloudinaryUsage!['bandwidthCreditsPercent'] ?? 0).toDouble() / 100,
                Icons.network_check_rounded,
                Colors.green,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.workspace_premium_outlined, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Plan: ${_cloudinaryUsage!['plan'] ?? 'Free'}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _loadCloudinaryUsage,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ]),

          const SizedBox(height: 12),

          // ===== USAGE CHARTS (last 14 days) =====
          _sectionCard(theme, Icons.bar_chart_rounded, 'Usage Charts (last 14 days)', [
            if (_statsLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const Text('Downloads & Bandwidth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _barChart(
                values: [
                  for (final d in _downloadStats)
                    (d['day'].toString().substring(5), (d['bandwidth_bytes'] ?? 0).toDouble()),
                ],
                format: (v) => v >= 1000000
                    ? '${(v / 1000000).toStringAsFixed(1)} MB'
                    : v >= 1000
                        ? '${(v / 1000).toStringAsFixed(0)} KB'
                        : '${v.round()} B',
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              const Text('Uploads & Storage Growth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _barChart(
                values: [
                  for (final d in _storageGrowth)
                    (d['day'].toString().substring(5), (d['storage_bytes'] ?? 0).toDouble()),
                ],
                format: (v) => v >= 1000000
                    ? '${(v / 1000000).toStringAsFixed(1)} MB'
                    : v >= 1000
                        ? '${(v / 1000).toStringAsFixed(0)} KB'
                        : '${v.round()} B',
                color: Colors.blue,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _loadUsageCharts,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
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
            _buildAdminAction(context, 'Feedback Explorer', 'View user bug reports and suggestions', Icons.feedback_outlined, Colors.teal),
            _buildAdminAction(context, 'Push Update', 'Send an announcement to all users', Icons.campaign, Colors.purple),
            _buildAdminAction(context, 'Pricing & Plans', 'View and manage subscription tiers', Icons.monetization_on, Colors.amber),
            _buildAdminAction(context, 'Archive Chats', 'Move old messages to storage to free DB space', Icons.archive, Colors.brown),
            _buildAdminAction(context, 'Re-index Notes', 'Add all old notes to the AI search pile', Icons.auto_awesome, Colors.indigo),
            _buildAdminAction(context, 'Restore from Backup', 'Revive dead notes from the Telegram backup', Icons.restore_rounded, Colors.teal),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.black12, child: Icon(Icons.shield_outlined, color: Colors.black87)),
              title: Text('Telegram backup coverage: $_backedUpCount/$_totalNoteCount notes',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Notes uploaded before backups existed have no copy', style: TextStyle(fontSize: 11)),
              onTap: _loadBackupCoverage,
            ),
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

  Widget _usageBar(String label, String valueText, double fraction, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(valueText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(fraction >= 0.8 ? Colors.red : color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(fraction * 100).toStringAsFixed(2)}% of monthly credits',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  /// Simple dependency-free bar chart: one bar per day.
  Widget _barChart({
    required List<(String label, double value)> values,
    required String Function(double) format,
    required Color color,
  }) {
    if (values.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No data yet', style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    final maxValue = values.map((v) => v.$2).fold(0.0, (a, b) => a > b ? a : b);
    final chartHeight = 140.0;

    return SizedBox(
      height: chartHeight + 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (label, value) in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: '$label: ${format(value)}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: maxValue == 0 ? 2 : (chartHeight * (value / maxValue)).clamp(2.0, chartHeight),
                        decoration: BoxDecoration(
                          color: value > 0 ? color.withOpacity(0.75) : color.withOpacity(0.12),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
        else if (title == 'Re-index Notes') _reindexAllNotes(context);
        else if (title == 'Restore from Backup') _restoreFromBackup(context);
      },
    );
  }

  Future<void> _reindexAllNotes(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-index All Notes'),
        content: const Text('Downloads every PDF/text note and adds it to the AI search pile so Notesy can answer questions about them. Notes already indexed are skipped. This can take a few minutes. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!context.mounted) return;
    final noteService = context.read<NoteService>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Re-indexing notes... this may take a while'), backgroundColor: Colors.blue),
    );

    final result = await noteService.indexAllNotesForAi();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Re-index done: ${result.indexed} indexed, ${result.skipped} already indexed/skipped, ${result.failed} failed'),
        backgroundColor: result.failed == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  /// Restores notes whose Cloudinary file is dead, using the Telegram backup.
  Future<void> _restoreFromBackup(BuildContext context) async {
    final noteService = context.read<NoteService>();
    final messenger = ScaffoldMessenger.of(context);

    // Find dead notes (health check may be cached; fetch fresh status)
    final List<dynamic> notes = await noteService.fetchAllNotes();
    final messenger2 = messenger;
    final dead = <Map<String, dynamic>>[];
    for (final n in notes) {
      final id = n['id'].toString();
      final raw = (n['gdrive_id'] as String?)?.trim() ?? '';
      if (raw.isEmpty) continue;
      final url = raw.contains('://') ? raw : 'https://drive.google.com/uc?export=download&id=$raw';
      try {
        final resp = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) {
          dead.add(n);
        }
      } catch (_) {
        dead.add(n);
      }
    }

    if (dead.isEmpty) {
      messenger2.showSnackBar(
        const SnackBar(content: Text('All notes are healthy — nothing to restore.'), backgroundColor: Colors.green),
      );
      return;
    }

    var restored = 0;
    var skipped = 0;
    for (final n in dead) {
      final id = n['id'].toString();
      if (n['telegram_file_id'] == null) {
        skipped++;
        continue;
      }
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'telegram-restore',
          body: {'noteId': id},
        );
        final data = response.data;
        if (data is Map && data['success'] == true) {
          restored++;
        } else {
          skipped++;
        }
      } catch (e) {
        debugPrint('Restore failed for note $id: $e');
        skipped++;
      }
    }

    messenger2.showSnackBar(
      SnackBar(
        content: Text('Restore done: $restored restored, $skipped skipped (no backup or failed).'),
        backgroundColor: restored > 0 ? Colors.green : Colors.orange,
      ),
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
