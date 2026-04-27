import 'package:flutter/material.dart';

/// Global application state using Provider.
/// Zero-persistence: nothing is saved to disk. All state is volatile.
class AppState extends ChangeNotifier {
  bool _isFirstLaunch = true;
  bool _isDeviceConnected = false;
  String _deviceStatus = 'Disconnected';

  // ── كلمات المرور المؤقتة في الذاكرة العشوائية فقط ──
  List<Map<String, dynamic>> _tempPasswords = [];

  bool get isFirstLaunch => _isFirstLaunch;
  bool get isDeviceConnected => _isDeviceConnected;
  String get deviceStatus => _deviceStatus;
  List<Map<String, dynamic>> get tempPasswords =>
      List.unmodifiable(_tempPasswords);

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

  /// حفظ كلمات المرور مؤقتاً في RAM فقط
  void setTempPasswords(List<Map<String, dynamic>> passwords) {
    _tempPasswords = List.from(passwords);
    notifyListeners();
  }

  /// مسح كامل لكلمات المرور من الذاكرة — الكتابة فوق ثم المسح
  void clearPasswords() {
    for (var entry in _tempPasswords) {
      entry.updateAll((key, value) => '');
    }
    _tempPasswords.clear();
    notifyListeners();
    debugPrint('[🛡️ SECURITY] Password list purged from RAM.');
  }
}
