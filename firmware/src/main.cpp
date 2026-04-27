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
    String targetUrl;   // [V2] Auto-login URL for Rubber Ducky payload
    String totpSecret;
    String phoneNumber; // [V4] Bound phone number for 2FA recovery
};

// [V4] Phone Vault Entry — standalone encrypted phone number
struct PhoneEntry {
    int id;
    String label;
    String phoneNumber;
    String notes;
};

std::vector<Account> accounts;
std::vector<PhoneEntry> phoneEntries;

enum MenuScreen {
    SCREEN_BOOT,
    SCREEN_SETUP_WAITING,
    SCREEN_SETUP_ENROLL,
    SCREEN_SETUP_ENROLL_OK,
    SCREEN_LOCKED,
    SCREEN_PIN_ENTRY,
    SCREEN_MAIN,
    SCREEN_PASSWORDS,
    SCREEN_PASSWORD_ACTIONS,
    SCREEN_AUTO_LOGIN,    // [V2] Rubber Ducky auto-login execution
    SCREEN_SETTINGS,
    SCREEN_VERIFY_IDENTITY,
    SCREEN_SEED_VAULT,
    SCREEN_FIDO2
};
MenuScreen currentScreen = SCREEN_BOOT;
MenuScreen returnAfterVerify = SCREEN_MAIN;
int selectedIndex = 0;
int menuScrollOffset = 0;
long lastEncoderPosition = 0;
bool isUnlocked = false;
int failedAttempts = 0;
bool hasMasterFingerprint = false;
bool setupComplete = false;

// Security variables
uint8_t derivedSessionKey[32];
uint8_t hardwareSalt[32] = {0x01, 0x02, 0x03}; // In production, read from ATECC608A serial/data slot
String pinEntryBuffer = "";
const String MASTER_PIN = "123456"; // Hash this in production!

// Ghost Mode Variables
bool isGhostModeActive = true;
int serialFailCount = 0;
unsigned long serialLockoutTime = 0;
const unsigned long SERIAL_LOCKOUT_DURATION = 10 * 60 * 1000; // 10 minutes
// Example token for 'password123' + 'MAHFADHA_GHOST_PROTOCOL_V1_2026'
const String EXPECTED_TOKEN = "c650bc7da0cc3565012f2e519c961e61884485eb3528b6d39d911b329431de3f";

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
void loadPhones();       // [V4] Phone vault persistence
void savePhones();       // [V4] Phone vault persistence
void clearRAM();
void lockDevice();
void unlockDevice(uint8_t fpID, String pin);
void executeRubberDuckyPayload(Account acc);
void handleSerialCommands();
void drawMenu();
void handleEncoderAndFingerprint();
int getBatteryPercentage();
void drawBootScreen();
void checkFirstTimeSetup();
void handleSetupSerial(JsonDocument& doc, const String& command);
void executeRubberDuckyPayload(const Account& acc);

// ==========================================
// SETUP
// ==========================================
void setup() {
    Serial.begin(115200); 
    
    tft.init();
    tft.setRotation(1);
    tft.fillScreen(TFT_BLACK);
    
    // ── Boot Welcome Screen ─────────────────────────
    drawBootScreen();
    
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
    setupComplete = prefs.getBool("setup_done", false);

    fpSerial.begin(57600, SERIAL_8N1, FP_RX_PIN, FP_TX_PIN);
    finger.begin(57600);
    if (finger.verifyPassword()) {
        finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
    }

    initATECC608A();
    lastActivityTime = millis();

    // ── First-Time Setup Check ──────────────────────
    checkFirstTimeSetup();
}

void drawBootScreen() {
    tft.fillScreen(TFT_BLACK);
    tft.setTextColor(TFT_CYAN);
    tft.setTextSize(3);
    tft.setCursor(10, 30);
    tft.println("Mahfadha Pro");
    tft.setTextSize(1);
    tft.setTextColor(TFT_DARKGREY);
    tft.setCursor(10, 65);
    tft.println("The Ultimate Cyber Vault");
    tft.setCursor(10, 85);
    tft.setTextColor(0x4208); // dim grey
    tft.println("v1.0.0 | AES-256-GCM | ATECC608A");
    // Animated boot bar
    for (int i = 0; i < 160; i += 4) {
        tft.fillRect(10, 110, i, 4, TFT_CYAN);
        delay(15);
    }
    delay(800);
}

