import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'services.dart';
import 'models.dart';
import 'user_manager_page.dart';

// ═══════════════════════════════════════════════════════════════
// ADMIN DASHBOARD — Responsive Grid
// ═══════════════════════════════════════════════════════════════

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  static const _cards = <Map<String, dynamic>>[
    {'name': 'Command Center', 'desc': 'KPIs, usage & health', 'icon': Icons.dashboard_rounded, 'color': Color(0xFF5C6BC0), 'page': 0},
    {'name': 'User Hub', 'desc': 'Roles & verification', 'icon': Icons.group_rounded, 'color': Color(0xFF26A69A), 'page': 1},
    {'name': 'Feedback Central', 'desc': 'Bug reports & ideas', 'icon': Icons.forum_rounded, 'color': Color(0xFF42A5F5), 'page': 2},
    {'name': 'Content Vault', 'desc': 'Notes & backups', 'icon': Icons.library_books_rounded, 'color': Color(0xFF66BB6A), 'page': 3},
    {'name': 'AI Control Room', 'desc': 'Model & limits', 'icon': Icons.psychology_rounded, 'color': Color(0xFFAB47BC), 'page': 4},
    {'name': 'Cloud Status', 'desc': 'Storage & bandwidth', 'icon': Icons.cloud_rounded, 'color': Color(0xFFEF5350), 'page': 5},
    {'name': 'System Health', 'desc': 'Feature toggles & charts', 'icon': Icons.monitor_heart_rounded, 'color': Color(0xFFEC407A), 'page': 6},
    {'name': 'Help & Support', 'desc': 'Contact & channels', 'icon': Icons.headset_mic_rounded, 'color': Color(0xFFFFA726), 'page': 7},
    {'name': 'App Updates', 'desc': 'Announcements', 'icon': Icons.campaign_rounded, 'color': Color(0xFF7E57C2), 'page': 8},
    {'name': 'Plans', 'desc': 'Manage subscription plans', 'icon': Icons.card_membership_rounded, 'color': Color(0xFF26C6DA), 'page': 9},
    {'name': 'Roadmap', 'desc': 'App feature plans', 'icon': Icons.construction_rounded, 'color': Color(0xFF26A69A), 'page': 11},
    {'name': 'Docs & Legal', 'desc': 'About, terms & privacy', 'icon': Icons.description_rounded, 'color': Color(0xFF8D6E63), 'page': 10},
  ];

  static final _pages = <Widget>[
    const _CommandCenterPage(),
    const UserManagerPage(),
    const FeedbackExplorerPage(),
    const _ContentVaultPage(),
    const _AIControlRoomPage(),
    const _CloudStatusPage(),
    const _SystemHealthPage(),
    const _HelpAndSupportPage(),
    const UpdatesManagerPage(),
    const _PlansManagerPage(),
    const _DocsAndLegalPage(),
    const _RoadmapManagerPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = w > 1024 ? 4 : w > 600 ? 3 : 2;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Command Center')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.1,
        ),
        itemCount: _cards.length,
        itemBuilder: (_, i) => _DashboardCard(
          name: _cards[i]['name'] as String,
          desc: _cards[i]['desc'] as String,
          icon: _cards[i]['icon'] as IconData,
          color: _cards[i]['color'] as Color,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _pages[_cards[i]['page'] as int]),
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String name, desc;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.name,
    required this.desc,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha:0.12),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(desc, style: t.bodySmall?.copyWith(color: Colors.grey[500], fontSize: 11), textAlign: TextAlign.center),
              const Spacer(),
              Text('LAUNCH  >', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 1. COMMAND CENTER — KPIs & health overview
// ═══════════════════════════════════════════════════════════════

class _CommandCenterPage extends StatefulWidget {
  const _CommandCenterPage();
  @override State<_CommandCenterPage> createState() => _CommandCenterPageState();
}

class _CommandCenterPageState extends State<_CommandCenterPage> {
  int _totalUsers = 0, _totalNotes = 0, _backedUp = 0;
  Map<String, dynamic>? _cloudinary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final stats = await ns.getAdminStats();
    final notes = await ns.fetchAllNotes();
    final usage = await _fetchCloudinary();
    if (!mounted) return;
    setState(() {
      _totalUsers = stats['totalUsers'] ?? 0;
      _totalNotes = stats['totalNotes'] ?? 0;
      _backedUp = notes.where((n) => n['telegram_file_id'] != null).length;
      _cloudinary = usage;
      _loading = false;
    });
  }

  Future<Map<String, dynamic>?> _fetchCloudinary() async {
    try {
      final r = await Supabase.instance.client.functions.invoke('cloudinary-usage');
      return r.data is Map ? Map<String, dynamic>.from(r.data) : null;
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Command Center')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _kpiRow([
                    _kpi('Users', '$_totalUsers', Icons.group_rounded, Colors.teal),
                    _kpi('Notes', '$_totalNotes', Icons.library_books_rounded, Colors.blue),
                    _kpi('Backed Up', '$_backedUp', Icons.shield_rounded, Colors.green),
                  ]),
                  const SizedBox(height: 16),
                  if (_cloudinary != null && _cloudinary!['error'] == null) ...[
                    Text('Cloudinary Usage', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    _usageBar('Credits', '${(_cloudinary!['creditsUsedPercent'] ?? 0).toStringAsFixed(2)}%',
                        (_cloudinary!['creditsUsedPercent'] ?? 0).toDouble() / 100, Colors.indigo),
                    const SizedBox(height: 8),
                    _usageBar('Storage', '${((_cloudinary!['storageBytes'] ?? 0) / 1e9).toStringAsFixed(2)} GB',
                        (_cloudinary!['storageCreditsPercent'] ?? 0).toDouble() / 100, Colors.blue),
                    const SizedBox(height: 8),
                    _usageBar('Bandwidth', '${((_cloudinary!['bandwidthBytes'] ?? 0) / 1e9).toStringAsFixed(2)} GB',
                        (_cloudinary!['bandwidthCreditsPercent'] ?? 0).toDouble() / 100, Colors.green),
                    const SizedBox(height: 8),
                    Text('Plan: ${_cloudinary!['plan'] ?? 'Free'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                  ],
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. FEEDBACK CENTRAL (was FeedbackExplorerPage)
// ═══════════════════════════════════════════════════════════════

class FeedbackExplorerPage extends StatelessWidget {
  const FeedbackExplorerPage({super.key});
  @override
  Widget build(BuildContext context) {
    final noteService = context.read<NoteService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback Central')),
      body: FutureBuilder<List<AppFeedback>>(
        future: noteService.getAllFeedback(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          if (list.isEmpty) return const Center(child: Text('No feedback yet.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final fb = list[i];
              return ListTile(
                leading: Icon(fb.type == 'bug' ? Icons.bug_report : Icons.lightbulb,
                    color: fb.type == 'bug' ? Colors.red : Colors.blue),
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

// ═══════════════════════════════════════════════════════════════
// 4. CONTENT VAULT — notes, re-index, restore
// ═══════════════════════════════════════════════════════════════

class _ContentVaultPage extends StatefulWidget {
  const _ContentVaultPage();
  @override State<_ContentVaultPage> createState() => _ContentVaultPageState();
}

class _ContentVaultPageState extends State<_ContentVaultPage> {
  List<dynamic> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await context.read<NoteService>().fetchAllNotes();
    if (!mounted) return;
    setState(() { _notes = notes; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Content Vault')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_awesome, color: Colors.indigo),
                    title: const Text('Re-index Notes'),
                    subtitle: const Text('Add all notes to AI search'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _reindex(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded, color: Colors.teal),
                    title: const Text('Restore from Backup'),
                    subtitle: const Text('Revive dead notes from Telegram'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _restore(context),
                  ),
                  const Divider(),
                  Text('${_notes.length} notes total', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
    );
  }

  Future<void> _reindex(BuildContext context) async {
      final ns = context.read<NoteService>();
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: const Text('Re-index All Notes'),
        content: const Text('Downloads every note and adds it to the AI search pile. This can take a few minutes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ));
    if (ok != true || !mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Re-indexing notes...'), backgroundColor: Colors.blue));
    final result = await ns.indexAllNotesForAi();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Done: ${result.indexed} indexed, ${result.skipped} skipped, ${result.failed} failed'),
      backgroundColor: result.failed == 0 ? Colors.green : Colors.orange,
    ));
  }

  Future<void> _restore(BuildContext context) async {
    final ns = context.read<NoteService>();
    final messenger = ScaffoldMessenger.of(context);
    final notes = await ns.fetchAllNotes();
    final candidates = notes.where((n) => (n['gdrive_id'] as String?)?.trim().isNotEmpty == true).toList();
    messenger.showSnackBar(SnackBar(content: Text('Checking ${candidates.length} notes for health...'), backgroundColor: Colors.blue));

    // HEAD checks in parallel batches (was fully serial = minutes on many notes)
    final dead = <Map<String, dynamic>>[];
    for (var i = 0; i < candidates.length; i += 8) {
      final end = i + 8 > candidates.length ? candidates.length : i + 8;
      final batch = candidates.sublist(i, end);
      final results = await Future.wait(batch.map((n) async {
        final raw = (n['gdrive_id'] as String?)?.trim() ?? '';
        final url = raw.contains('://') ? raw : 'https://drive.google.com/uc?export=download&id=$raw';
        try {
          final r = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 8));
          return r.statusCode == 200 ? null : n;
        } catch (_) { return n; }
      }));
      dead.addAll(results.whereType<Map<String, dynamic>>());
    }
    if (dead.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('All notes healthy.'), backgroundColor: Colors.green));
      return;
    }
    var restored = 0, skipped = 0;
    for (final n in dead) {
      if (n['telegram_file_id'] == null) {
        skipped++;
        continue;
      }
      try {
        final r = await Supabase.instance.client.functions.invoke('telegram-restore', body: {'noteId': n['id'].toString()});
        if (r.data is Map && r.data['success'] == true) {
          restored++;
        } else {
          skipped++;
        }
      } catch (_) { skipped++; }
    }
    messenger.showSnackBar(SnackBar(content: Text('Restored: $restored, skipped: $skipped'), backgroundColor: restored > 0 ? Colors.green : Colors.orange));
  }
}

// ═══════════════════════════════════════════════════════════════
// 5. AI CONTROL ROOM — model, search, limits
// ═══════════════════════════════════════════════════════════════

class _AIControlRoomPage extends StatefulWidget {
  const _AIControlRoomPage();
  @override State<_AIControlRoomPage> createState() => _AIControlRoomPageState();
}

class _AIControlRoomPageState extends State<_AIControlRoomPage> {
  String _model = 'llama-3.3-70b-versatile';
  String _visionModel = 'qwen/qwen3.6-27b';
  bool _webSearch = true;
  final _textLimit = TextEditingController();
  final _imageLimit = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final c = await ns.getAppConfig();
    if (!mounted) return;
    setState(() {
      _model = c['ai_model'] ?? 'llama-3.3-70b-versatile';
      _visionModel = c['ai_vision_model'] ?? 'qwen/qwen3.6-27b';
      _webSearch = c['ai_web_search'] != 'false';
      _textLimit.text = c['ai_daily_text_limit'] ?? '50';
      _imageLimit.text = c['ai_daily_image_limit'] ?? '10';
      _loading = false;
    });
  }

  @override
  void dispose() { _textLimit.dispose(); _imageLimit.dispose(); super.dispose(); }

  Future<void> _save(String k, String v) async => context.read<NoteService>().updateAppConfig(k, v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Control Room')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Model', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'llama-3.3-70b-versatile', label: Text('70B'), icon: Icon(Icons.speed)),
                    ButtonSegment(value: 'llama-3.1-8b-instant', label: Text('8B'), icon: Icon(Icons.bolt)),
                  ],
                  selected: {_model},
                  onSelectionChanged: (s) { setState(() => _model = s.first); _save('ai_model', s.first); },
                ),
                const SizedBox(height: 4),
                Text(_model == 'llama-3.3-70b-versatile' ? '70B: Smarter, slower' : '8B: Faster, lighter',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 16),
                const Text('Vision Model (images)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _visionModel,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.image_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'qwen/qwen3.6-27b', child: Text('Qwen 3.6 27B (vision)')),
                    DropdownMenuItem(value: 'llama-3.2-11b-vision-preview', child: Text('Llama 3.2 11B Vision (legacy)')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _visionModel = v);
                    _save('ai_vision_model', v);
                  },
                ),
                const SizedBox(height: 4),
                Text('Used when a user attaches an image. Qwen 3.6 27B is Groq\'s current vision model.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Web Search'),
                  subtitle: const Text('Let AI search the internet when notes don\'t have the answer'),
                  value: _webSearch,
                  onChanged: (v) { setState(() => _webSearch = v); _save('ai_web_search', v.toString()); },
                  secondary: Icon(Icons.language, color: _webSearch ? Colors.green : Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: _textLimit, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Daily Text Limit', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _imageLimit, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Daily Image Limit', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await _save('ai_daily_text_limit', _textLimit.text);
                    await _save('ai_daily_image_limit', _imageLimit.text);
                    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Limits saved'), backgroundColor: Colors.green));
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Limits'),
                ),
                const Divider(height: 32),
                const Text('Test Model', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Probe any model directly — text or image. No usage counted.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                _ModelTester(),
              ],
            ),
    );
  }
}

/// Admin-only model probe: pick a model, type a prompt, optionally attach an
/// image, and see the raw Groq response (via the notesy `test_model` action).
class _ModelTester extends StatefulWidget {
  const _ModelTester();

  @override
  State<_ModelTester> createState() => _ModelTesterState();
}

class _ModelTesterState extends State<_ModelTester> {
  static const _models = [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'qwen/qwen3.6-27b',
    'llama-3.2-11b-vision-preview',
  ];

  String _model = 'qwen/qwen3.6-27b';
  final _prompt = TextEditingController();
  String? _imageBase64;
  String? _imageName;
  bool _testing = false;
  String? _result;
  String? _error;

  @override
  void dispose() { _prompt.dispose(); super.dispose(); }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() {
      _imageBase64 = base64Encode(bytes);
      _imageName = file.name;
    });
  }

  Future<void> _run() async {
    if (_prompt.text.trim().isEmpty && _imageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a prompt or attach an image.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() { _testing = true; _result = null; _error = null; });
    try {
      final response = await Supabase.instance.client.functions.invoke('notesy', body: {
        'action': 'test_model',
        'model': _model,
        'message': _prompt.text.trim(),
        if (_imageBase64 != null) 'imageBase64': _imageBase64,
      });
      final data = response.data;
      if (data is Map && data['content'] != null) {
        if (mounted) setState(() => _result = data['content'].toString());
      } else {
        if (mounted) setState(() => _error = 'Unexpected response: $data');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _model,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.smart_toy_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: const [
            DropdownMenuItem(value: 'llama-3.3-70b-versatile', child: Text('Llama 3.3 70B (text)')),
            DropdownMenuItem(value: 'llama-3.1-8b-instant', child: Text('Llama 3.1 8B (text)')),
            DropdownMenuItem(value: 'qwen/qwen3.6-27b', child: Text('Qwen 3.6 27B (vision)')),
            DropdownMenuItem(value: 'llama-3.2-11b-vision-preview', child: Text('Llama 3.2 11B Vision (legacy)')),
          ],
          onChanged: (v) { if (v != null) setState(() => _model = v); },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _prompt,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Prompt',
            hintText: 'e.g. What does this note teach? / Describe this image.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(
                  _imageName != null && _imageName!.length > 18
                      ? '${_imageName!.substring(0, 15)}…'
                      : (_imageName ?? 'Attach image'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_imageName != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remove image',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() { _imageBase64 = null; _imageName = null; }),
              ),
            ],
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _testing ? null : _run,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 18),
              label: Text(_testing ? 'Testing…' : 'Run Test'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        if (_result != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(_result!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        if (_result != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _result!));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!'), duration: Duration(seconds: 1)));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy result'),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 6. CLOUD STATUS — Cloudinary usage details
// ═══════════════════════════════════════════════════════════════

class _CloudStatusPage extends StatefulWidget {
  const _CloudStatusPage();
  @override State<_CloudStatusPage> createState() => _CloudStatusPageState();
}

class _CloudStatusPageState extends State<_CloudStatusPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Supabase.instance.client.functions.invoke('cloudinary-usage');
      final d = r.data;
      if (mounted) setState(() { _data = d is Map ? Map<String, dynamic>.from(d) : null; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Status')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null || _data!['error'] != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_data?['error']?.toString() ?? 'Could not load', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _usageBar('Credits Used', '${(_data!['creditsUsedPercent'] ?? 0).toStringAsFixed(2)}%',
                          (_data!['creditsUsedPercent'] ?? 0).toDouble() / 100, Colors.indigo),
                      const SizedBox(height: 16),
                      _usageBar('Storage', '${((_data!['storageBytes'] ?? 0) / 1e9).toStringAsFixed(2)} GB',
                          (_data!['storageCreditsPercent'] ?? 0).toDouble() / 100, Colors.blue),
                      const SizedBox(height: 16),
                      _usageBar('Bandwidth (this month)', '${((_data!['bandwidthBytes'] ?? 0) / 1e9).toStringAsFixed(2)} GB',
                          (_data!['bandwidthCreditsPercent'] ?? 0).toDouble() / 100, Colors.green),
                      const SizedBox(height: 12),
                      Text('Free tier = 25 credits/month. Each credit = 1GB storage OR 1GB bandwidth.', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(height: 16),
                      Row(children: [
                        Icon(Icons.workspace_premium_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('Plan: ${_data!['plan'] ?? 'Free'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                      ]),
                    ],
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 7. SYSTEM HEALTH — feature toggles & usage charts
// ═══════════════════════════════════════════════════════════════

class _SystemHealthPage extends StatefulWidget {
  const _SystemHealthPage();
  @override State<_SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<_SystemHealthPage> {
  bool _chatBetaLocked = true;
  bool _showCommsButton = true;
  bool _loading = true;
  List<Map<String, dynamic>> _downloads = [];
  List<Map<String, dynamic>> _growth = [];
  bool _chartsLoading = true;

  @override
  void initState() { super.initState(); _load(); _loadCharts(); }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final c = await ns.getAppConfig();
    if (!mounted) return;
    setState(() {
      _chatBetaLocked = c['chat_beta_locked'] != 'false';
      _showCommsButton = c['show_comms_button'] != 'false';
      _loading = false;
    });
  }

  Future<void> _loadCharts() async {
    final ns = context.read<NoteService>();
    final d = await ns.getDownloadStats();
    final g = await ns.getStorageGrowth();
    if (!mounted) return;
    setState(() { _downloads = d; _growth = g; _chartsLoading = false; });
  }

  Future<void> _save(String k, String v) async => context.read<NoteService>().updateAppConfig(k, v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Health')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: const Text('Communications Page — Beta Lock'),
                  subtitle: Text(_chatBetaLocked ? 'Locked: users see Under Construction' : 'Unlocked: all users can access',
                      style: const TextStyle(fontSize: 12)),
                  value: _chatBetaLocked,
                  onChanged: (v) {
                    setState(() => _chatBetaLocked = v);
                    _save('chat_beta_locked', v.toString());
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(v ? 'Comms locked' : 'Comms unlocked'),
                      backgroundColor: v ? Colors.orange : Colors.green,
                    ));
                  },
                  secondary: Icon(_chatBetaLocked ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                      color: _chatBetaLocked ? Colors.orange : Colors.green),
                ),
                SwitchListTile(
                  title: const Text('Show Communication Button'),
                  subtitle: Text(_showCommsButton
                      ? 'Visible: the Communication card shows on the homepage'
                      : 'Hidden: the Communication card is removed from the homepage',
                      style: const TextStyle(fontSize: 12)),
                  value: _showCommsButton,
                  onChanged: (v) {
                    setState(() => _showCommsButton = v);
                    _save('show_comms_button', v.toString());
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(v ? 'Communication button shown' : 'Communication button hidden'),
                      backgroundColor: v ? Colors.green : Colors.orange,
                    ));
                  },
                  secondary: Icon(_showCommsButton ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      color: _showCommsButton ? Colors.green : Colors.orange),
                ),
                const Divider(height: 32),
                Text('Usage Charts (last 14 days)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (_chartsLoading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  const Text('Downloads & Bandwidth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _barChart(
                    values: [for (final d in _downloads) (d['day'].toString().substring(5), (d['bandwidth_bytes'] ?? 0).toDouble())],
                    format: (v) => v >= 1e6 ? '${(v / 1e6).toStringAsFixed(1)} MB' : v >= 1e3 ? '${(v / 1e3).toStringAsFixed(0)} KB' : '${v.round()} B',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  const Text('Uploads & Storage Growth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _barChart(
                    values: [for (final d in _growth) (d['day'].toString().substring(5), (d['storage_bytes'] ?? 0).toDouble())],
                    format: (v) => v >= 1e6 ? '${(v / 1e6).toStringAsFixed(1)} MB' : v >= 1e3 ? '${(v / 1e3).toStringAsFixed(0)} KB' : '${v.round()} B',
                    color: Colors.blue,
                  ),
                ],
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 8. HELP & SUPPORT — contact info & channels
// ═══════════════════════════════════════════════════════════════

class _HelpAndSupportPage extends StatefulWidget {
  const _HelpAndSupportPage();
  @override State<_HelpAndSupportPage> createState() => _HelpAndSupportPageState();
}

class _HelpAndSupportPageState extends State<_HelpAndSupportPage> {
  final _helpUrl = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _whatsappGroup = TextEditingController();
  final _mpesa = TextEditingController();
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final c = await ns.getAppConfig();
    if (!mounted) return;
    setState(() {
      _helpUrl.text = c['help_center_url'] ?? '';
      _email.text = c['support_email'] ?? '';
      _phone.text = c['support_phone'] ?? '';
      _whatsapp.text = c['support_whatsapp'] ?? '';
      _whatsappGroup.text = c['whatsapp_group_link'] ?? '';
      _mpesa.text = c['mpesa_no'] ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() { _helpUrl.dispose(); _email.dispose(); _phone.dispose(); _whatsapp.dispose(); _whatsappGroup.dispose(); _mpesa.dispose(); super.dispose(); }

  Future<void> _save() async {
    final ns = context.read<NoteService>();
    final messenger = ScaffoldMessenger.of(context);
    final m = {
      'help_center_url': _helpUrl.text, 'support_email': _email.text, 'support_phone': _phone.text,
      'support_whatsapp': _whatsapp.text, 'whatsapp_group_link': _whatsappGroup.text, 'mpesa_no': _mpesa.text,
    };
    for (final e in m.entries) {
      await ns.updateAppConfig(e.key, e.value);
    }
    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Support info saved'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support'), actions: [
        TextButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _field('Help Center URL', _helpUrl, Icons.link, 'https://...'),
                const SizedBox(height: 12),
                _field('Support Email', _email, Icons.email, 'support@...'),
                const SizedBox(height: 12),
                _field('Support Phone', _phone, Icons.phone, '+254...'),
                const SizedBox(height: 12),
                _field('WhatsApp Number', _whatsapp, Icons.chat, '254...'),
                const SizedBox(height: 12),
                _field('WhatsApp Group Link', _whatsappGroup, Icons.group_add, 'https://chat.whatsapp.com/...'),
                const SizedBox(height: 12),
                _field('M-Pesa Number', _mpesa, Icons.payment, '123456'),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 9. APP UPDATES (was UpdatesManagerPage)
// ═══════════════════════════════════════════════════════════════

class UpdatesManagerPage extends StatefulWidget {
  const UpdatesManagerPage({super.key});
  @override
  State<UpdatesManagerPage> createState() => _UpdatesManagerPageState();
}

class _UpdatesManagerPageState extends State<UpdatesManagerPage> {
  List<Map<String, dynamic>> _updates = [];
  bool _loading = true;
  final _title = TextEditingController();
  final _content = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _title.dispose(); _content.dispose(); super.dispose(); }

  Future<void> _load() async {
    final u = await context.read<NoteService>().getAppUpdates();
    if (mounted) setState(() { _updates = u; _loading = false; });
  }

  Future<void> _add() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and message required'), backgroundColor: Colors.orange));
      return;
    }
    final ns = context.read<NoteService>();
    await ns.insertAppUpdate(_title.text.trim(), _content.text.trim());
    _title.clear(); _content.clear();
    if (mounted) Navigator.pop(context);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement sent!'), backgroundColor: Colors.green));
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete update?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
      ],
    ));
    if (ok == true) {
      if (!mounted) return;
      await context.read<NoteService>().deleteAppUpdate(id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Updates'), centerTitle: true, actions: [
        IconButton(tooltip: 'New update', icon: const Icon(Icons.add_rounded), onPressed: () => showDialog(
          context: context, builder: (_) => AlertDialog(
            title: const Text('New Announcement'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _content, maxLines: 3, decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder())),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(onPressed: () { Navigator.pop(context); _add(); }, child: const Text('Send')),
            ],
          ),
        )),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _updates.isEmpty
              ? const Center(child: Text('No updates yet.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _updates.length,
                    itemBuilder: (_, i) {
                      final u = _updates[i];
                      return Card(
                        elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha:0.08))),
                        child: ListTile(
                          leading: const Icon(Icons.campaign_outlined, color: Colors.purple),
                          title: Text(u['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(u['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _delete(u['id'].toString())),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 9b. PLANS MANAGER — add/remove plans (feeds homepage bottom card)
// ═══════════════════════════════════════════════════════════════

class _PlansManagerPage extends StatefulWidget {
  const _PlansManagerPage();
  @override State<_PlansManagerPage> createState() => _PlansManagerPageState();
}

class _PlansManagerPageState extends State<_PlansManagerPage> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _period = TextEditingController();
  final _description = TextEditingController();
  final _features = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _name.dispose(); _price.dispose(); _period.dispose(); _description.dispose(); _features.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final all = await ns.getPricingPlans();
    if (!mounted) return;
    setState(() { _plans = all; _loading = false; });
  }

  Future<void> _addPlan() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan name is required.'), backgroundColor: Colors.orange));
      return;
    }
    final features = _features.text
        .split('\n')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    final ok = await context.read<NoteService>().addPricingPlan(
      name: name,
      price: _price.text.trim().isEmpty ? 'KSh 0' : _price.text.trim(),
      period: _period.text.trim().isEmpty ? 'forever' : _period.text.trim(),
      description: _description.text.trim(),
      features: features,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Plan added!' : 'Failed to add plan.'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) {
      _name.clear(); _price.clear(); _period.clear(); _description.clear(); _features.clear();
      await _load();
    }
  }

  Future<void> _deletePlan(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete plan?'),
        content: const Text('This removes the plan from the homepage. Users won\'t see it anymore.'),
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
    final success = await context.read<NoteService>().deletePricingPlan(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Plan deleted.' : 'Failed to delete plan.'),
      backgroundColor: success ? Colors.green : Colors.red,
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans Manager')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add a plan', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (e.g. Student Pro)', border: OutlineInputBorder())),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: TextField(controller: _price, decoration: const InputDecoration(labelText: 'Price (e.g. KSh 250)', border: OutlineInputBorder()))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _period, decoration: const InputDecoration(labelText: 'Period (e.g. /month)', border: OutlineInputBorder()))),
                          ]),
                          const SizedBox(height: 10),
                          TextField(controller: _description, decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
                          const SizedBox(height: 10),
                          TextField(controller: _features, maxLines: 4,
                              decoration: const InputDecoration(labelText: 'Features — one per line', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _addPlan,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Plan'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('${_plans.length} plan(s)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  if (_plans.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('No plans yet.'))
                  else
                    for (final plan in _plans)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(Icons.card_membership, color: theme.colorScheme.primary, size: 20),
                          ),
                          title: Text(plan['name']?.toString() ?? 'Plan', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(
                            '${plan['price'] ?? ''} ${plan['period'] ?? ''} • ${((plan['features'] as List?) ?? []).length} features',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            onPressed: () => _deletePlan(plan['id'].toString()),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 12. ROADMAP MANAGER — app feature plans (feeds homepage "What's Coming")
// ═══════════════════════════════════════════════════════════════

class _RoadmapManagerPage extends StatefulWidget {
  const _RoadmapManagerPage();
  @override State<_RoadmapManagerPage> createState() => _RoadmapManagerPageState();
}

class _RoadmapManagerPageState extends State<_RoadmapManagerPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _icon = 'construction';

  static const _icons = [
    ('mic', 'Audio / Voice'),
    ('notifications', 'Push notifications'),
    ('draw', 'Draw / Annotate'),
    ('play_circle', 'Video'),
    ('upload', 'Upload'),
    ('translate', 'Translate'),
    ('quiz', 'Quiz'),
    ('construction', 'General'),
  ];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _title.dispose(); _description.dispose(); super.dispose(); }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final all = await ns.getRoadmapItems();
    if (!mounted) return;
    setState(() { _items = all; _loading = false; });
  }

  Future<void> _addItem() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title is required.'), backgroundColor: Colors.orange));
      return;
    }
    final ok = await context.read<NoteService>().addRoadmapItem(
      title: title,
      description: _description.text.trim(),
      icon: _icon,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Added to roadmap!' : 'Failed to add.'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) {
      _title.clear(); _description.clear();
      await _load();
    }
  }

  Future<void> _deleteItem(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from roadmap?'),
        content: const Text('It will disappear from the homepage "What\'s Coming" card.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await context.read<NoteService>().deleteRoadmapItem(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Removed.' : 'Failed to remove.'),
      backgroundColor: success ? Colors.green : Colors.red,
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Roadmap Manager')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add a planned feature', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title (e.g. Audio notes)', border: OutlineInputBorder())),
                          const SizedBox(height: 10),
                          TextField(controller: _description, maxLines: 2,
                              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _icon,
                            decoration: const InputDecoration(labelText: 'Icon', border: OutlineInputBorder()),
                            items: [for (final (value, label) in _icons) DropdownMenuItem(value: value, child: Text(label))],
                            onChanged: (v) { if (v != null) setState(() => _icon = v); },
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add),
                              label: const Text('Add to Roadmap'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('${_items.length} planned feature(s)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Nothing planned yet.'))
                  else
                    for (final item in _items)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.08)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(Icons.construction, color: theme.colorScheme.primary, size: 20),
                          ),
                          title: Text(item['title']?.toString() ?? 'Planned', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: (item['description']?.toString() ?? '').isNotEmpty
                              ? Text(item['description'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            onPressed: () => _deleteItem(item['id'].toString()),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 11. DOCS & LEGAL — about, terms, privacy
// ═══════════════════════════════════════════════════════════════

class _DocsAndLegalPage extends StatefulWidget {
  const _DocsAndLegalPage();
  @override State<_DocsAndLegalPage> createState() => _DocsAndLegalPageState();
}

class _DocsAndLegalPageState extends State<_DocsAndLegalPage> {
  final _about = TextEditingController();
  final _terms = TextEditingController();
  final _privacy = TextEditingController();
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final ns = context.read<NoteService>();
    final c = await ns.getAppConfig();
    if (!mounted) return;
    setState(() {
      _about.text = c['about_text'] ?? 'NotesCache v1.0.0';
      _terms.text = c['terms_and_conditions'] ?? '';
      _privacy.text = c['privacy_policy'] ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() { _about.dispose(); _terms.dispose(); _privacy.dispose(); super.dispose(); }

  Future<void> _save() async {
    final ns = context.read<NoteService>();
    await ns.updateAppConfig('about_text', _about.text);
    await ns.updateAppConfig('terms_and_conditions', _terms.text);
    await ns.updateAppConfig('privacy_policy', _privacy.text);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Docs saved'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Docs & Legal'), actions: [
        TextButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _multiline('About Text', _about, 'NotesCache — Your campus study companion'),
                const SizedBox(height: 12),
                _multiline('Terms & Conditions', _terms, 'Enter your terms of service...'),
                const SizedBox(height: 12),
                _multiline('Privacy Policy', _privacy, 'Enter your privacy policy...'),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared widgets
// ═══════════════════════════════════════════════════════════════

Widget _kpiRow(List<Widget> children) {
  return Row(children: [
    for (int i = 0; i < children.length; i++) ...[
      if (i > 0) const SizedBox(width: 12),
      Expanded(child: children[i]),
    ],
  ]);
}

Widget _kpi(String label, String value, IconData icon, Color color) {
  return Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: color.withValues(alpha:0.2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
    ),
  );
}

Widget _usageBar(String label, String valueText, double fraction, Color color) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(valueText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0), minHeight: 8,
          backgroundColor: color.withValues(alpha:0.12),
          valueColor: AlwaysStoppedAnimation(fraction >= 0.8 ? Colors.red : color),
        ),
      ),
      const SizedBox(height: 2),
      Text('${(fraction * 100).toStringAsFixed(1)}% of monthly credits', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
    ],
  );
}

Widget _barChart({
  required List<(String label, double value)> values,
  required String Function(double) format,
  required Color color,
}) {
  if (values.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('No data yet', style: TextStyle(fontSize: 12, color: Colors.grey)));
  final mx = values.map((v) => v.$2).fold(0.0, (a, b) => a > b ? a : b);
  return SizedBox(
    height: 170,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (label, value) in values)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: '$label: ${format(value)}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: mx == 0 ? 2 : (140 * (value / mx)).clamp(2.0, 140.0),
                  decoration: BoxDecoration(
                    color: value > 0 ? color.withValues(alpha:0.75) : color.withValues(alpha:0.12),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          )),
      ],
    ),
  );
}

Widget _field(String label, TextEditingController c, IconData icon, String hint) {
  return TextField(
    controller: c,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
  );
}

Widget _multiline(String label, TextEditingController c, String hint) {
  return TextField(
    controller: c, maxLines: 5,
    decoration: InputDecoration(labelText: label, hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        alignLabelWithHint: true, contentPadding: const EdgeInsets.all(12)),
  );
}
