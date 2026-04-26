import 'package:flutter/material.dart';

/// Global application state using Provider.
/// Zero-persistence: nothing is saved to disk. All state is volatile.
class AppState extends ChangeNotifier {
  bool _isFirstLaunch = true;
  bool _isDeviceConnected = false;
  String _deviceStatus = 'Disconnected';

  bool get isFirstLaunch => _isFirstLaunch;
  bool get isDeviceConnected => _isDeviceConnected;
  String get deviceStatus => _deviceStatus;

  void completeSetup() {
    _isFirstLaunch = false;
    notifyListeners();
  }

  void setDeviceConnected(bool connected) {
    _isDeviceConnected = connected;
    _deviceStatus = connected ? 'Connected' : 'Disconnected';
    notifyListeners();
  }

  void updateStatus(String status) {
    _deviceStatus = status;
    notifyListeners();
  }
}