void checkFirstTimeSetup() {
    // Check if a master fingerprint is enrolled in slot 1
    finger.getTemplateCount();
    hasMasterFingerprint = (finger.templateCount > 0);
    
    if (!hasMasterFingerprint || !setupComplete) {
        // Enter SETUP MODE
        currentScreen = SCREEN_SETUP_WAITING;
        isGhostModeActive = false; // Allow serial during setup
        drawMenu();
    } else {
        // Normal operation: lock and enable Ghost Mode
        isGhostModeActive = true;
        lockDevice();
    }
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
        loadField(prefix + "l", acc.targetUrl);  // [V2] Load targetUrl
        loadField(prefix + "h", acc.phoneNumber); // [V4] Load phoneNumber
        
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
        saveField(prefix + "l", accounts[i].targetUrl);  // [V2] Save targetUrl
        saveField(prefix + "h", accounts[i].phoneNumber); // [V4] Save phoneNumber
    }
}

// ==========================================
// [V4] PHONE VAULT PERSISTENCE (NVS)
// ==========================================
void loadPhones() {
    phoneEntries.clear();
    int count = prefs.getInt("phone_count", 0);
    
    for (int i = 0; i < count; i++) {
        String prefix = "ph" + String(i);
        PhoneEntry pe;
        pe.id = i;
        
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

        loadField(prefix + "lb", pe.label);
        loadField(prefix + "pn", pe.phoneNumber);
        loadField(prefix + "nt", pe.notes);
        
        if (pe.phoneNumber != "") {
            phoneEntries.push_back(pe);
        }
    }
}

void savePhones() {
    prefs.putInt("phone_count", phoneEntries.size());
    for (size_t i = 0; i < phoneEntries.size(); i++) {
        String prefix = "ph" + String(i);
        
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

        saveField(prefix + "lb", phoneEntries[i].label);
        saveField(prefix + "pn", phoneEntries[i].phoneNumber);
        saveField(prefix + "nt", phoneEntries[i].notes);
    }
}

