import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/app_state.dart';
import 'hardware_service.dart';
import 'websocket_server_service.dart';
import 'websocket_vault_service.dart';

/// Centralizes all business logic and system interactions.
class TaskManager {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();

  HardwareService? _hardwareService;
  final WebSocketServerService _wsServer = WebSocketServerService();
  final WebsocketVaultService _vaultWsServer = WebsocketVaultService();
  Timer? _telemetryTimer;

  bool _isQuitting = false;

  Future<void> initialize(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Setup WebSocket for Auto-Save Interceptor
    _wsServer.onCredentialIntercepted = (url, username, password) {
      final credential = InterceptedCredential(
        targetUrl: url,
        username: username,
        password: password,
        interceptedAt: DateTime.now(),
      );
      appState.setPendingCredential(credential);
      restorePrimaryWindow();
    };
    await _wsServer.start();
    await _vaultWsServer.start();
    
    // Watch for device connection
    appState.addListener(() {
      final portName = appState.connectedPort;
      if (portName != null && (_hardwareService == null || _hardwareService!.portName != portName)) {
        _connectHardware(portName, appState);
      }
    });
  }

  void _connectHardware(String portName, AppState appState) {
    _hardwareService?.dispose();
    _hardwareService = HardwareService(portName: portName);

    _hardwareService!.onStatus.listen((status) {
      if (status == 'connected') {
        appState.updateStatus('متصل عبر $portName — بانتظار المصادقة الحيوية');
        // Request Firmware version
        _hardwareService!.sendCommand({'cmd': 'GET_VER'});
      } else {
        appState.updateStatus(status);
      }
    });

    _hardwareService!.onData.listen((json) {
      if (json['status'] == 'telemetry') {
        final dataStr = json['data']?.toString() ?? '';
        appState.processTelemetry(dataStr);
        _checkThermalState(appState);
      } else if (json['status'] == 'event') {
        final eventMessage = json['message']?.toString() ?? '';
        switch (eventMessage) {
          case 'FINGERPRINT_VERIFIED':
            appState.updateStatus('تمت المصادقة الحيوية بنجاح ✓');
            appState.onFingerprintVerified();
            break;
          case 'BIOMETRIC_UNLOCKED':
            appState.updateStatus('تمت المصادقة الحيوية بنجاح');
            appState.onBiometricUnlocked();
            break;
          case 'FINGERPRINT_SCANNING':
            appState.updateStatus('جارٍ مسح البصمة...');
            appState.onBiometricScanning();
            break;
          case 'FINGERPRINT_FAILED':
            appState.updateStatus('فشل التحقق من البصمة');
            appState.onBiometricFailed();
            break;
          case 'BIOMETRIC_LOCKED':
            appState.updateStatus('وحدة التشفير متصلة وتنتظر التحقق الحيوي');
            appState.lockBiometricVault();
            break;
        }
      } else if (json.containsKey('FW')) {
        // e.g. FW:1.0.0
        appState.setFirmwareVersion(json['FW'].toString());
      } else if (json.containsKey('INJECT')) {
        final accountName = json['INJECT'].toString();
        // Search for account in appState
        try {
          final account = appState.vaultAccounts.firstWhere(
            (acc) => acc.name.toLowerCase() == accountName.toLowerCase()
          );
          _vaultWsServer.sendCredentialsToBrowser(account.username, account.password);
          appState.addAuditLog('Injected credentials for: $accountName');
        } catch (_) {
          appState.addAuditLog('Inject failed: Account "$accountName" not found in vault.');
        }
      }
    });

    _hardwareService!.connect();

    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _hardwareService?.sendCommand({'cmd': 'get_telemetry'});
    });
  }

  void _checkThermalState(AppState state) {
    if (state.isThermalEmergency) {
      _telemetryTimer?.cancel();
      _hardwareService?.sendCommand({'cmd': 'SHUTDOWN'});
      
      Future.delayed(const Duration(seconds: 4), () {
        _hardwareService?.dispose();
        state.fullReset();
      });
    }
  }
  
  void sendHardwareCommand(Map<String, dynamic> cmd) {
    _hardwareService?.sendCommand(cmd);
  }

  Future<void> restorePrimaryWindow() async {
    await windowManager.setSkipTaskbar(false);
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideToSystemTray() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> quitApplication() async {
    if (_isQuitting) return;
    _isQuitting = true;
    _telemetryTimer?.cancel();
    _hardwareService?.dispose();
    await _wsServer.stop();
    await _vaultWsServer.stop();
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }
}
