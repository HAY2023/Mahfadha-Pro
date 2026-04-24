#include <Arduino.h>
#include <TFT_eSPI.h>
#include <Preferences.h>
#include <RTClib.h>
#include <TOTP.h>
#include <ArduinoJson.h>
#include "USB.h"
#include "USBHIDKeyboard.h"
#include "mbedtls/aes.h"
#include "mbedtls/md.h"
#include "mbedtls/gcm.h"
#include <vector>
#include <Adafruit_Fingerprint.h>
#include <ESP32Encoder.h>
#include "cryptoauthlib.h"

// ==========================================
// CONFIGURATION & SECURE PARAMETERS
// ==========================================
// Rotary Encoder Pins
#define ENC_A       4
#define ENC_B       5
#define ENC_SW      6

// Fingerprint Sensor Pins (UART)
#define FP_RX_PIN   17
#define FP_TX_PIN   18

// Power Management
#define BAT_ADC_PIN 9
#define I2C_SDA     21
#define I2C_SCL     22

const int MAX_ACCOUNTS = 100;
const unsigned long IDLE_TIMEOUT_MS = 60000;
unsigned long lastActivityTime = 0;
const int MAX_FAILURES = 15;

// ==========================================
// GLOBALS & INSTANCES
// ==========================================
TFT_eSPI tft = TFT_eSPI();
USBHIDKeyboard Keyboard;
Preferences prefs;
RTC_DS3231 rtc;
ESP32Encoder encoder;
HardwareSerial fpSerial(1);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fpSerial);
ATCAIfaceCfg cfg_atecc608a_i2c;

struct Account {
    int id;
    String name;
    String username;
    String password;
    String totpSecret;
};

std::vector<Account> accounts;

enum MenuScreen { SCREEN_LOCKED, SCREEN_PIN_ENTRY, SCREEN_MAIN, SCREEN_PASSWORDS, SCREEN_PASSWORD_ACTIONS, SCREEN_SETTINGS };
MenuScreen currentScreen = SCREEN_LOCKED;
int selectedIndex = 0;
int menuScrollOffset = 0;
long lastEncoderPosition = 0;
bool isUnlocked = false;
int failedAttempts = 0;

// Security variables
uint8_t derivedSessionKey[32];
uint8_t hardwareSalt[32] = {0x01, 0x02, 0x03}; // In production, read from ATECC608A serial/data slot
String pinEntryBuffer = "";
const String MASTER_PIN = "123456"; // Hash this in production!

// ==========================================
// FUNCTION PROTOTYPES
// ==========================================
void initATECC608A();
void deriveSessionKey(const String& pin, uint8_t fingerprintID);
void hardWipe();
void encryptDataGCM(const String& plaintext, uint8_t* ciphertext, size_t& outLen, uint8_t* iv, uint8_t* tag);
String decryptDataGCM(const uint8_t* ciphertext, size_t len, uint8_t* iv, uint8_t* tag);
void loadAccounts();
void saveAccounts();
void clearRAM();
void lockDevice();
void unlockDevice(uint8_t fpID, String pin);
void handleSerialCommands();
void drawMenu();
void handleEncoderAndFingerprint();
int getBatteryPercentage();

// ==========================================
// SETUP
// ==========================================
void setup() {
    Serial.begin(115200); 
    
    tft.init();
    tft.setRotation(1);
    tft.fillScreen(TFT_BLACK);
    
    // Rotary Encoder
    ESP32Encoder::useInternalWeakPullResistors = UP;
    encoder.attachHalfQuad(ENC_A, ENC_B);
    encoder.setCount(0);
    pinMode(ENC_SW, INPUT_PULLUP);

    Keyboard.begin();
    USB.begin();
    
    Wire.begin(I2C_SDA, I2C_SCL);
    rtc.begin();
    
    prefs.begin("mahfadha", false);
    failedAttempts = prefs.getInt("fails", 0);

    fpSerial.begin(57600, SERIAL_8N1, FP_RX_PIN, FP_TX_PIN);
    finger.begin(57600);
    if (finger.verifyPassword()) {
        finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
    }

    initATECC608A();

    lastActivityTime = millis();
    lockDevice(); 
}

