import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services.dart';
import 'models.dart';
import 'admin_dashboard_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'notes_page.dart';
import 'chats_list_page.dart';
import 'ai_chat_page.dart';
import 'updates_page.dart';
import 'feedback_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DashboardPageState extends State<DashboardPage> {
  final ConnectivityService _connectivity = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _connectivity.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = context.read<AuthService>();
      final themeProvider = context.read<ThemeProvider>();
      
      authService.updateThemeProvider(themeProvider);
      
      if (authService.currentUser != null) {
        themeProvider.setUserId(authService.currentUser!.id);
        themeProvider.setUserTheme(authService.currentUser!);
        _setupBackgroundNotifications();
      } else {
        // Wait for user to be loaded if session is still recovering
        authService.addListener(_onAuthChanged);
      }

      authService.onYearAutoUpdated = (newYear) {
        _showCongratulationPopup(newYear);
      };
    });
  }

  @override
  void dispose() {
    _connectivity.dispose();
    super.dispose();
  }

  void _onAuthChanged() {    final authService = context.read<AuthService>();
    if (authService.currentUser != null) {
      authService.removeListener(_onAuthChanged);
      final themeProvider = context.read<ThemeProvider>();
      themeProvider.setUserId(authService.currentUser!.id);
      themeProvider.setUserTheme(authService.currentUser!);
      _setupBackgroundNotifications();
    }
  }

  void _setupBackgroundNotifications() {
    final supabase = Supabase.instance.client;
    final ns = context.read<NotificationService>();
    final authService = context.read<AuthService>();
    final user = authService.currentUser;

    if (user != null) {
      // 1. Chat Messages
      supabase.channel('public:chat_messages').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_messages',
        callback: (payload) {
          final msg = payload.newRecord;
          if (msg['sender_id'] != user.id) {
            ns.showNotification(title: 'New Message from ${msg['sender_name']}', body: msg['content']);
          }
        }
      ).subscribe();

      // 2. Document Uploads (Lecturers only)
      supabase.channel('public:notes').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notes',
        callback: (payload) {
          final note = payload.newRecord;
          if (note['target_year'] == user.yearLevel && note['lecturer_name'] != 'Student Upload' && note['lecturer_name'] != 'Guest Contributor') {
            ns.showNotification(title: 'New Material: ${note['title']}', body: 'Uploaded by ${note['lecturer_name']}');
          }
        }
      ).subscribe();

      // 3. App Updates (Admin announcements)
      supabase.channel('public:app_updates').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'app_updates',
        callback: (payload) {
          final update = payload.newRecord;
          ns.showNotification(title: 'App Update: ${update['title']}', body: update['content']);
        }
      ).subscribe();
    }
  }

  void _showCongratulationPopup(int newYear) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 60, color: primaryColor),
            ),
            const SizedBox(height: 24),
            Text('Congratulations!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 12),
            Text('Welcome to your new academic year!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withOpacity(0.7))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12)),
              child: Text('YEAR $newYear', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('LET\'S GET STARTED', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 20,
        toolbarHeight: 64,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user.fullName ?? 'Student', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    user.roles.map((r) => r.name.toUpperCase()).join(' • '),
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (user.hasRole(UserRole.admin)) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboardPage())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(4)),
                      child: const Text('ADMIN', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(context.watch<ThemeProvider>().themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: primaryColor),
            onPressed: () {
              final provider = context.read<ThemeProvider>();
              provider.setThemeMode(provider.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
            },
          ),
          PopupMenuButton<String>(
            icon: CircleAvatar(radius: 16, backgroundColor: primaryColor.withOpacity(0.1), child: Icon(Icons.person, size: 20, color: primaryColor)),
            onSelected: (value) {
              if (value == 'profile') Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage()));
              else if (value == 'settings') Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
              else if (value == 'updates') Navigator.push(context, MaterialPageRoute(builder: (context) => const UpdatesPage()));
              else if (value == 'feedback') Navigator.push(context, MaterialPageRoute(builder: (context) => const FeedbackPage()));
              else if (value == 'logout') _showLogoutConfirmation(context, authService);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person_outline, size: 20), SizedBox(width: 8), Text('My Profile')])),
              const PopupMenuItem(value: 'updates', child: Row(children: [Icon(Icons.campaign_outlined, size: 20), SizedBox(width: 8), Text('Updates')])),
              const PopupMenuItem(value: 'feedback', child: Row(children: [Icon(Icons.bug_report_outlined, size: 20), SizedBox(width: 8), Text('Report a Bug')])),
              const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 20), SizedBox(width: 8), Text('Settings')])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.logout_rounded, size: 20, color: Colors.red), SizedBox(width: 8), Text('SIGN OUT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]))),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Offline banner — shown only when connectivity is lost
          ValueListenableBuilder<bool>(
            valueListenable: _connectivity.isOnline,
            builder: (context, online, _) {
              if (online) return const SizedBox.shrink();
              return Material(
                color: Colors.orange.shade700,
                child: const SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You\'re offline — some features may be unavailable',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Workspace Hub', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Text('Quick access to your academic tools', style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    const SizedBox(height: 32),
                    Expanded(
                      child: ListView(
                        children: [
                          _buildHubCard(
                            context,
                            'Academic Notes',
                            'Access and share study materials',
                            Icons.menu_book_rounded,
                            Colors.blue,
                            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotesPage())),
                          ),
                          const SizedBox(height: 16),
                          _buildHubCard(
                            context,
                            'Communication',
                            'Chat with friends and study groups',
                            Icons.chat_bubble_outline_rounded,
                            Colors.orange,
                            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatsListPage())),
                          ),
                          const SizedBox(height: 16),
                          _buildNotesyMemoryCard(context),
                        ],
                      ),
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

  Widget _buildHubCard(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurface.withOpacity(0.2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesyMemoryCard(BuildContext context) {
    final theme = Theme.of(context);
    final accent = const Color(0xFF7C3AED);
    final warm = const Color(0xFFF59E0B);

    return Card(
      elevation: 0,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withOpacity(0.18)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AiChatPage())),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.psychology_alt_rounded, color: accent, size: 34),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Notesy Memory Lab', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: warm.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('NEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: warm)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Flashcards, quizzes, recall drills, mind maps',
                          style: TextStyle(fontSize: 13, height: 1.3, color: theme.colorScheme.onSurface.withOpacity(0.58)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _FeaturePill(icon: Icons.style_outlined, label: 'Flashcards'),
                  _FeaturePill(icon: Icons.quiz_outlined, label: 'Quiz me'),
                  _FeaturePill(icon: Icons.repeat_outlined, label: 'Recall'),
                  _FeaturePill(icon: Icons.lock_clock, label: 'Private'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Paste a topic and let Notesy turn it into something you can actually remember.',
                      style: TextStyle(fontSize: 12, height: 1.35, color: theme.colorScheme.onSurface.withOpacity(0.52)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.arrow_forward_rounded, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out?'),
        content: const Text('Are you sure you want to sign out of NotesCache?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
  }
}
