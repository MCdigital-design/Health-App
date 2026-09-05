import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'polar/polar_repository.dart';
import 'screens/live_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/ai_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  runApp(const VerityDashboardApp());
}

class VerityDashboardApp extends StatelessWidget {
  const VerityDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => PolarRepository(),
      dispose: (_, repo) => repo.dispose(),
      child: MaterialApp(
        title: 'Verity Dashboard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C5CE7),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F111A),
          cardTheme: CardThemeData(
            color: const Color(0xFF1A1D2E),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    LiveScreen(),
    RecordingsScreen(),
    DashboardScreen(),
    AiScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Covers the "app restart with a sensor already known" case: if Auto
    // Reconnect is on and we have a remembered device, try it once the
    // widget tree (and the repository's prefs load) is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PolarRepository>().tryAutoReconnectOnLaunch();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can throttle or drop BLE GATT callbacks while backgrounded or
    // the screen is locked. Rather than hoping the stream silently recovers
    // on its own, proactively re-check and restart on resume so returning
    // to the app shows live data immediately instead of a stale chart.
    final repo = context.read<PolarRepository>();
    if (state == AppLifecycleState.resumed) {
      repo.onAppResumed();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      repo.onAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.favorite), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.folder), label: 'Recordings'),
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
