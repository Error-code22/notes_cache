import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services.dart';
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

  // Initialize Notifications
  final notificationService = NotificationService();
  await notificationService.init();

  // Load the current session to check if user is already logged in
  final session = Supabase.instance.client.auth.currentSession;
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => NoteService()),
        Provider(create: (_) => ChatService()),
        Provider(create: (_) => notificationService),
      ],
      child: MyApp(initialRoute: session != null ? '/dashboard' : '/login'),
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
      themeMode: themeProvider.themeMode,
      theme: themeProvider.getThemeData(Brightness.light),
      darkTheme: themeProvider.getThemeData(Brightness.dark),
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
      },
    );
  }
}
