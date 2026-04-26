import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme/mars_theme.dart';
import 'providers/app_state.dart';
import 'screens/setup_wizard.dart';
import 'screens/dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Configure Desktop Window ──────────────────────────────────────
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1100, 750),
    minimumSize: Size(900, 650),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Mahfadha Pro — Cyber Vault',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MahfadhaApp(),
    ),
  );
}

class MahfadhaApp extends StatelessWidget {
  const MahfadhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mahfadha Pro',
      theme: MarsTheme.darkTheme,
      home: Consumer<AppState>(
        builder: (context, appState, _) {
          if (appState.isFirstLaunch) {
            return const SetupWizard();
          }
          return const DashboardScreen();
        },
      ),
    );
  }
}
