import 'dart:async';
import 'dart:convert';
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
    title: 'CipherVault Pro',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle('CipherVault Pro');
    await windowManager.setIcon(_resolveDesktopAssetPath(_trayIconIcoPath));
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
  const CipherVaultApp({super.key});

  @override
  State<CipherVaultApp> createState() => _CipherVaultAppState();
}

class _CipherVaultAppState extends State<CipherVaultApp>
    with WindowListener, TrayListener {
  bool _isQuitting = false;

  // ── [V4] Auto-Save Interceptor — local socket listener ──
  ServerSocket? _autoSaveServer;

  @override
  void initState() {
    super.initState();
    _initializeDesktopShell();
    _startAutoSaveListener();
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
        MenuItem(key: 'open_app', label: 'فتح CipherVault Pro'),
        MenuItem.separator(),
        MenuItem(key: 'quit_app', label: 'إغلاق نهائي'),
      ],
    );

    await trayManager.setIcon(
      _resolveDesktopAssetPath(
        Platform.isWindows ? _trayIconIcoPath : _trayIconPngPath,
      ),
    );
    await trayManager.setToolTip('CipherVault Pro');
    await trayManager.setContextMenu(menu);
  }

  // ══════════════════════════════════════════════════════════════
  //  [V4] Auto-Save Interceptor — Background Socket Listener
  //  Listens on localhost:9847 for JSON credential payloads from
  //  the Chrome extension's Native Messaging bridge.
  // ══════════════════════════════════════════════════════════════

  Future<void> _startAutoSaveListener() async {
    try {
      _autoSaveServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        9847,
        shared: true,
      );
      debugPrint(
          '[🔌 Auto-Save] Listening on localhost:9847 for credential intercepts.');

      _autoSaveServer!.listen(
        (socket) {
          socket.listen((data) {
            try {
              final payload = utf8.decode(data).trim();
              if (payload.isEmpty) return;

              final json = jsonDecode(payload) as Map<String, dynamic>;
              final url = json['url']?.toString() ?? '';
              final username = json['username']?.toString() ?? '';
              final password = json['password']?.toString() ?? '';

              if (url.isNotEmpty && username.isNotEmpty && password.isNotEmpty) {
                final credential = InterceptedCredential(
                  targetUrl: url,
                  username: username,
                  password: password,
                  interceptedAt: DateTime.now(),
                );

                // Push to AppState for the dialog to pick up
                final appState =
                    Provider.of<AppState>(context, listen: false);
                appState.setPendingCredential(credential);

                // Restore the window so the user sees the dialog
                _restorePrimaryWindow();

                debugPrint(
                    '[🔌 Auto-Save] Intercepted credential for: $url');
              }

              socket.write('{"status":"received"}');
              socket.close();
            } catch (e) {
              debugPrint('[🔌 Auto-Save] Parse error: $e');
              socket.close();
            }
          });
        },
        onError: (e) => debugPrint('[🔌 Auto-Save] Socket error: $e'),
      );
    } catch (e) {
      debugPrint('[🔌 Auto-Save] Failed to start listener: $e');
    }
  }

  Future<void> _hideToBackground() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _quitApplication() async {
    if (_isQuitting) return;
    _isQuitting = true;
    _autoSaveServer?.close();
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
    _autoSaveServer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CipherVault Pro',
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

// ══════════════════════════════════════════════════════════════════════════
//  _AppShell — Simple shell for non-dashboard routes (connection gate, etc.)
// ══════════════════════════════════════════════════════════════════════════
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
          // ── Auto-Save Dialog Overlay ──
          const _AutoSaveOverlay(),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _DashboardShell — Main app with sidebar + liquid background + content
// ══════════════════════════════════════════════════════════════════════════
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
              // ── Title bar at absolute top ──
              const AppTitleBar(),

              // ── Main content area: Sidebar + Content ──
              Expanded(
                child: LiquidBackground(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(
                      children: [
                        // ── Sidebar ──
                        const AppSidebar(),

                        // ── Content area ──
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
          // ── Auto-Save Dialog Overlay ──
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

// ══════════════════════════════════════════════════════════════════════════
//  _AutoSaveOverlay — Watches for pending credentials and shows dialog
//  Overlays on top of all content including from system tray popup.
// ══════════════════════════════════════════════════════════════════════════
class _AutoSaveOverlay extends StatelessWidget {
  const _AutoSaveOverlay();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final credential = state.pendingCredential;
        if (credential == null) return const SizedBox.shrink();

        // Show dialog as soon as credential is available
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.pendingCredential != null) {
            AutoSaveDialog.show(
              context,
              credential: credential,
              onSave: () {
                // Send to ESP32 for encryption and NVS storage
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
                debugPrint(
                    '[🔌 Auto-Save] Credential saved for: ${credential.targetUrl}');
              },
              onDismiss: () {
                state.clearPendingCredential();
                Navigator.of(context, rootNavigator: true).pop();
                debugPrint('[🔌 Auto-Save] Credential dismissed.');
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
