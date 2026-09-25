import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services.dart';
import 'push_service.dart';
import 'login_page.dart';
import 'dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

  // Initialize Firebase (for FCM push notifications).
  // Requires android/app/google-services.json — skip gracefully if absent.
  try {
    await Firebase.initializeApp();
    await PushService.instance.init();
  } catch (e) {
    debugPrint('Firebase not configured (google-services.json missing?) — push disabled: $e');
  }

  // Initialize Notifications
  final notificationService = NotificationService();
  await notificationService.init();
  // Route foreground FCM messages through the local notification pipeline
  PushService.instance.setOnPushReceived(
    (title, body) => notificationService.showNotification(title: title, body: body, payload: 'route:/dashboard'),
  );

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
      child: const MyApp(initialRoute: '/dashboard'),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'NotesCache',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      themeMode: themeProvider.themeMode,
      theme: themeProvider.getThemeData(Brightness.light),
      darkTheme: themeProvider.getThemeData(Brightness.dark),
      initialRoute: initialRoute,
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