// ==========================================
// MAIN LOOP
// ==========================================
void loop() {
    handleSerialCommands();
    handleEncoderAndFingerprint();
    
    if (isUnlocked && (millis() - lastActivityTime > IDLE_TIMEOUT_MS)) {
        lockDevice();
    }
    
    delay(10);
}

// ==========================================
// HARDWARE & CRYPTO LOGIC
// ==========================================
void initATECC608A() {
    // Config for ATECC608A over I2C
    cfg_atecc608a_i2c.iface_type = ATCA_I2C_IFACE;
    cfg_atecc608a_i2c.devtype = ATECC608A;
    cfg_atecc608a_i2c.atcai2c.slave_address = 0xC0; // Default I2C address (shifted)
    cfg_atecc608a_i2c.atcai2c.bus = 0;
    cfg_atecc608a_i2c.atcai2c.baud = 100000;
    cfg_atecc608a_i2c.wake_delay = 1500;
    cfg_atecc608a_i2c.rx_retries = 20;

    ATCA_STATUS status = atcab_init(&cfg_atecc608a_i2c);
    if (status != ATCA_SUCCESS) {
        // Serial.println("ATECC608A Init Failed");
        // Handle failure (e.g. halt system if military grade requires it)
    }
}

int getBatteryPercentage() {
    // Assuming simple voltage divider on ADC pin 9
    int raw = analogRead(BAT_ADC_PIN);
    float voltage = (raw / 4095.0) * 3.3 * 2; // Assuming 1:1 voltage divider
    int percent = map(voltage * 100, 320, 420, 0, 100);
    return constrain(percent, 0, 100);
}

void hardWipe() {
    tft.fillScreen(TFT_RED);
    tft.setTextColor(TFT_WHITE);
    tft.setCursor(10, 50);
    tft.setTextSize(3);
    tft.println("SECURITY BREACH");
    tft.setTextSize(2);
    tft.println("Wiping Data...");
    
    prefs.clear(); // Clear all NVM
    // In a real implementation, you would also issue commands to ATECC608A to lock/wipe keys
    
    delay(3000);
    ESP.restart();
}

void deriveSessionKey(const String& pin, uint8_t fingerprintID) {
    // PBKDF2 Derivation using mbedTLS
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 1);
    
    String combinedInput = pin + String(fingerprintID);
    
    // In production, hardwareSalt should be securely read from ATECC608A
    mbedtls_pkcs5_pbkdf2_hmac(&ctx, 
        (const unsigned char*)combinedInput.c_str(), combinedInput.length(),
        hardwareSalt, sizeof(hardwareSalt),
        10000, // Iterations
        32, derivedSessionKey);
        
    mbedtls_md_free(&ctx);
}

void encryptDataGCM(const String& plaintext, uint8_t* ciphertext, size_t& outLen, uint8_t* iv, uint8_t* tag) {
    mbedtls_gcm_context gcm;
    mbedtls_gcm_init(&gcm);
    mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, derivedSessionKey, 256);
    
    // Generate random IV (in prod, use ATECC608A RNG)
    for(int i=0; i<12; i++) iv[i] = random(256);
    
    outLen = plaintext.length();
    mbedtls_gcm_crypt_and_tag(&gcm, MBEDTLS_GCM_ENCRYPT, outLen,
                              iv, 12, 
                              NULL, 0, // No Additional Authenticated Data
                              (const unsigned char*)plaintext.c_str(), ciphertext,
                              16, tag);
    mbedtls_gcm_free(&gcm);
}

String decryptDataGCM(const uint8_t* ciphertext, size_t len, uint8_t* iv, uint8_t* tag) {
    mbedtls_gcm_context gcm;
    mbedtls_gcm_init(&gcm);
    mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, derivedSessionKey, 256);
    
    uint8_t output[len + 1];
    memset(output, 0, len + 1);
    
    int ret = mbedtls_gcm_auth_decrypt(&gcm, len, iv, 12, NULL, 0, tag, 16, ciphertext, output);
    mbedtls_gcm_free(&gcm);
    
    if (ret != 0) return ""; // Authentication failed! (Tampered data or wrong key)
    
    return String((char*)output);
}

