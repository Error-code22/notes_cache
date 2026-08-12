import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import 'donate_notes_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final SupabaseKeepAliveService _keepAlive = SupabaseKeepAliveService();
  bool _showCommsButton = true;
  List<Map<String, dynamic>> _roadmapItems = [];

  @override
  void initState() {
    super.initState();
    _connectivity.start();
    _keepAlive.start();
    _loadHomeConfig();
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

        // Ask for notification permission AFTER the first frame so the OS
        // dialog never delays startup (was blocking in main()).
        if (Platform.isAndroid) {
          context.read<NotificationService>().requestPermission();
          unawaited(_checkForUpdate());
        }
      });
  }

  @override
  void dispose() {
    _connectivity.dispose();
    _keepAlive.dispose();
    super.dispose();
  }

  Future<void> _loadHomeConfig() async {
    final ns = context.read<NoteService>();
    final config = await ns.getAppConfig();
    final roadmap = await ns.getRoadmapItems();
    if (!mounted) return;
    setState(() {
      _showCommsButton = config['show_comms_button'] != 'false';
      _roadmapItems = roadmap;
    });
  }

  void _onAuthChanged() {    final authService = context.read<AuthService>();    if (authService.currentUser != null) {
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

      // 4. Homepage live updates: roadmap + config changes made in the
      //    admin dashboard reflect on the homepage immediately.
      supabase.channel('public:home_config').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'roadmap_items',
        callback: (_) => _loadHomeConfig(),
      ).subscribe();
      supabase.channel('public:home_config_app_config').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'app_config',
        callback: (_) => _loadHomeConfig(),
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
              // system mode renders dark on dark OSes; treat it as light for
              // toggling so the FIRST click always produces a visible change.
              final next = provider.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
              provider.setThemeMode(next);
            },
          ),
          PopupMenuButton<String>(
            icon: CircleAvatar(radius: 16, backgroundColor: primaryColor.withOpacity(0.1), child: Icon(Icons.person, size: 20, color: primaryColor)),
            onSelected: (value) {
              if (value == 'profile') Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfilePage()));
              else if (value == 'settings') Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
              else if (value == 'updates') Navigator.push(context, MaterialPageRoute(builder: (context) => const UpdatesPage()));
              else if (value == 'feedback') Navigator.push(context, MaterialPageRoute(builder: (context) => const FeedbackPage()));
              else if (value == 'signin') Navigator.pushNamed(context, '/login');
              else if (value == 'logout') _showLogoutConfirmation(context, authService);
            },
            itemBuilder: (context) => [
              if (user.isGuest) ...[
                const PopupMenuItem(value: 'signin', child: Row(children: [Icon(Icons.login_rounded, size: 20), SizedBox(width: 8), Text('Sign In')])),
                const PopupMenuDivider(),
              ],
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
          // Demo-mode banner — shown for guests
          if (user.isGuest)
            Material(
              color: Colors.amber.shade600,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Demo mode: browsing & donating only. Sign in for full access.',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pushNamed(context, '/login'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(
                            'SIGN IN',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                    Expanded(
                      child: ListView(
                        children: [
                          _buildHubCard(
                            context,
                            'Academic Notes',
                            'Browse and read the shared library',
                            Icons.menu_book_rounded,
                            Colors.blue,
                            () => Navigator.push(context, MaterialPageRoute(builder: (context) => NotesPage(connectivity: _connectivity))),
                          ),
                          const SizedBox(height: 16),
                          _buildHubCard(
                            context,
                            'Donate Notes',
                            'Share notes with everyone on the app',
                            Icons.volunteer_activism,
                            Colors.pink,
                            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DonateNotesPage())),
                          ),
                          const SizedBox(height: 16),
                          if (_showCommsButton)
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
                          const SizedBox(height: 12),
                          _buildHomeBottomCard(context),
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
                            const SizedBox(height: 4),
                            Text(
                              'Quizzes, flashcards & memory tools',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
    );
  }

  /// Homepage bottom card: shows the app's upcoming-features roadmap
  /// (read-only display, NOT a button) with a "Request a feature" button
  /// inside it that opens the feature/bug page.
  Widget _buildHomeBottomCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.construction_rounded, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("What's Coming", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_roadmapItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing planned yet — request a feature below!', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              )
            else
              Column(
                children: _roadmapItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(_roadmapIcon(item['icon']?.toString()), size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['title']?.toString() ?? 'Coming soon',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if ((item['description']?.toString() ?? '').isNotEmpty)
                                Text(item['description'].toString(),
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.lightbulb_outline, size: 20, color: theme.colorScheme.error),
              ),
              title: const Text('Request a feature', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Suggest an idea or report a bug', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FeedbackPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _roadmapIcon(String? name) {
    switch (name) {
      case 'mic': return Icons.mic_rounded;
      case 'notifications': return Icons.notifications_active_rounded;
      case 'draw': return Icons.draw_rounded;
      case 'play_circle': return Icons.play_circle_fill_rounded;
      case 'upload': return Icons.upload_file_rounded;
      case 'translate': return Icons.translate_rounded;
      case 'quiz': return Icons.quiz_rounded;
      default: return Icons.construction_rounded;
    }
  }

  /// Happymod-style updater: compares the installed version with the latest
  /// GitHub release; if newer, offers download + install with a persistent
  /// progress dialog. Also shows a "What's New" popup after updating.
  Future<void> _checkForUpdate() async {
    final updateService = UpdateService();
    final latest = await updateService.getLatestVersion();
    if (latest == null || !mounted) return;

    final packageInfo = await PackageInfo.fromPlatform();
    final installed = packageInfo.version;

    if (!UpdateService.isNewer(installed, latest)) {
      // Up to date — show "What's New" once per version if notes exist.
      if (!await updateService.hasShownWhatsNew(installed)) {
        await updateService.markWhatsNewShown(installed);
        final notes = await updateService.getLatestReleaseNotes();
        if (notes != null && notes.isNotEmpty && mounted) {
          _showWhatsNewDialog(notes);
        }
      }
      return;
    }

    // Already downloaded this version earlier (user dismissed the dialog)?
    if (await updateService.hasCachedApk(latest)) {
      await _showUpdateDialog(updateService, latest, installed, readyToInstall: true);
      return;
    }
    await _showUpdateDialog(updateService, latest, installed);
  }

  void _showWhatsNewDialog(String notes) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text("What's New"),
        content: SingleChildScrollView(
          child: Text(notes, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateDialog(
    UpdateService updateService,
    String latest,
    String installed, {
    bool readyToInstall = false,
  }) async {
    final canInstall = await _canInstallPackages();
    var downloading = !readyToInstall;
    var progress = readyToInstall ? 1.0 : 0.0;
    var done = readyToInstall;
    var failed = false;
    var downloadStarted = false;
    String? downloadedPath;
    final messenger = ScaffoldMessenger.of(context);

    // non-dismissible: user can only use the buttons
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Kick off the download automatically once the dialog is up.
          if (downloading && !downloadStarted) {
            downloadStarted = true;
            Future.microtask(() async {
              downloadedPath = await updateService.downloadApk(onProgress: (received, total) {
                if (total > 0 && ctx.mounted) {
                  setDialogState(() => progress = received / total);
                }
              });
              if (downloadedPath == null) {
                if (ctx.mounted) {
                  setDialogState(() {
                    downloading = false;
                    failed = true;
                  });
                }
              } else {
                await updateService.markDownloaded(latest);
                if (ctx.mounted) {
                  setDialogState(() {
                    downloading = false;
                    done = true;
                    progress = 1.0;
                  });
                }
              }
            });
          }

          return AlertDialog(
            title: Text(done ? 'Install update' : 'Update available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(done
                    ? 'v$latest is downloaded and ready.'
                    : 'A new version of NotesCache is out (v$latest — you have v$installed).\n\nDownloading…'),
                const SizedBox(height: 20),
                if (downloading) ...[
                  LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 8),
                  const SizedBox(height: 8),
                  Text(
                    progress == 0
                        ? 'Starting download…'
                        : '${(progress * 100).toStringAsFixed(0)}% — ${(progress * 40).toStringAsFixed(1)} MB',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ] else if (failed) ...[
                  const Text('Download failed. Check your connection.',
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                ] else if (!done) ...[
                  Text(
                    canInstall
                        ? 'You\'ll be able to install it right away.'
                        : 'You\'ll need to allow NotesCache to install apps in settings first.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            actions: [
              if (!done && !failed)
                TextButton(
                  onPressed: () {
                    // Keep any partial download for next time.
                    if (downloadedPath != null) {
                      updateService.markDownloaded(latest);
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Later'),
                ),
              if (failed)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              if (done)
                ElevatedButton(
                  onPressed: () async {
                    if (!canInstall) {
                      await openAppSettings();
                      if (ctx.mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Enable "Install unknown apps" for NotesCache, then reopen the app to install.'), backgroundColor: Colors.orange),
                        );
                      }
                      return;
                    }
                    final path = downloadedPath ?? await updateService.apkFilePath();
                    final result = await OpenFilex.open(path);
                    if (ctx.mounted && result.type != ResultType.done) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(result.type == ResultType.noAppToOpen
                              ? 'Install blocked. Enable "Install unknown apps" for NotesCache in settings.'
                              : 'Could not open installer: ${result.message}'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  child: Text(canInstall ? 'INSTALL' : 'OPEN SETTINGS'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _canInstallPackages() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.requestInstallPackages.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('Install permission check error: $e');
      return true; // default to trying; installer will surface issues
    }
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
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
  }
}
