import 'package:flutter/material.dart';

/// ══════════════════════════════════════════════════════════════════════
///  حالة التطبيق العامة — كل شيء في الذاكرة العشوائية فقط
///  Zero-Persistence: لا يُحفظ أي شيء على القرص مطلقاً
///  [FIX 5] حالة الإعداد تُقرأ من الجهاز مباشرة
/// ══════════════════════════════════════════════════════════════════════
class AppState extends ChangeNotifier {
  bool _isDeviceConnected = false;
  bool _isSetupComplete = false;     // [FIX 5] يُحدَّث من رد الجهاز فقط
  String _deviceStatus = 'غير متصل';
  String? _connectedPort;

  // ── كلمات المرور المؤقتة في الذاكرة العشوائية فقط ──
  List<Map<String, dynamic>> _tempPasswords = [];

  // ── Getters ──
  bool get isDeviceConnected => _isDeviceConnected;
  bool get isSetupComplete => _isSetupComplete;
  String get deviceStatus => _deviceStatus;
  String? get connectedPort => _connectedPort;
  List<Map<String, dynamic>> get tempPasswords =>
      List.unmodifiable(_tempPasswords);

  // ── اتصال الجهاز ──
  void setDeviceConnected(bool connected) {
    _isDeviceConnected = connected;
    _deviceStatus = connected ? 'متصل' : 'غير متصل';
    notifyListeners();
  }

  void setConnectedPort(String? port) {
    _connectedPort = port;
    notifyListeners();
  }

  void updateStatus(String status) {
    _deviceStatus = status;
    notifyListeners();
  }

  /// [FIX 5] تحديث حالة الإعداد من رد الجهاز — وليس تخميناً
  void markSetupComplete() {
    _isSetupComplete = true;
    notifyListeners();
  }

  void markSetupNeeded() {
    _isSetupComplete = false;
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
    debugPrint('[🛡️ أمان] تم مسح كلمات المرور من الذاكرة.');
  }

  /// إعادة ضبط كاملة — مسح كل شيء (عند القفل التلقائي أو فصل الجهاز)
  void fullReset() {
    _isDeviceConnected = false;
    _isSetupComplete = false;
    _deviceStatus = 'غير متصل';
    _connectedPort = null;
    clearPasswords();
    debugPrint('[🛡️ أمان] إعادة ضبط كاملة — كل البيانات مُحيت.');
  }
}