// ==========================================
// DATA HANDLING (NVM)
// ==========================================
void loadAccounts() {
    accounts.clear();
    int count = prefs.getInt("acc_count", 0);
    
    for (int i = 0; i < count; i++) {
        String prefix = "a" + String(i);
        Account acc;
        acc.id = i;
        
        // Helper lambda for reading and decrypting GCM
        auto loadField = [&](const String& pfx, String& field) {
            size_t cLen = prefs.getBytesLength((pfx + "_c").c_str());
            if (cLen > 0) {
                uint8_t c[cLen];
                uint8_t iv[12];
                uint8_t tag[16];
                prefs.getBytes((pfx + "_c").c_str(), c, cLen);
                prefs.getBytes((pfx + "_i").c_str(), iv, 12);
                prefs.getBytes((pfx + "_t").c_str(), tag, 16);
                field = decryptDataGCM(c, cLen, iv, tag);
            }
        };

        loadField(prefix + "n", acc.name);
        loadField(prefix + "u", acc.username);
        loadField(prefix + "p", acc.password);
        
        if (acc.name != "") { // Only add if decryption succeeded
            accounts.push_back(acc);
        }
    }
}

void saveAccounts() {
    prefs.putInt("acc_count", accounts.size());
    for (size_t i = 0; i < accounts.size(); i++) {
        String prefix = "a" + String(i);
        
        auto saveField = [&](const String& pfx, const String& field) {
            uint8_t c[256];
            uint8_t iv[12];
            uint8_t tag[16];
            size_t len;
            encryptDataGCM(field, c, len, iv, tag);
            prefs.putBytes((pfx + "_c").c_str(), c, len);
            prefs.putBytes((pfx + "_i").c_str(), iv, 12);
            prefs.putBytes((pfx + "_t").c_str(), tag, 16);
        };

        saveField(prefix + "n", accounts[i].name);
        saveField(prefix + "u", accounts[i].username);
        saveField(prefix + "p", accounts[i].password);
    }
}

void clearRAM() {
    for(auto& acc : accounts) {
        acc.name = "";
        acc.username = "";
        acc.password = "";
    }
    accounts.clear();
    memset(derivedSessionKey, 0, 32); // Clear key from RAM
}

void lockDevice() {
    isUnlocked = false;
    currentScreen = SCREEN_LOCKED;
    clearRAM();
    finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
    Serial.println("{\"status\":\"event\",\"message\":\"BIOMETRIC_LOCKED\"}");
    drawMenu();
}

void unlockDevice(uint8_t fpID, String pin) {
    // Derive key using Biometric ID or PIN
    deriveSessionKey(pin, fpID); 
    
    // Reset fail counter on success
    failedAttempts = 0;
    prefs.putInt("fails", failedAttempts);

    isUnlocked = true;
    lastActivityTime = millis();
    finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_GREEN, 10);
    
    loadAccounts(); // Decrypt into RAM using derived key
    
    currentScreen = SCREEN_MAIN;
    selectedIndex = 0;
    Serial.println("{\"status\":\"event\",\"message\":\"BIOMETRIC_UNLOCKED\"}");
    delay(500); 
    finger.LEDcontrol(FINGERPRINT_LED_OFF, 0, FINGERPRINT_LED_CYAN); 
    drawMenu();
}

void handleFail() {
    failedAttempts++;
    prefs.putInt("fails", failedAttempts);
    if (failedAttempts >= MAX_FAILURES) {
        hardWipe();
    }
    finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_RED, 10);
    delay(500);
    finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
}

