import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services.dart';
import 'models.dart';
import 'user_manager_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _helpUrlController = TextEditingController();
  final _privacyController = TextEditingController();
  final _aboutController = TextEditingController();
  final _textLimitController = TextEditingController();
  final _imageLimitController = TextEditingController();
  final _supportEmailController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _mpesaNoController = TextEditingController();
  
  // App Updates Controllers
  final _updateTitleController = TextEditingController();
  final _updateContentController = TextEditingController();
  
  bool _isSaving = false;
  Map<String, dynamic> _stats = {'totalUsers': 0, 'totalNotes': 0, 'storageUsed': '...'};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final noteService = context.read<NoteService>();
    final config = await noteService.getAppConfig();
    final stats = await noteService.getAdminStats();
    
    if (mounted) {
      setState(() {
        _helpUrlController.text = config['help_center_url'] ?? '';
        _privacyController.text = config['privacy_policy'] ?? '';
        _aboutController.text = config['about_text'] ?? '';
        _textLimitController.text = config['ai_daily_text_limit'] ?? '50';
        _imageLimitController.text = config['ai_daily_image_limit'] ?? '10';
        _supportEmailController.text = config['support_email'] ?? 'support@notescache.com';
        _supportPhoneController.text = config['support_phone'] ?? '+254700000000';
        _whatsappController.text = config['support_whatsapp'] ?? '254700000000';
        _mpesaNoController.text = config['mpesa_no'] ?? '123456';
        _stats = stats;
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    final noteService = context.read<NoteService>();
    
    await noteService.updateAppConfig('help_center_url', _helpUrlController.text);
    await noteService.updateAppConfig('privacy_policy', _privacyController.text);
    await noteService.updateAppConfig('about_text', _aboutController.text);
    await noteService.updateAppConfig('ai_daily_text_limit', _textLimitController.text);
    await noteService.updateAppConfig('ai_daily_image_limit', _imageLimitController.text);
    await noteService.updateAppConfig('support_email', _supportEmailController.text);
    await noteService.updateAppConfig('support_phone', _supportPhoneController.text);
    await noteService.updateAppConfig('support_whatsapp', _whatsappController.text);
    await noteService.updateAppConfig('mpesa_no', _mpesaNoController.text);
    
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ System configuration updated!')),
      );
    }
  }

  Future<void> _postUpdate() async {
    final title = _updateTitleController.text.trim();
    final content = _updateContentController.text.trim();
    if (title.isEmpty || content.isEmpty) return;

    setState(() => _isSaving = true);
    final supabase = Supabase.instance.client;
    try {
      await supabase.from('app_updates').insert({
        'title': title,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        _updateTitleController.clear();
        _updateContentController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ App Update Posted Successfully!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error posting update: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Admin Command Center'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.textTheme.titleLarge?.color,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, ${user.fullName ?? "Admin"}',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor),
              ),
              const SizedBox(height: 20),
              
              // Stats Row
              Row(
                children: [
                  _buildStatCard(context, 'Total Users', _stats['totalUsers'].toString(), Icons.people, Colors.blue),
                  const SizedBox(width: 16),
                  _buildStatCard(context, 'Total Notes', _stats['totalNotes'].toString(), Icons.description, Colors.green),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildStatCard(context, 'Storage Used', _stats['storageUsed'], Icons.storage, Colors.orange),
                  const SizedBox(width: 16),
                  _buildStatCard(context, 'Active Drives', '1', Icons.cloud_done, Colors.purple),
                ],
              ),
              
              const SizedBox(height: 30),
              Text(
                'Support & Finance (Live)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.3 : 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    _buildTextField(context, 'Support Email', _supportEmailController, Icons.email_outlined),
                    const SizedBox(height: 16),
                    _buildTextField(context, 'Support Phone (Dialer)', _supportPhoneController, Icons.phone_android_rounded),
                    const SizedBox(height: 16),
                    _buildTextField(context, 'WhatsApp Number (No +)', _whatsappController, Icons.chat_outlined),
                    const SizedBox(height: 16),
                    _buildTextField(context, 'M-Pesa Till/Paybill No', _mpesaNoController, Icons.account_balance_wallet_outlined),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveConfig,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('Update Support Info'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'Post App Update',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.3 : 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    _buildTextField(context, 'Update Title', _updateTitleController, Icons.title),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _updateContentController,
                      maxLines: 4,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Update Content',
                        prefixIcon: Icon(Icons.campaign, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _postUpdate,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('POST UPDATE TO USERS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              Text(
                'System Configuration (App-wide)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
      
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.3 : 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    _buildTextField(context, 'Help Center URL', _helpUrlController, Icons.link),
                    const SizedBox(height: 16),
                    _buildTextField(context, 'Privacy Policy Text', _privacyController, Icons.privacy_tip, maxLines: 3),
                    const SizedBox(height: 16),
                    _buildTextField(context, 'About App Text', _aboutController, Icons.info, maxLines: 2),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(context, 'Daily AI Text Limit', _textLimitController, Icons.chat_bubble_outline, keyboardType: TextInputType.number)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildTextField(context, 'Daily AI Image Limit', _imageLimitController, Icons.image_search_rounded, keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveConfig,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving 
                          ? const CircularProgressIndicator(color: Colors.white) 
                          : const Text('Update Global Settings'),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              Text(
                'Management Tools',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
              
              _buildAdminAction(context, 'Manage Users', 'Promote, demote, or remove accounts', Icons.manage_accounts, Colors.blue),
              _buildAdminAction(context, 'Storage Explorer', 'Manage your Google Drive Pool', Icons.folder_shared, Colors.orange),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(BuildContext context, String label, TextEditingController controller, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.6)),
        filled: true,
        fillColor: theme.scaffoldBackgroundColor.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            Text(title, style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.6), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminAction(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7), fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          if (title == 'Manage Users') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagerPage()));
          }
        },
      ),
    );
  }
}
