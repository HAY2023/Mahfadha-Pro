# 🛡️ Mahfadha Pro

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg)
![Version](https://img.shields.io/badge/Version-1.0.2-orange.svg)

**Mahfadha Pro** is a next-generation, military-grade hardware password manager and Authenticator (TOTP) built for zero-trust environments. Designed in 2026, it operates entirely offline, using advanced cryptographic co-processors and biometric authentication to secure your digital life.

## 🌌 Project Philosophy
1. **Zero Persistence:** Sensitive data (passwords, encryption keys, decrypted payloads) is **never** stored on the host PC. Data exists momentarily in RAM during transfer and is wiped immediately.
2. **Ghost Mode (Stealth Serial):** The hardware device (ESP32-S3) is invisible to standard serial monitors. It remains silent and ignores all incoming traffic until a mathematically complex 64-character SHA-256 Handshake Token is provided.
3. **Hardware-Enforced Security:** Uses the ATECC608A Secure Element to handle AES-256-GCM encryption. The master key never touches the ESP32's volatile or non-volatile memory.

---

## 📁 Repository Structure

### 🔌 `/firmware` (ESP32-S3 / C++)
The core brain of the device.
* **Biometrics:** GROW R503 Fingerprint sensor integration.
* **Crypto:** ATECC608A (CryptoAuthLib) & PBKDF2 Key Derivation.
* **Navigation:** Interrupt-driven Rotary Encoder (Jog Dial).
* **Self-Destruct:** Formats all NVM partitions and locks ATECC608A if brute-forced (15 failed attempts).

### 🖥️ `/app` (Flutter / Dart)
The companion application for Windows/macOS/Linux.
* **Frosted Glass UI:** A stunning, modern, and immersive 2026 aesthetic.
* **Migration Tool:** Encrypts and imports CSV files from Bitwarden and Chrome.
* **Zero-Knowledge Backup:** Exports/Imports `.mahfadha` encrypted blobs.
* **Dashboard Controller:** Live telemetry (temperature, storage, system load) with circular gauges.
* **OTA Update System:** Secure self-update via GitHub Releases with SHA-256 verification — app exits automatically during install.

### 🌉 `/cli-bridge` (Python)
The secure middleware.
* Acts as the exclusive translator between the Flutter App and the Hardware.
* Manages the "Secret Handshake" protocol.

---

## 🎛️ Dashboard Controller

The dashboard (`/app/lib/screens/dashboard.dart`) provides:

| Feature | Description |
|---|---|
| **Live Telemetry** | Real-time temperature, storage usage, and system load from ESP32 |
| **Thermal Protection** | Auto-shutdown at 60°C with full data wipe |
| **Operations Grid** | Quick access to all device operations (add account, sync time, backup, etc.) |
| **Password Health** | Analyzes imported passwords for weak/reused entries |
| **Scrollable Layout** | All sections visible without overflow on any screen size |

### 🔄 OTA Update Flow

The update system (`/app/lib/screens/update_center.dart` + `/app/lib/services/github_updater_service.dart`):

1. **Check** → Fetches `latest.json` manifest from GitHub Releases
2. **Download** → Streams the `.exe` installer with progress tracking
3. **Verify** → SHA-256 checksum validation (file deleted on mismatch)
4. **Install** → Confirmation dialog → launches installer → **app exits automatically**

---

## 🚀 Getting Started

### 📥 Download the Pre-built `.exe` (Windows)
The easiest way to get started on Windows is to download the pre-built binaries:
1. Go to the [Releases](../../releases) page on GitHub.
2. Download `Mahfadha-Pro-Setup.exe` from the latest release.
3. Run the installer and complete setup.
4. If you need the portable package, download `Mahfadha-Pro-Windows.zip`.

> **Note:** GitHub Actions automatically builds and publishes `Mahfadha-Pro-Setup.exe`, `Mahfadha-Pro-Windows.zip`, and `latest.json` whenever a new Git tag like `v1.2.0` is pushed.

---

### 1. Flash the Firmware
1. Navigate to `/firmware`.
2. Open with VS Code + PlatformIO.
3. Build and upload to your ESP32-S3.

### 2. Run the Secure Bridge
1. Navigate to `/cli-bridge`.
2. Install requirements (if any).
3. Run the bridge:
   ```bash
   python mahfadha_bridge.py --connect --port COM3 --session-auth
   ```

### 3. Launch the App
1. Navigate to `/app`.
2. Run `flutter pub get`.
3. Launch desktop app: `flutter run -d windows` (or macos/linux).

---

## 🔖 Releasing a New Version

1. Update `version:` in `app/pubspec.yaml`
2. Update `MyAppVersion` in `installer/setup.iss`
3. Update `_currentDesktopVersion` in `app/lib/screens/update_center.dart`
4. Update version in `app/lib/screens/settings_screen.dart`
5. Commit, then push a tag:
   ```bash
   git tag v1.0.3
   git push origin v1.0.3
   ```
6. GitHub Actions will build and publish the release automatically.

---

## ⚠️ Security Warning
Do not lose your Master PIN or your hardware device. Because Mahfadha Pro uses the ATECC608A Secure Element, **there is absolutely no backdoor**. If the hardware is destroyed and no `.mahfadha` backup exists, your data is mathematically unrecoverable.