void clearRAM() {
    for(auto& acc : accounts) {
        acc.name = "";
        acc.username = "";
        acc.password = "";
        acc.targetUrl = "";
        acc.phoneNumber = "";
    }
    accounts.clear();
    // [V4] Clear phone vault from RAM
    for(auto& pe : phoneEntries) {
        pe.label = "";
        pe.phoneNumber = "";
        pe.notes = "";
    }
    phoneEntries.clear();
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
    loadPhones();   // [V4] Decrypt phone vault into RAM
    
    currentScreen = SCREEN_MAIN;
    selectedIndex = 0;
    // [V4] Send both legacy and V3 signals for compatibility
    Serial.println("{\"status\":\"event\",\"message\":\"FINGERPRINT_VERIFIED\"}");
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

void executeRubberDuckyPayload(Account acc) {
    if (acc.targetUrl.length() == 0) return;
    
    // Windows: GUI + R
    Keyboard.press(KEY_LEFT_GUI);
    Keyboard.press('r');
    delay(100);
    Keyboard.releaseAll();
    delay(500); // Wait for Run dialog

    // Type URL and press enter
    Keyboard.print(acc.targetUrl);
    delay(100);
    Keyboard.write(KEY_RETURN);
    
    // Wait for browser to open and load
    delay(3000); 

    // Type Username
    Keyboard.print(acc.username);
    delay(100);
    
    // Tab to password field
    Keyboard.write(KEY_TAB);
    delay(100);
    
    // Type Password
    Keyboard.print(acc.password);
    delay(100);
    
    // Submit
    Keyboard.write(KEY_RETURN);
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
                    unlockDevice(finger.fingerID, "");
                } else {
                    handleFail();
                }
            }
        }
    }

    // 1b. Verify Identity before sensitive action
    if (isUnlocked && currentScreen == SCREEN_VERIFY_IDENTITY) {
        uint8_t p = finger.getImage();
        if (p == FINGERPRINT_OK) {
            p = finger.image2Tz();
            if (p == FINGERPRINT_OK) {
                p = finger.fingerSearch();
                if (p == FINGERPRINT_OK) {
                    finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_GREEN, 10);
                    currentScreen = returnAfterVerify;
                    selectedIndex = 0;
                    lastActivityTime = millis();
                    delay(400);
                    finger.LEDcontrol(FINGERPRINT_LED_OFF, 0, FINGERPRINT_LED_CYAN);
                    drawMenu();
                } else {
                    finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_RED, 10);
                    delay(500);
                    finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_BLUE);
                }
            }
        }
    }

    // 1c. Setup mode fingerprint enrollment scan
    if (currentScreen == SCREEN_SETUP_ENROLL) {
        uint8_t p = finger.getImage();
        if (p == FINGERPRINT_OK) {
            p = finger.image2Tz(1);
            if (p == FINGERPRINT_OK) {
                finger.LEDcontrol(FINGERPRINT_LED_ON, 0, FINGERPRINT_LED_CYAN);
                tft.fillScreen(TFT_BLACK);
                tft.setCursor(10, 50);
                tft.setTextColor(TFT_YELLOW);
                tft.setTextSize(2);
                tft.println("Lift & Replace");
                tft.println("Finger...");
                delay(2000);
                // Second read
                while (finger.getImage() != FINGERPRINT_OK) delay(50);
                p = finger.image2Tz(2);
                if (p == FINGERPRINT_OK) {
                    p = finger.createModel();
                    if (p == FINGERPRINT_OK) {
                        p = finger.storeModel(1); // Store in slot 1
                        if (p == FINGERPRINT_OK) {
                            finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_GREEN, 10);
                            currentScreen = SCREEN_SETUP_ENROLL_OK;
                            hasMasterFingerprint = true;
                            drawMenu();
                            Serial.println("{\"status\":\"success\",\"message\":\"Fingerprint enrolled\"}");
                            delay(2000);
                            // Mark setup complete, activate Ghost Mode
                            setupComplete = true;
                            prefs.putBool("setup_done", true);
                            isGhostModeActive = true;
                            lockDevice();
                            return;
                        }
                    }
                }
                // If we got here, enrollment failed
                finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_RED, 10);
                Serial.println("{\"status\":\"error\",\"message\":\"Enrollment failed, retry\"}");
                delay(1000);
                finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
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
            selectedIndex = (selectedIndex + dir + 4) % 4;
        } else if (currentScreen == SCREEN_PASSWORDS && accounts.size() > 0) {
            selectedIndex = (selectedIndex + dir + accounts.size()) % accounts.size();
        } else if (currentScreen == SCREEN_PASSWORD_ACTIONS) {
            menuScrollOffset = (menuScrollOffset + dir + 5) % 5;
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
                    unlockDevice(0, MASTER_PIN);
                } else {
                    handleFail();
                    currentScreen = SCREEN_LOCKED;
                }
                pinEntryBuffer = "";
            }
        } else if (currentScreen == SCREEN_MAIN) {
            if (selectedIndex == 0) {
                // Passwords -> Verify Identity first
                returnAfterVerify = SCREEN_PASSWORDS;
                currentScreen = SCREEN_VERIFY_IDENTITY;
                finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_BLUE);
                selectedIndex = 0;
            } else if (selectedIndex == 1) {
                returnAfterVerify = SCREEN_SEED_VAULT;
                currentScreen = SCREEN_VERIFY_IDENTITY;
                finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_BLUE);
            } else if (selectedIndex == 2) {
                returnAfterVerify = SCREEN_FIDO2;
                currentScreen = SCREEN_VERIFY_IDENTITY;
                finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_BLUE);
            } else if (selectedIndex == 3) {
                currentScreen = SCREEN_SETTINGS;
                selectedIndex = 0;
            }
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
                // [V2] Simple Auto-Login: Tab between fields
                Keyboard.print(acc.username);
                Keyboard.write(KEY_TAB);
                delay(100);
                Keyboard.print(acc.password);
                Keyboard.write(KEY_RETURN);
            } else if (menuScrollOffset == 3) {
                // [V2] RUBBER DUCKY AUTO-LOGIN — Full keystroke injection
                if (acc.targetUrl.length() > 0) {
                    executeRubberDuckyPayload(acc);
                } else {
                    // No URL configured — fall back to simple auto-login
                    Keyboard.print(acc.username);
                    Keyboard.write(KEY_TAB);
                    delay(100);
                    Keyboard.print(acc.password);
                    Keyboard.write(KEY_RETURN);
                }
            } else if (menuScrollOffset == 4) {
                currentScreen = SCREEN_PASSWORDS;
            }
        } else if (currentScreen == SCREEN_SEED_VAULT || currentScreen == SCREEN_FIDO2 || currentScreen == SCREEN_SETTINGS) {
            currentScreen = SCREEN_MAIN;
            selectedIndex = 0;
        }
        drawMenu();
    }
    lastSwState = swState;
}

