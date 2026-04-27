import 'dart:io';

import 'package:flutter/material.dart' hide MenuItem;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'providers/app_state.dart';
import 'screens/connection_gate.dart';
import 'screens/dashboard.dart';
import 'screens/setup_wizard.dart';
import 'screens/update_center.dart';
import 'screens/vault_screen.dart';
import 'theme/mars_theme.dart';
import 'widgets/app_title_bar.dart';
import 'widgets/auto_lock_wrapper.dart';

const String _trayIconIcoPath = 'assets/tray/mahfadha_pro_tray.ico';
const String _trayIconPngPath = 'assets/tray/mahfadha_pro_tray.png';

String _resolveDesktopAssetPath(String relativePath) {
  final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
  final localCandidate =
      '${Directory.current.path}${Platform.pathSeparator}$normalized';
  if (File(localCandidate).existsSync()) {
    return localCandidate;
  }

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final bundledCandidate =
      '$executableDir${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}$normalized';
  return bundledCandidate;
}

Future<void> _restorePrimaryWindow() async {
  await windowManager.setSkipTaskbar(false);
  if (await windowManager.isMinimized()) {
    await windowManager.restore();
  }
  await windowManager.show();
  await windowManager.focus();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await WindowsSingleInstance.ensureSingleInstance(
    args,
    'mahfadha_pro_windows_desktop',
    onSecondWindow: (_) async {
      await _restorePrimaryWindow();
    },
  );

  const windowOptions = WindowOptions(
    size: Size(1180, 780),
    minimumSize: Size(980, 680),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Mahfadha Pro',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle('Mahfadha Pro');
    await windowManager.setIcon(_resolveDesktopAssetPath(_trayIconIcoPath));
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

class MahfadhaApp extends StatefulWidget {
  const MahfadhaApp({super.key});

  @override
  State<MahfadhaApp> createState() => _MahfadhaAppState();
}

class _MahfadhaAppState extends State<MahfadhaApp>
    with WindowListener, TrayListener {
  bool _isQuitting = false;

  @override
  void initState() {
    super.initState();
    _initializeDesktopShell();
  }

  Future<void> _initializeDesktopShell() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _configureTray();
  }

  Future<void> _configureTray() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'open_app', label: 'فتح Mahfadha Pro'),
        MenuItem.separator(),
        MenuItem(key: 'quit_app', label: 'إغلاق نهائي'),
      ],
    );

    await trayManager.setIcon(
      _resolveDesktopAssetPath(
        Platform.isWindows ? _trayIconIcoPath : _trayIconPngPath,
      ),
    );
    await trayManager.setToolTip('Mahfadha Pro');
    await trayManager.setContextMenu(menu);
  }

  Future<void> _hideToBackground() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _quitApplication() async {
    if (_isQuitting) return;
    _isQuitting = true;
    await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    if (_isQuitting) return;
    await _hideToBackground();
  }

  @override
  void onTrayIconMouseDown() async {
    await _restorePrimaryWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open_app':
        await _restorePrimaryWindow();
        break;
      case 'quit_app':
        await _quitApplication();
        break;
    }
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mahfadha Pro',
      theme: MarsTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'AE'),
      ],
      locale: const Locale('ar', 'AE'),
      initialRoute: '/',
      routes: {
        '/': (context) => const _AppShell(child: ConnectionGateScreen()),
        '/dashboard': (context) => const _AppShell(
              child: AutoLockWrapper(
                timeout: Duration(seconds: 180),
                child: DashboardScreen(),
              ),
            ),
        '/setup': (context) => const _AppShell(child: SetupWizard()),
        '/updates': (context) => const _AppShell(
              child: AutoLockWrapper(
                timeout: Duration(seconds: 180),
                child: UpdateCenterScreen(),
              ),
            ),
        '/vault': (context) => const _AppShell(
              child: AutoLockWrapper(
                timeout: Duration(seconds: 180),
                child: VaultScreen(),
              ),
            ),
      },
    );
  }
}

class _AppShell extends StatelessWidget {
  final Widget child;

  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarsTheme.spaceNavy,
      body: Column(
        children: [
          const AppTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
