import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/server_manager.dart';
import 'core/visitor_tracker.dart';
import 'features/dashboard/dashboard_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VisitorTracker()),
        ChangeNotifierProxyProvider<VisitorTracker, ServerManager>(
          create: (context) => ServerManager(context.read<VisitorTracker>()),
          update: (_, visitorTracker, serverManager) =>
              serverManager ?? ServerManager(visitorTracker),
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
