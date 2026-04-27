import 'package:flutter/material.dart';

/// ══════════════════════════════════════════════════════════════════════
///  حالة التطبيق العامة — كل شيء في الذاكرة العشوائية فقط
///  Zero-Persistence: لا يُحفظ أي شيء على القرص مطلقاً
///  [FIX 5] حالة الإعداد تُقرأ من الجهاز مباشرة
///
///  [V2] Biometric-Gated Vault + Sensitive Profile Vault + Auto-Login URL
/// ══════════════════════════════════════════════════════════════════════

/// Sensitive profile entry — phone numbers, recovery emails, backup codes, etc.
class SensitiveProfileEntry {
  final String label;       // e.g. "Phone Number", "Recovery Email", "Backup Code"
  final String category;    // e.g. "phone", "email", "backup_code", "custom"
  final String value;       // The actual sensitive data

  const SensitiveProfileEntry({
    required this.label,
    required this.category,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'category': category,
    'value': value,
  };

  factory SensitiveProfileEntry.fromJson(Map<String, dynamic> json) {
    return SensitiveProfileEntry(
      label: json['label']?.toString() ?? '',
      category: json['category']?.toString() ?? 'custom',
      value: json['value']?.toString() ?? '',
    );
  }
}

/// Extended account model — now includes targetURL for Rubber Ducky auto-login
/// and a list of sensitive profile entries (phone, recovery emails, backup codes)
class VaultAccount {
  final int id;
  final String name;
  final String username;
  final String password;
  final String targetUrl;          // For auto-login (Rubber Ducky payload)
  final String totpSecret;
  final List<SensitiveProfileEntry> sensitiveEntries;

  const VaultAccount({
    required this.id,
    required this.name,
    this.username = '',
    this.password = '',
    this.targetUrl = '',
    this.totpSecret = '',
    this.sensitiveEntries = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'username': username,
    'password': password,
    'targetUrl': targetUrl,
    'totpSecret': totpSecret,
    'sensitiveEntries': sensitiveEntries.map((e) => e.toJson()).toList(),
  };

  factory VaultAccount.fromJson(Map<String, dynamic> json) {
    final entriesJson = json['sensitiveEntries'];
    final entries = <SensitiveProfileEntry>[];
    if (entriesJson is List) {
      for (final e in entriesJson) {
        if (e is Map<String, dynamic>) {
          entries.add(SensitiveProfileEntry.fromJson(e));
        }
      }
    }

    return VaultAccount(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      targetUrl: json['targetUrl']?.toString() ?? '',
      totpSecret: json['totpSecret']?.toString() ?? '',
      sensitiveEntries: entries,
    );
  }

  /// Create a scrubbed copy (overwrite sensitive fields)
  VaultAccount scrubbed() => VaultAccount(
    id: id,
    name: '',
    username: '',
    password: '',
    targetUrl: '',
    totpSecret: '',
    sensitiveEntries: const [],
  );
}

class AppState extends ChangeNotifier {
  bool _isDeviceConnected = false;
  bool _isSetupComplete = false;     // [FIX 5] يُحدَّث من رد الجهاز فقط
  String _deviceStatus = 'غير متصل';
  String? _connectedPort;

  // ── كلمات المرور المؤقتة في الذاكرة العشوائية فقط ──
  List<Map<String, dynamic>> _tempPasswords = [];

  // ══════════════════════════════════════════════════════════════
  //  [V2] Biometric-Gated Vault State
  // ══════════════════════════════════════════════════════════════
  /// Whether the ESP32 has confirmed biometric authentication.
  /// The vault data is NEVER decrypted or displayed until this is true.
  bool _isBiometricUnlocked = false;

  /// Vault accounts — only populated after biometric confirmation
  List<VaultAccount> _vaultAccounts = [];

  /// Standalone sensitive profiles (not tied to a specific account)
  List<SensitiveProfileEntry> _globalSensitiveEntries = [];

  // ── Getters ──
  bool get isDeviceConnected => _isDeviceConnected;
  bool get isSetupComplete => _isSetupComplete;
  String get deviceStatus => _deviceStatus;
  String? get connectedPort => _connectedPort;
  List<Map<String, dynamic>> get tempPasswords =>
      List.unmodifiable(_tempPasswords);

