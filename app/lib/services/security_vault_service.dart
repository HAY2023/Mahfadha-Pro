import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/app_state.dart';

class SecurityVaultService {
  static final SecurityVaultService _instance = SecurityVaultService._internal();
  factory SecurityVaultService() => _instance;
  SecurityVaultService._internal();

  String? _cachedPin;
  String? _panicPin;

  // Derives a 32-byte key from the 6-digit PIN using SHA-256
  encrypt.Key _deriveKey(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  Future<void> initialize(String pin) async {
    _cachedPin = pin;
    final prefs = await SharedPreferences.getInstance();
    _panicPin = prefs.getString('panic_pin');
  }

  Future<void> setPanicPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('panic_pin', pin);
    _panicPin = pin;
  }

  bool isPanicPin(String pin) {
    return _panicPin != null && pin == _panicPin;
  }

  Future<void> triggerSelfDestruct() async {
    final prefs = await SharedPreferences.getInstance();
    // Wipe everything
    await prefs.remove('app_pin');
    await prefs.remove('panic_pin');
    
    // Clear any local backup/storage if we had any
    final dir = await getApplicationDocumentsDirectory();
    final backupFile = File('${dir.path}/my_passwords.cvault');
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  // Encrypt string with AES-256
  String encryptData(String plainText) {
    if (_cachedPin == null) throw Exception("Vault locked");
    final key = _deriveKey(_cachedPin!);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    // return IV + encrypted payload, base64 encoded
    return base64Encode(iv.bytes + encrypted.bytes);
  }

  // Decrypt string with AES-256
  String decryptData(String encryptedBase64) {
    if (_cachedPin == null) throw Exception("Vault locked");
    final key = _deriveKey(_cachedPin!);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    
    final allBytes = base64Decode(encryptedBase64);
    final iv = encrypt.IV(allBytes.sublist(0, 16));
    final encrypted = encrypt.Encrypted(allBytes.sublist(16));
    
    return encrypter.decrypt(encrypted, iv: iv);
  }

  // Export all accounts to an encrypted .cvault file
  Future<String> exportBackup(List<VaultAccount> accounts, String nanoId) async {
    final jsonList = accounts.map((a) => a.toJson()).toList();
    final jsonStr = jsonEncode(jsonList);

    // Use a key derived from the Nano ID (hardware binding)
    final key = _deriveKey(nanoId);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);
    final finalData = base64Encode(iv.bytes + encrypted.bytes);

    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/my_passwords.cvault';
    final file = File(filePath);
    await file.writeAsString(finalData);
    
    return filePath;
  }

  // Import accounts from a .cvault file (must match Nano ID)
  Future<List<VaultAccount>> importBackup(String filePath, String nanoId) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception("Backup not found");

    final finalData = await file.readAsString();
    final allBytes = base64Decode(finalData);

    final key = _deriveKey(nanoId);
    final iv = encrypt.IV(allBytes.sublist(0, 16));
    final encrypted = encrypt.Encrypted(allBytes.sublist(16));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    try {
      final decryptedStr = encrypter.decrypt(encrypted, iv: iv);
      final jsonList = jsonDecode(decryptedStr) as List<dynamic>;
      return jsonList.map((e) => VaultAccount.fromJson(e)).toList();
    } catch (e) {
      throw Exception("Invalid backup or Nano ID mismatch");
    }
  }
}