// ==========================================
// SYSTEM FLOW & NAVIGATION
// ==========================================
void handleEncoderAndFingerprint() {
    // 1. Biometric Check
    if (!isUnlocked && currentScreen == SCREEN_LOCKED) {
        uint8_t p = finger.getImage();
        if (p == FINGERPRINT_OK) {
            p = finger.image2Tz();
            if (p == FINGERPRINT_OK) {
                p = finger.fingerSearch();
                if (p == FINGERPRINT_OK) {
                    unlockDevice(finger.fingerID, ""); // Success via FP
                } else {
                    handleFail();
                }
            }
        }
    }

    // 2. Rotary Encoder Scroll
    long currentPos = encoder.getCount() / 2; 
    if (currentPos != lastEncoderPosition) {
        lastActivityTime = millis();
        int dir = (currentPos > lastEncoderPosition) ? 1 : -1;
        lastEncoderPosition = currentPos;

        if (currentScreen == SCREEN_LOCKED) {
            // Start PIN entry fallback
            currentScreen = SCREEN_PIN_ENTRY;
            selectedIndex = 0; // 0-9
        } else if (currentScreen == SCREEN_PIN_ENTRY) {
            selectedIndex = (selectedIndex + dir + 10) % 10;
        } else if (currentScreen == SCREEN_MAIN) {
            selectedIndex = (selectedIndex + dir + 3) % 3;
        } else if (currentScreen == SCREEN_PASSWORDS && accounts.size() > 0) {
            selectedIndex = (selectedIndex + dir + accounts.size()) % accounts.size();
        } else if (currentScreen == SCREEN_PASSWORD_ACTIONS) {
            menuScrollOffset = (menuScrollOffset + dir + 4) % 4;
        }
        drawMenu();
    }

    // 3. Encoder Click
    static bool lastSwState = HIGH;
    bool swState = digitalRead(ENC_SW);
    if (swState == LOW && lastSwState == HIGH) { 
        lastActivityTime = millis();
        
        if (currentScreen == SCREEN_PIN_ENTRY) {
            pinEntryBuffer += String(selectedIndex);
            if (pinEntryBuffer.length() == 6) {
                if (pinEntryBuffer == MASTER_PIN) {
                    unlockDevice(0, MASTER_PIN); // Success via PIN
                } else {
                    handleFail();
                    currentScreen = SCREEN_LOCKED;
                }
                pinEntryBuffer = "";
            }
        } else if (currentScreen == SCREEN_MAIN) {
            if (selectedIndex == 0) { currentScreen = SCREEN_PASSWORDS; selectedIndex = 0; }
        } else if (currentScreen == SCREEN_PASSWORDS) {
            if (accounts.size() > 0) {
                currentScreen = SCREEN_PASSWORD_ACTIONS;
                menuScrollOffset = 0;
            }
        } else if (currentScreen == SCREEN_PASSWORD_ACTIONS) {
            Account acc = accounts[selectedIndex];
            if (menuScrollOffset == 0) Keyboard.print(acc.username);
            else if (menuScrollOffset == 1) Keyboard.print(acc.password);
            else if (menuScrollOffset == 2) {
                Keyboard.print(acc.username);
                Keyboard.write(KEY_TAB);
                delay(100);
                Keyboard.print(acc.password);
                Keyboard.write(KEY_RETURN);
            } else if (menuScrollOffset == 3) {
                currentScreen = SCREEN_PASSWORDS;
            }
        }
        drawMenu();
    }
    lastSwState = swState;
}

// ==========================================
// USB SERIAL COMMUNICATION
// ==========================================
void handleSerialCommands() {
    if (Serial.available()) {
        String payload = Serial.readStringUntil('\n');
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, payload);
        if (err) return;
        
        String command = doc["cmd"].as<String>();
        
        if (command == "add_account" || command == "delete_account" || command == "list_accounts") {
            if (!isUnlocked) {
                Serial.println("{\"status\":\"error\",\"message\":\"Device is locked.\"}");
                return;
            }
            lastActivityTime = millis(); 
        }

        if (command == "sync_time") {
            rtc.adjust(DateTime(doc["time"].as<uint32_t>()));
            Serial.println("{\"status\":\"success\",\"message\":\"Time synced\"}");
        }
        else if (command == "add_account") {
            if (accounts.size() >= MAX_ACCOUNTS) {
                Serial.println("{\"status\":\"error\",\"message\":\"Limit reached\"}");
                return;
            }
            Account newAcc;
            newAcc.id = accounts.size();
            newAcc.name = doc["name"].as<String>();
            newAcc.username = doc["username"].as<String>();
            newAcc.password = doc["password"].as<String>();
            accounts.push_back(newAcc);
            saveAccounts();
            Serial.println("{\"status\":\"success\",\"message\":\"Account added securely (GCM)\"}");
            drawMenu();
        }
        else if (command == "delete_account") {
            int id = doc["id"].as<int>();
            if (id >= 0 && id < accounts.size()) {
                accounts.erase(accounts.begin() + id);
                saveAccounts();
                Serial.println("{\"status\":\"success\",\"message\":\"Account deleted\"}");
                drawMenu();
            }
        }
        else if (command == "list_accounts") {
            JsonDocument res;
            res["status"] = "success";
            JsonArray arr = res["accounts"].to<JsonArray>();
            for (size_t i = 0; i < accounts.size(); i++) {
                JsonObject obj = arr.add<JsonObject>();
                obj["id"] = i;
                obj["name"] = accounts[i].name; 
            }
            serializeJson(res, Serial);
            Serial.println();
        }
        else if (command == "export_backup") {
             if (!isUnlocked) {
                 Serial.println("{\"status\":\"error\",\"message\":\"Unlock required for backup.\"}");
                 return;
             }
             // Send raw NVM hex blobs to PC to be saved as .mahfadha
             // Implement logic to iterate NVM and send JSON array of hex blobs.
             Serial.println("{\"status\":\"success\",\"message\":\"Backup exported (Mock)\"}");
        }
    }
}

