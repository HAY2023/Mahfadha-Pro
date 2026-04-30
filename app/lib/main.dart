import 'dart:async';
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
import 'screens/phone_vault_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_wizard.dart';
import 'screens/update_center.dart';
import 'screens/vault_screen.dart';
import 'services/task_manager.dart';
import 'services/github_updater_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'theme/mars_theme.dart';
import 'widgets/app_title_bar.dart';
import 'widgets/auto_lock_wrapper.dart';
import 'widgets/auto_save_dialog.dart';
import 'widgets/liquid_background.dart';
import 'widgets/sidebar.dart';

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

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await WindowsSingleInstance.ensureSingleInstance(
    args,
    'mahfadha_pro_windows_desktop',
    onSecondWindow: (_) async {
      await TaskManager().restorePrimaryWindow();
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

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle('Mahfadha Pro');
    try {
      await windowManager.setIcon(_resolveDesktopAssetPath(_trayIconIcoPath));
    } catch (_) {}
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const CipherVaultApp(),
    ),
  );
}

class CipherVaultApp extends StatefulWidget {
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  const CipherVaultApp({super.key});

  @override
  State<CipherVaultApp> createState() => _CipherVaultAppState();
}

class _CipherVaultAppState extends State<CipherVaultApp>
    with WindowListener, TrayListener {

  @override
  void initState() {
    super.initState();
    _initializeDesktopShell();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final packageInfo = await PackageInfo.fromPlatform();
      context.read<AppState>().setAppVersion('v${packageInfo.version}');
      TaskManager().initialize(context);
      _checkForUpdates(packageInfo.version);
    });
  }

  Future<void> _checkForUpdates(String currentVersion) async {
    try {
      final updater = GitHubUpdaterService(owner: 'HAY2023');
      final latest = await updater.fetchLatestRelease();
      final latestVer = latest.tagName.replaceAll('v', '');
      
      if (latestVer.compareTo(currentVersion) > 0) {
        if (!mounted) return;
        CipherVaultApp.scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.new_releases, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'تحديث جديد متاح (${latest.tagName})! تحقق من مركز التحديثات.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: MarsTheme.cyanNeon.withOpacity(0.9),
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (_) {
      // Ignore update check errors in background
    }
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

  @override
  void onWindowClose() async {
    await TaskManager().hideToSystemTray();
  }

  @override
  void onTrayIconMouseDown() async {
    await TaskManager().restorePrimaryWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open_app':
        await TaskManager().restorePrimaryWindow();
        break;
      case 'quit_app':
        await TaskManager().quitApplication();
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
      scaffoldMessengerKey: CipherVaultApp.scaffoldMessengerKey,
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
        '/dashboard': (context) => const _DashboardShell(),
        '/setup': (context) => const _AppShell(child: SetupWizard()),
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
      body: Stack(
        children: [
          Column(
            children: [
              const AppTitleBar(),
              Expanded(child: child),
            ],
          ),
          const _AutoSaveOverlay(),
        ],
      ),
    );
  }
}

class _DashboardShell extends StatelessWidget {
  const _DashboardShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarsTheme.spaceNavy,
      body: Stack(
        children: [
          Column(
            children: [
              const AppTitleBar(),
              Expanded(
                child: LiquidBackground(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(
                      children: [
                        const AppSidebar(),
                        Expanded(
                          child: AutoLockWrapper(
                            timeout: const Duration(seconds: 180),
                            child: Consumer<AppState>(
                              builder: (context, state, _) {
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: _buildPageContent(state.currentPage),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const _AutoSaveOverlay(),
        ],
      ),
    );
  }

  Widget _buildPageContent(SidebarPage page) {
    switch (page) {
      case SidebarPage.home:
        return const DashboardScreen(key: ValueKey('home'));
      case SidebarPage.accounts:
        return const VaultScreen(key: ValueKey('accounts'));
      case SidebarPage.phones:
        return const PhoneVaultScreen(key: ValueKey('phones'));
      case SidebarPage.updates:
        return const UpdateCenterScreen(key: ValueKey('updates'));
      case SidebarPage.settings:
        return const SettingsScreen(key: ValueKey('settings'));
    }
  }
}

class _AutoSaveOverlay extends StatelessWidget {
  const _AutoSaveOverlay();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final credential = state.pendingCredential;
        if (credential == null) return const SizedBox.shrink();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.pendingCredential != null) {
            AutoSaveDialog.show(
              context,
              credential: credential,
              onSave: () {
                final newAccount = VaultAccount(
                  id: state.vaultAccounts.length,
                  name: _extractDomain(credential.targetUrl),
                  username: credential.username,
                  password: credential.password,
                  targetUrl: credential.targetUrl,
                );
                state.addVaultAccount(newAccount);
                state.clearPendingCredential();
                Navigator.of(context, rootNavigator: true).pop();
                
                CipherVaultApp.scaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text('تم تشفير وحفظ حساب ${newAccount.name} بنجاح!'),
                    backgroundColor: MarsTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              onDismiss: () {
                state.clearPendingCredential();
                Navigator.of(context, rootNavigator: true).pop();
              },
            );
          }
        });

        return const SizedBox.shrink();
      },
    );
  }

  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }
}