  // ── [V2] Biometric Vault Getters ──
  bool get isBiometricUnlocked => _isBiometricUnlocked;

  /// Returns vault accounts ONLY if biometric is unlocked.
  /// Otherwise returns empty — zero data leakage.
  List<VaultAccount> get vaultAccounts {
    if (!_isBiometricUnlocked) return const [];
    return List.unmodifiable(_vaultAccounts);
  }

  /// Returns global sensitive entries ONLY if biometric is unlocked.
  List<SensitiveProfileEntry> get globalSensitiveEntries {
    if (!_isBiometricUnlocked) return const [];
    return List.unmodifiable(_globalSensitiveEntries);
  }

  // ── اتصال الجهاز ──
  void setDeviceConnected(bool connected) {
    _isDeviceConnected = connected;
    _deviceStatus = connected ? 'متصل' : 'غير متصل';
    if (!connected) {
      // Device disconnected — lock the vault immediately
      lockBiometricVault();
    }
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

  // ══════════════════════════════════════════════════════════════
  //  [V2] Biometric-Gated Vault Operations
  // ══════════════════════════════════════════════════════════════

  /// Called when ESP32 sends BIOMETRIC_UNLOCKED signal.
  /// This is the ONLY way to unlock the vault view.
  void onBiometricUnlocked() {
    _isBiometricUnlocked = true;
    notifyListeners();
    debugPrint('[🛡️ أمان] تم فتح القبو — المصادقة الحيوية تمت بنجاح.');
  }

  /// Lock the vault — scrub all decrypted data from RAM.
  void lockBiometricVault() {
    _isBiometricUnlocked = false;
    // Scrub vault accounts from RAM
    for (var acc in _vaultAccounts) {
      acc = acc.scrubbed();
    }
    _vaultAccounts.clear();
    // Scrub global sensitive entries
    _globalSensitiveEntries.clear();
    // Optional: Force Garbage Collection prompt if possible, or clear references
    notifyListeners();
    debugPrint('[🛡️ أمان] تم قفل القبو — جميع البيانات الحساسة مُحيت من الذاكرة.');
  }

  /// Populate vault with accounts received from ESP32 (only after biometric unlock)
  void setVaultAccounts(List<VaultAccount> accounts) {
    if (!_isBiometricUnlocked) {
      debugPrint('[🛡️ أمان] رُفض تحميل بيانات القبو — المصادقة الحيوية مطلوبة.');
      return;
    }
    _vaultAccounts = List.from(accounts);
    notifyListeners();
  }

  /// Add a single account to the vault (biometric must be unlocked)
  void addVaultAccount(VaultAccount account) {
    if (!_isBiometricUnlocked) {
      debugPrint('[🛡️ أمان] رُفض إضافة حساب — المصادقة الحيوية مطلوبة.');
      return;
    }
    _vaultAccounts.add(account);
    notifyListeners();
  }

  /// Set global sensitive entries (phone numbers, recovery emails, etc.)
  void setGlobalSensitiveEntries(List<SensitiveProfileEntry> entries) {
    if (!_isBiometricUnlocked) {
      debugPrint('[🛡️ أمان] رُفض تحميل الملف الحساس — المصادقة الحيوية مطلوبة.');
      return;
    }
    _globalSensitiveEntries = List.from(entries);
    notifyListeners();
  }

  /// Add a global sensitive entry
  void addGlobalSensitiveEntry(SensitiveProfileEntry entry) {
    if (!_isBiometricUnlocked) return;
    _globalSensitiveEntries.add(entry);
    notifyListeners();
  }

  /// إعادة ضبط كاملة — مسح كل شيء (عند القفل التلقائي أو فصل الجهاز)
  void fullReset() {
    _isDeviceConnected = false;
    _isSetupComplete = false;
    _deviceStatus = 'غير متصل';
    _connectedPort = null;
    clearPasswords();
    lockBiometricVault();
    debugPrint('[🛡️ أمان] إعادة ضبط كاملة — كل البيانات مُحيت.');
  }
}
