import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/server_manager.dart';
import 'core/visitor_tracker.dart';
import 'core/preferences_service.dart';
import 'features/dashboard/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  final prefsService = await PreferencesService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VisitorTracker()),
        ChangeNotifierProxyProvider<VisitorTracker, ServerManager>(
          create: (context) {
            final manager = ServerManager(context.read<VisitorTracker>());
            manager.init(prefsService);
            return manager;
          },
          update: (_, visitorTracker, serverManager) =>
              serverManager ?? ServerManager(visitorTracker)..init(prefsService),
        ),
      ],
      child: const DTechApp(),
    ),
  );
}

class DTechApp extends StatelessWidget {
  const DTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DTech',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0), // Deep Blue
          brightness: Brightness.dark,
          secondary: const Color(0xFF00BCD4), // Cyan
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
