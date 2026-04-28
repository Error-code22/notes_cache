// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:notes_cache/services.dart';
import 'package:notes_cache/main.dart';

void main() {
  testWidgets('App builds and shows login page by default', (WidgetTester tester) async {
    // Build our app with initialRoute and required providers.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthService()),
          Provider(create: (_) => NoteService()),
          Provider(create: (_) => NotificationService()),
        ],
        child: const MyApp(initialRoute: '/login'),
      ),
    );

    // Verify that we are on the login page
    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