// ==========================================
// UI
// ==========================================
void drawMenu() {
    tft.fillScreen(TFT_BLACK);
    tft.setTextSize(2);
    tft.setCursor(0, 0);
    
    // Battery
    tft.setTextSize(1);
    tft.setCursor(120, 0);
    tft.setTextColor(TFT_GREEN);
    tft.print(getBatteryPercentage()); tft.println("%");
    tft.setTextSize(2);
    tft.setCursor(0, 15);

    if (currentScreen == SCREEN_LOCKED) {
        tft.setTextColor(TFT_ORANGE);
        tft.println("Mahfadha Pro");
        tft.println("");
        tft.setTextColor(TFT_CYAN);
        tft.println("Scan Fingerprint");
        tft.setTextColor(TFT_DARKGREY);
        tft.println("or scroll for PIN");
        if (failedAttempts > 0) {
            tft.setTextColor(TFT_RED);
            tft.print("Attempts: "); tft.print(failedAttempts); tft.print("/"); tft.println(MAX_FAILURES);
        }
    }
    else if (currentScreen == SCREEN_PIN_ENTRY) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Enter Master PIN");
        tft.setTextColor(TFT_WHITE);
        tft.print("PIN: ");
        for(int i=0; i<pinEntryBuffer.length(); i++) tft.print("*");
        tft.println();
        tft.setTextColor(TFT_GREEN);
        tft.print("Select: [ "); tft.print(selectedIndex); tft.println(" ]");
    }
    else if (currentScreen == SCREEN_MAIN) {
        tft.setTextColor(TFT_ORANGE);
        tft.println("Mahfadha Pro");
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        String items[] = {"Vault", "TOTP", "Settings"};
        for (int i = 0; i < 3; i++) {
            if (i == selectedIndex) { tft.setTextColor(TFT_GREEN); tft.print("> "); }
            else { tft.setTextColor(TFT_WHITE); tft.print("  "); }
            tft.println(items[i]);
        }
    }
    else if (currentScreen == SCREEN_PASSWORDS) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Vault Accounts");
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        for (size_t i = 0; i < accounts.size(); i++) {
            if (i == selectedIndex) { tft.setTextColor(TFT_GREEN); tft.print("> "); }
            else { tft.setTextColor(TFT_WHITE); tft.print("  "); }
            tft.println(accounts[i].name);
        }
        if (accounts.size() == 0) tft.println("  Vault Empty");
    }
    else if (currentScreen == SCREEN_PASSWORD_ACTIONS) {
        tft.setTextColor(TFT_YELLOW);
        tft.println(accounts[selectedIndex].name);
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        String items[] = {"Type Username", "Type Password", "Auto-Login", "Back"};
        for (int i = 0; i < 4; i++) {
            if (i == menuScrollOffset) { tft.setTextColor(TFT_GREEN); tft.print("> "); }
            else { tft.setTextColor(TFT_WHITE); tft.print("  "); }
            tft.println(items[i]);
        }
    }
}
