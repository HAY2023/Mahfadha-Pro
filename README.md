# 🛡️ Mahfadha Pro

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg)
![Version](https://img.shields.io/badge/Version-1.0.2-orange.svg)

**Mahfadha Pro** — مدير كلمات مرور مادي متقدم بتشفير عسكري وحماية حيوية. يعمل دون اتصال بالإنترنت نهائياً.

---

## 📋 متغيرات الإصدار (للنسخ السريع)

عند إصدار نسخة جديدة، قم بتحديث هذه القيم في جميع الملفات:

```yaml
# app/pubspec.yaml
version: 1.0.2
```

```dart
// app/lib/screens/update_center.dart
static const String _currentDesktopVersion = '1.0.2';
```

```dart
// app/lib/screens/settings_screen.dart  (قسم "حول التطبيق")
subtitle: '1.0.2',
```

```pascal
// installer/setup.iss
#define MyAppVersion "1.0.2"
```

```bash
# أوامر الإصدار
git tag v1.0.2
git push origin v1.0.2
```

---

## 🔧 متغيرات التطبيق الأساسية

```dart
// ── GitHub Updater Config ──
const String owner = 'HAY2023';
const String repository = 'Mahfadha-Pro';
const String manifestAsset = 'latest.json';
const List<String> appAssets = [
  'Mahfadha-Pro-Setup.exe',
  'MahfadhaPro.exe',
  'Mahfadha-Pro-Windows.zip',
];

// ── Window Config ──
const Size windowSize = Size(1180, 780);
const Size minimumSize = Size(980, 680);
const String windowTitle = 'CipherVault Pro';

// ── WebSocket Server ──
const int wsPort = 2050;
const String wsHost = '127.0.0.1';
// ws://127.0.0.1:2050

// ── Auto-Lock ──
const Duration autoLockTimeout = Duration(seconds: 180);
const int warningThreshold = 30; // seconds

// ── Security ──
const String encryptionAlgorithm = 'AES-256-GCM';
const String keyDerivation = 'PBKDF2';
const String secureElement = 'ATECC608A';
const String fingerprintSensor = 'GROW R503';
const String hashAlgorithm = 'SHA-256';
```

---

## 📁 هيكل المشروع

```
Mahfadha-Pro/
├── app/                      # تطبيق Flutter Desktop
│   ├── lib/
│   │   ├── main.dart                    # نقطة الدخول + Window Manager
│   │   ├── providers/app_state.dart     # إدارة الحالة (Provider)
│   │   ├── screens/
│   │   │   ├── connection_gate.dart     # بوابة الاتصال بالجهاز
│   │   │   ├── dashboard.dart           # لوحة التحكم الرئيسية
│   │   │   ├── update_center.dart       # مركز التحديثات (تطبيق + متحكم)
│   │   │   ├── vault_screen.dart        # القبو الحساس (بصمة)
│   │   │   ├── settings_screen.dart     # الإعدادات
│   │   │   └── csv_importer_and_health.dart
│   │   ├── services/
│   │   │   ├── github_updater_service.dart  # خدمة التحديث الآمن
│   │   │   └── websocket_server_service.dart # خادم الاعتراض
│   │   ├── widgets/
│   │   │   ├── app_title_bar.dart       # شريط العنوان المخصص
│   │   │   ├── sidebar.dart             # القائمة الجانبية
│   │   │   ├── auto_save_dialog.dart    # حوار الحفظ التلقائي
│   │   │   ├── auto_lock_wrapper.dart   # القفل التلقائي
│   │   │   └── liquid_background.dart   # الخلفية المتحركة
│   │   └── theme/mars_theme.dart        # نظام التصميم
│   └── pubspec.yaml
├── firmware/                 # ESP32-S3 Firmware (PlatformIO)
├── cli-bridge/               # Python Serial Bridge
├── installer/setup.iss       # Inno Setup Installer
└── .github/workflows/
    └── release.yml           # CI/CD Pipeline
```

---

## 🎛️ مركز التحديثات

يدعم تابين:

| تاب | الوظيفة |
|---|---|
| **تحديث التطبيق** | تنزيل وتثبيت Mahfadha-Pro-Setup.exe مع SHA-256 |
| **تحديث المتحكم** | فحص تحديثات firmware الـ ESP32-S3 عبر OTA |

### 🔄 تدفق تحديث التطبيق
1. **فحص** → `latest.json` من GitHub Releases
2. **تنزيل** → `.exe` مع شريط تقدم
3. **تحقق** → SHA-256 checksum
4. **حوار تأكيد** → تحذير بإغلاق التطبيق
5. **تثبيت** → تشغيل المثبت + `exit(0)`

---

## 🔌 نظام الحفظ التلقائي (Auto-Save)

عند دخول موقع ويب وإدخال بيانات تسجيل الدخول:

1. إضافة Chrome ترسل البيانات عبر Native Messaging
2. `mahfadha_bridge.exe` يستقبل ويُعيد التوجيه
3. `WebSocketServerService` على `ws://127.0.0.1:2050` يستقبل
4. `_AutoSaveOverlay` يكتشف `pendingCredential` في `AppState`
5. `AutoSaveDialog` يظهر فوراً مع خيارات:
   - **تشفير وحفظ** → يُرسل إلى ESP32 عبر AES-256-GCM
   - **تجاهل** → يمسح البيانات من الذاكرة فوراً

---

## 🚀 التشغيل

```bash
# 1. تشغيل التطبيق (تطوير)
cd app
flutter pub get
flutter run -d windows

# 2. بناء للإنتاج
flutter build windows --release

# 3. إصدار جديد
git tag v1.0.3
git push origin v1.0.3
```

---

## ⚠️ تحذير أمني
لا تفقد رقم التعريف الشخصي أو جهازك المادي. بسبب استخدام ATECC608A Secure Element، **لا يوجد باب خلفي مطلقاً**. إذا دُمّر الجهاز بدون نسخة احتياطية `.mahfadha`، فالبيانات غير قابلة للاسترداد رياضياً.
