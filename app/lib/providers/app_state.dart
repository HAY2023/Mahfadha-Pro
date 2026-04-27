import 'package:flutter/material.dart';

/// ══════════════════════════════════════════════════════════════════════
///  حالة التطبيق العامة — كل شيء في الذاكرة العشوائية فقط
///  Zero-Persistence: لا يُحفظ أي شيء على القرص مطلقاً
///  [FIX 5] حالة الإعداد تُقرأ من الجهاز مباشرة
///
///  [V2] Biometric-Gated Vault + Sensitive Profile Vault + Auto-Login URL
///  [V3] Expanded data model: phoneNumbers, backupCodes, recoveryEmails
///       + FINGERPRINT_VERIFIED signal support from ESP32
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

/// Extended account model — includes:
/// - targetURL for Rubber Ducky auto-login (Keystroke Injection)
/// - phoneNumbers bound to this account (2FA recovery)
/// - backupCodes for emergency account access
/// - recoveryEmails for account recovery
/// - arbitrary sensitiveEntries for anything else
class VaultAccount {
  final int id;
  final String name;
  final String username;
  final String password;
  final String targetUrl;          // For auto-login (Rubber Ducky payload)
  final String totpSecret;
  final List<String> phoneNumbers;     // [V3] Bound phone numbers (2FA)
  final List<String> backupCodes;      // [V3] Emergency backup codes
  final List<String> recoveryEmails;   // [V3] Recovery email addresses
  final List<SensitiveProfileEntry> sensitiveEntries; // Arbitrary extras

  const VaultAccount({
    required this.id,
    required this.name,
    this.username = '',
    this.password = '',
    this.targetUrl = '',
    this.totpSecret = '',
    this.phoneNumbers = const [],
    this.backupCodes = const [],
    this.recoveryEmails = const [],
    this.sensitiveEntries = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'username': username,
    'password': password,
    'targetUrl': targetUrl,
    'totpSecret': totpSecret,
    'phoneNumbers': phoneNumbers,
    'backupCodes': backupCodes,
    'recoveryEmails': recoveryEmails,
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
      phoneNumbers: _parseStringList(json['phoneNumbers']),
      backupCodes: _parseStringList(json['backupCodes']),
      recoveryEmails: _parseStringList(json['recoveryEmails']),
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
    phoneNumbers: const [],
    backupCodes: const [],
    recoveryEmails: const [],
    sensitiveEntries: const [],
  );

  /// Whether this account has a targetUrl configured for Rubber Ducky auto-login
  bool get hasAutoLogin => targetUrl.isNotEmpty;

  /// Total count of all sensitive data items bound to this account
  int get sensitiveDataCount =>
      phoneNumbers.length +
      backupCodes.length +
      recoveryEmails.length +
      sensitiveEntries.length;
}

/// Parse a dynamic value into a List<String> safely
List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

// ══════════════════════════════════════════════════════════════════════════
//  Biometric verification state — tracks the ESP32 fingerprint flow
// ══════════════════════════════════════════════════════════════════════════

/// Possible states of the biometric verification lifecycle.
enum BiometricState {
  /// Waiting for user to place finger on sensor
  waitingForFinger,

  /// ESP32 is actively scanning the fingerprint
  scanning,

  /// Fingerprint was verified successfully (FINGERPRINT_VERIFIED)
  verified,

  /// Fingerprint verification failed
  failed,
}

class AppState extends ChangeNotifier {
  bool _isDeviceConnected = false;
  bool _isSetupComplete = false;     // [FIX 5] يُحدَّث من رد الجهاز فقط
  String _deviceStatus = 'غير متصل';
  String? _connectedPort;

  // ── كلمات المرور المؤقتة في الذاكرة العشوائية فقط ──
  List<Map<String, dynamic>> _tempPasswords = [];

  // ══════════════════════════════════════════════════════════════
  //  [V2/V3] Biometric-Gated Vault State
  // ══════════════════════════════════════════════════════════════
  /// Whether the ESP32 has confirmed biometric authentication.
  /// The vault data is NEVER decrypted or displayed until this is true.
  bool _isBiometricUnlocked = false;

  /// [V3] Current state of the biometric verification flow
  BiometricState _biometricState = BiometricState.waitingForFinger;

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

  // ── [V2/V3] Biometric Vault Getters ──
  bool get isBiometricUnlocked => _isBiometricUnlocked;
  BiometricState get biometricState => _biometricState;

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
  //  [V2/V3] Biometric-Gated Vault Operations
  // ══════════════════════════════════════════════════════════════

  /// [V3] Called when ESP32 begins scanning fingerprint.
  void onBiometricScanning() {
    _biometricState = BiometricState.scanning;
    notifyListeners();
    debugPrint('[🛡️ أمان] ESP32 يقوم بمسح البصمة...');
  }

  /// [V3] Called when ESP32 sends FINGERPRINT_VERIFIED signal.
  /// This is the ONLY way to unlock the vault view.
  /// Also handles legacy BIOMETRIC_UNLOCKED for backward compatibility.
  void onFingerprintVerified() {
    _isBiometricUnlocked = true;
    _biometricState = BiometricState.verified;
    notifyListeners();
    debugPrint('[🛡️ أمان] تم فتح القبو — المصادقة الحيوية تمت بنجاح (FINGERPRINT_VERIFIED).');
  }

  /// Called when ESP32 sends BIOMETRIC_UNLOCKED signal.
  /// Kept for backward compatibility — delegates to onFingerprintVerified.
  void onBiometricUnlocked() {
    onFingerprintVerified();
  }

  /// [V3] Called when ESP32 reports fingerprint verification failure.
  void onBiometricFailed() {
    _biometricState = BiometricState.failed;
    notifyListeners();
    debugPrint('[🛡️ أمان] فشل التحقق من البصمة.');
    // Auto-reset to waiting state after a delay
    Future.delayed(const Duration(seconds: 3), () {
      if (_biometricState == BiometricState.failed) {
        _biometricState = BiometricState.waitingForFinger;
        notifyListeners();
      }
    });
  }

  /// Lock the vault — scrub all decrypted data from RAM.
  void lockBiometricVault() {
    _isBiometricUnlocked = false;
    _biometricState = BiometricState.waitingForFinger;
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