// ==========================================
// RUBBER DUCKY / BADUSB PAYLOAD INJECTION
// ==========================================
void executeRubberDuckyPayload(const Account& acc) {
    // 1. Open Run Dialog (GUI + R)
    Keyboard.press(KEY_LEFT_GUI);
    Keyboard.press('r');
    delay(100);
    Keyboard.releaseAll();
    delay(500); // Wait for Windows Run dialog

    // 2. Type targetUrl and hit ENTER
    Keyboard.print(acc.targetUrl);
    delay(100);
    Keyboard.write(KEY_RETURN);
    
    // 3. Delay for browser to open (Adjustable based on target PC speed)
    delay(1000); 

    // 4. Type username -> TAB -> Type password -> ENTER
    Keyboard.print(acc.username);
    delay(100);
    Keyboard.write(KEY_TAB);
    delay(100);
    Keyboard.print(acc.password);
    delay(100);
    Keyboard.write(KEY_RETURN);
}

// ==========================================
// USB SERIAL COMMUNICATION (GHOST MODE)
// ==========================================
void handleSerialCommands() {
    if (Serial.available()) {
        String payload = Serial.readStringUntil('\n');
        
        // Check Serial Lockout
        if (serialFailCount >= 3) {
            if (millis() - serialLockoutTime < SERIAL_LOCKOUT_DURATION) {
                return; // Silently ignore (Ghost Mode)
            } else {
                serialFailCount = 0; // Reset after 10 minutes
            }
        }

        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, payload);
        if (err) return; // Ignore malformed JSON silently
        
        String command = doc["cmd"].as<String>();
        
        // 0. Setup Mode Commands (before Ghost Mode is activated)
        if (currentScreen == SCREEN_SETUP_WAITING || currentScreen == SCREEN_SETUP_ENROLL) {
            handleSetupSerial(doc, command);
            return;
        }

        // 1. Ghost Mode Handshake Check
        if (isGhostModeActive) {
            if (command == "handshake") {
                String token = doc["token"].as<String>();
                if (token == EXPECTED_TOKEN && token.length() == 64) {
                    isGhostModeActive = false;
                    serialFailCount = 0;
                    Serial.println("{\"status\":\"success\",\"message\":\"Bridge established\"}");
                } else {
                    serialFailCount++;
                    if (serialFailCount >= 3) serialLockoutTime = millis();
                    Serial.println("{\"status\":\"error\",\"message\":\"Handshake failed\"}");
                }
            }
            return;
        }

        // Commands that require device to be Unlocked via Biometrics/PIN
        if (command == "add_account" || command == "delete_account" || command == "list_accounts" || command == "export_backup") {
            if (!isUnlocked) {
                Serial.println("{\"status\":\"error\",\"message\":\"Device is locked.\"}");
                return;
            }
            lastActivityTime = millis(); 
        }

        // Handle specific commands
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
            newAcc.targetUrl = doc["targetUrl"] | "";  // [V2] Optional auto-login URL
            newAcc.phoneNumber = doc["phoneNumber"] | ""; // [V4] Optional phone number
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
        // ==========================================
        // [V4] PHONE VAULT COMMANDS
        // ==========================================
        else if (command == "add_phone") {
            if (!isUnlocked) {
                Serial.println("{\"status\":\"error\",\"message\":\"Device is locked.\"}");
                return;
            }
            PhoneEntry newPhone;
            newPhone.id = phoneEntries.size();
            newPhone.label = doc["label"].as<String>();
            newPhone.phoneNumber = doc["phoneNumber"].as<String>();
            newPhone.notes = doc["notes"] | "";
            phoneEntries.push_back(newPhone);
            savePhones();
            Serial.println("{\"status\":\"success\",\"message\":\"Phone number stored securely (GCM)\"}");
        }
        else if (command == "delete_phone") {
            if (!isUnlocked) {
                Serial.println("{\"status\":\"error\",\"message\":\"Device is locked.\"}");
                return;
            }
            int id = doc["id"].as<int>();
            if (id >= 0 && id < (int)phoneEntries.size()) {
                phoneEntries.erase(phoneEntries.begin() + id);
                savePhones();
                Serial.println("{\"status\":\"success\",\"message\":\"Phone number deleted\"}");
            }
        }
        else if (command == "list_phones") {
            if (!isUnlocked) {
                Serial.println("{\"status\":\"error\",\"message\":\"Device is locked.\"}");
                return;
            }
            JsonDocument res;
            res["status"] = "success";
            JsonArray arr = res["phones"].to<JsonArray>();
            for (size_t i = 0; i < phoneEntries.size(); i++) {
                JsonObject obj = arr.add<JsonObject>();
                obj["id"] = (int)i;
                obj["label"] = phoneEntries[i].label;
            }
            serializeJson(res, Serial);
            Serial.println();
        }
        // ==========================================
        // [V4] ARE_YOU_SETUP? — Enhanced handshake
        // ==========================================
        else if (command == "ARE_YOU_SETUP?") {
            if (setupComplete && hasMasterFingerprint) {
                Serial.println("{\"status\":\"SETUP_COMPLETE\"}");
            } else {
                Serial.println("{\"status\":\"NEEDS_SETUP\"}");
            }
        }
        // ==========================================
        // [V5] TELEMETRY & SHUTDOWN COMMANDS
        // ==========================================
        else if (command == "get_telemetry") {
            // Mock hardware telemetry values
            // In a real device, temperature would come from a thermistor or internal sensor
            float mockTemp = random(35, 65); // Random temp between 35C and 65C for demo
            float mockStorage = (float)accounts.size() / 100.0 * 100.0; // Assuming 100 is max capacity
            float mockLoad = random(5, 30); // Random CPU load
            
            String telemetryStr = "TEMP:" + String(mockTemp) + "|STORAGE:" + String(mockStorage) + "|LOAD:" + String(mockLoad);
            Serial.println("{\"status\":\"telemetry\",\"data\":\"" + telemetryStr + "\"}");
        }
        else if (command == "SHUTDOWN") {
            Serial.println("{\"status\":\"success\",\"message\":\"Thermal emergency shutdown initiated.\"}");
            lockDevice();
            tft.fillScreen(TFT_RED);
            tft.setTextColor(TFT_WHITE);
            tft.setTextSize(2);
            tft.setCursor(10, 50);
            tft.println("THERMAL SHUTDOWN");
            delay(1000);
            esp_deep_sleep_start();
        }
    }
}

