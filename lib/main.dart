import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services.dart';
import 'push_service.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'file_viewer_page.dart';
import 'share_intent_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Copy an Open-with document while Supabase starts, then pass it to the
  // app as an initial route instead of pushing during the first frame.
  final initialDocument = ShareIntentService.takeInitialDocument();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Supabase (implicit flow so password reset works on web page)
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  // Local notifications and Firebase are both background work. The dashboard
  // must draw without waiting for either, especially when offline.
  final notificationService = NotificationService();
  unawaited(_initPush(notificationService));
  unawaited(ShareIntentService.init());
  final shared = await initialDocument;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => NoteService()),
        Provider(create: (_) => ChatService()),
        Provider(create: (_) => notificationService),
      ],
      // Always open straight to the dashboard; guests are auto-created by AuthService.
      child: MyApp(
        initialRoute: '/dashboard',
        initialSharedPath: shared?.path,
        initialSharedName: shared?.name,
      ),
    ),
  );
}

Future<void> _initPush(NotificationService notificationService) async {
  await notificationService.init();
  try {
    await Firebase.initializeApp();
    // Route foreground FCM messages through the local notification pipeline.
    PushService.instance.setOnPushReceived(
      (title, body) => notificationService.showNotification(
        title: title,
        body: body,
        payload: 'route:/dashboard',
      ),
    );
    // Registration talks to FCM and Supabase. Run it in the background too:
    // a failed token refresh must never block reading.
    unawaited(PushService.instance.init());
  } catch (e) {
    debugPrint(
      'Firebase not configured (google-services.json missing?) — push disabled: $e',
    );
  }
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final String? initialSharedPath;
  final String? initialSharedName;

  const MyApp({
    super.key,
    required this.initialRoute,
    this.initialSharedPath,
    this.initialSharedName,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Foluma',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      themeMode: themeProvider.themeMode,
      theme: themeProvider.getThemeData(Brightness.light),
      darkTheme: themeProvider.getThemeData(Brightness.dark),
      initialRoute: initialRoute,
      onGenerateInitialRoutes: initialSharedPath == null
          ? null
          : (routeName) => [
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/dashboard'),
                  builder: (_) => const DashboardPage(),
                ),
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/shared-document'),
                  builder: (_) => FileViewerPage(
                    file: File(initialSharedPath!),
                    title: initialSharedName ?? 'Shared document',
                  ),
                ),
              ],
      routes: {
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
      },
      builder: (context, child) {
        // Apply user's text scale preference globally
        final scale = themeProvider.textScale;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: scale),
          child: child!,
        );
      },
    );
  }
}
