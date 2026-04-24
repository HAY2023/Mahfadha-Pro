# Mahfadha Pro - Military Grade Hardware Password Manager

This repository contains the professional, commercial-grade implementation of the "Mahfadha Pro" system, transitioning from a WiFi-based PoC to a 100% offline, secure, military-grade architecture.

## 📁 Repository Structure

### 1. `esp32_firmware/` (ESP32-S3 C++ Code)
The completely rewritten firmware for the ESP32-S3 hardware module.
**Key Upgrades:**
- **Zero Radio / 100% Offline:** All WiFi, WebServer, and NTP functionalities have been completely removed to ensure zero wireless attack surface.
- **AES-256 CBC Encryption:** Uses `mbedtls` to encrypt all sensitive data before saving it to the ESP32's non-volatile memory (NVM via `Preferences`). The keys/passwords exist in plaintext *only* in the volatile RAM when needed for UI or USB typing.
- **Dynamic Memory Allocation:** Removed hardcoded arrays. Now dynamically stores up to 100 accounts using `std::vector`.
- **Hardware RTC:** Integrated `RTClib` (DS3231) for maintaining precise time for TOTP generation without internet access.
- **Secure USB Serial Protocol:** Replaced the WiFi portal with a JSON-based command protocol over USB Serial.

#### How to build (PlatformIO):
1. Open the `esp32_firmware` folder in VSCode with the PlatformIO extension.
2. Connect your ESP32-S3.
3. Click "Build" and "Upload".

### 2. `companion_app/` (Cross-Platform Flutter App)
The structural codebase for the PC/Mobile Companion App built using **Flutter**.
**Key Features:**
- **Cross-Platform Compatibility:** Runs on Windows, macOS, Linux natively. Can easily be ported to Android/iOS (using mobile USB OTG packages) later with the same Dart codebase.
- **Serial Port Communication:** Uses `flutter_libserialport` to scan for connected Mahfadha Pro devices and establish a direct wired connection.
- **Command Center:** Features a dynamic UI to send JSON commands over USB to Add Accounts, Delete Accounts, and Sync the ESP32's Hardware RTC time directly from the host PC.

#### How to run:
1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Navigate to `companion_app/` in your terminal.
3. Run `flutter pub get`.
4. Run `flutter run -d windows` (or macos/linux depending on your OS).

## 🔒 Security Posture
*   **Air-gapped by default:** The device has no capability to connect to the internet.
*   **Zero-Trust Storage:** If the ESP32 flash chip is desoldered or dumped, the attacker only sees AES-256 encrypted blobs.
*   **Direct Hardware Typing:** Passwords are never sent back to the PC companion app. They are typed directly into the OS as a standard USB Keyboard (`USBHIDKeyboard`), defeating software keyloggers.