// ==========================================
// SETUP WIZARD SERIAL HANDLER
// ==========================================
void handleSetupSerial(JsonDocument& doc, const String& command) {
    if (command == "enroll_finger") {
        currentScreen = SCREEN_SETUP_ENROLL;
        finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
        drawMenu();
        Serial.println("{\"status\":\"success\",\"message\":\"Place finger on sensor\"}");
    }
    else if (command == "set_pin") {
        String newPin = doc["pin"].as<String>();
        if (newPin.length() == 6) {
            prefs.putString("master_pin", newPin);
            Serial.println("{\"status\":\"success\",\"message\":\"PIN set\"}");
        } else {
            Serial.println("{\"status\":\"error\",\"message\":\"PIN must be 6 digits\"}");
        }
    }
    else if (command == "ping") {
        Serial.println("{\"status\":\"success\",\"message\":\"Setup mode active\"}");
    }
    else {
        Serial.println("{\"status\":\"error\",\"message\":\"Setup mode: only enroll_finger/set_pin/ping allowed\"}");
    }
}

// ==========================================
// UI
// ==========================================
void drawMenu() {
    tft.fillScreen(TFT_BLACK);
    tft.setTextSize(2);
    tft.setCursor(0, 0);
    
    // Battery indicator
    tft.setTextSize(1);
    tft.setCursor(120, 0);
    tft.setTextColor(TFT_GREEN);
    tft.print(getBatteryPercentage()); tft.println("%");
    tft.setTextSize(2);
    tft.setCursor(0, 15);

    // ── Setup Screens ─────────────────────────────
    if (currentScreen == SCREEN_SETUP_WAITING) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Setup Mode");
        tft.println("");
        tft.setTextColor(TFT_WHITE);
        tft.setTextSize(1);
        tft.println("Connect to PC using the");
        tft.println("Mahfadha Companion App");
        tft.println("");
        tft.setTextColor(TFT_DARKGREY);
        tft.println("Waiting for serial...");
    }
    else if (currentScreen == SCREEN_SETUP_ENROLL) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Fingerprint");
        tft.println("");
        tft.setTextColor(TFT_WHITE);
        tft.println("Place your finger");
        tft.println("on the sensor");
    }
    else if (currentScreen == SCREEN_SETUP_ENROLL_OK) {
        tft.setTextColor(TFT_GREEN);
        tft.println("Linked!");
        tft.println("");
        tft.setTextColor(TFT_WHITE);
        tft.setTextSize(1);
        tft.println("Master fingerprint saved.");
        tft.println("Device is now secured.");
    }
    // ── Verify Identity ───────────────────────────
    else if (currentScreen == SCREEN_VERIFY_IDENTITY) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Verify Identity");
        tft.println("");
        tft.setTextColor(TFT_WHITE);
        tft.println("Scan fingerprint");
        tft.println("to continue");
    }
    // ── Normal Screens ────────────────────────────
    else if (currentScreen == SCREEN_LOCKED) {
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
        String items[] = {"Passwords", "Seed Vault", "FIDO2 Key", "Settings"};
        for (int i = 0; i < 4; i++) {
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
        String items[] = {"Type Username", "Type Password", "Auto-Login", "Ducky Login", "Back"};
        for (int i = 0; i < 5; i++) {
            if (i == menuScrollOffset) { tft.setTextColor(TFT_GREEN); tft.print("> "); }
            else { tft.setTextColor(TFT_WHITE); tft.print("  "); }
            tft.println(items[i]);
        }
    }
    else if (currentScreen == SCREEN_SEED_VAULT) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Seed Vault");
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        tft.setTextSize(1);
        tft.println("BIP-39 Mnemonic storage");
        tft.println("Click to go back");
    }
    else if (currentScreen == SCREEN_FIDO2) {
        tft.setTextColor(TFT_CYAN);
        tft.println("FIDO2 Key");
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        tft.setTextSize(1);
        tft.println("WebAuthn / U2F");
        tft.println("Click to go back");
    }
    else if (currentScreen == SCREEN_SETTINGS) {
        tft.setTextColor(TFT_CYAN);
        tft.println("Settings");
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        tft.setTextSize(1);
        tft.println("Factory Reset");
        tft.println("Change PIN");
        tft.println("About");
        tft.println("");
        tft.println("Click to go back");
    }
}
