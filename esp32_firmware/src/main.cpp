#include <Arduino.h>
#include <TFT_eSPI.h>
#include <Preferences.h>
#include <RTClib.h>
#include <TOTP.h>
#include <ArduinoJson.h>
#include "USB.h"
#include "USBHIDKeyboard.h"
#include "mbedtls/aes.h"
#include <vector>
#include <Adafruit_Fingerprint.h>
#include <ESP32Encoder.h>

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

const int MAX_ACCOUNTS = 100;
const unsigned long IDLE_TIMEOUT_MS = 60000; // 60 seconds
unsigned long lastActivityTime = 0;

// AES-256 Master Key (MUST be derived from a secure PIN/Hardware Secure Element in production)
const uint8_t MASTER_AES_KEY[32] = {
    0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, 0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C,
    0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, 0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C
};

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

struct Account {
    int id;
    String name;
    String username;
    String password;
    String totpSecret;
};

std::vector<Account> accounts;

enum MenuScreen { SCREEN_LOCKED, SCREEN_MAIN, SCREEN_PASSWORDS, SCREEN_PASSWORD_ACTIONS, SCREEN_TOTP, SCREEN_SETTINGS };
MenuScreen currentScreen = SCREEN_LOCKED;
int selectedIndex = 0;
int menuScrollOffset = 0;
long lastEncoderPosition = 0;
bool isUnlocked = false;

// ==========================================
// FUNCTION PROTOTYPES
// ==========================================
void encryptData(const String& plaintext, uint8_t* output, size_t& outLen);
String decryptData(const uint8_t* ciphertext, size_t len);
void loadAccounts();
void clearRAM();
void lockDevice();
void unlockDevice();
void handleSerialCommands();
void drawMenu();
void handleEncoderAndFingerprint();

// ==========================================
// SETUP
// ==========================================
void setup() {
    Serial.begin(115200); // Secure USB Serial ONLY
    
    // UI Init
    tft.init();
    tft.setRotation(1);
    tft.fillScreen(TFT_BLACK);
    
    // Rotary Encoder
    ESP32Encoder::useInternalWeakPullResistors = UP;
    encoder.attachHalfQuad(ENC_A, ENC_B);
    encoder.setCount(0);
    pinMode(ENC_SW, INPUT_PULLUP);

    // Keyboard (USB HID)
    Keyboard.begin();
    USB.begin();
    
    // RTC (Hardware Time)
    rtc.begin();
    
    // Preferences (NVM)
    prefs.begin("mahfadha", false);

    // Fingerprint Sensor
    fpSerial.begin(57600, SERIAL_8N1, FP_RX_PIN, FP_TX_PIN);
    finger.begin(57600);
    if (finger.verifyPassword()) {
        // Init Cyan LED: Breathing, speed 100, color 2 (Cyan)
        finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
    }

    lastActivityTime = millis();
    lockDevice(); // Ensure locked on boot
}

// ==========================================
// MAIN LOOP
// ==========================================
void loop() {
    handleSerialCommands();
    handleEncoderAndFingerprint();
    
    // Idle Timeout Logic
    if (isUnlocked && (millis() - lastActivityTime > IDLE_TIMEOUT_MS)) {
        lockDevice();
    }
    
    delay(10);
}

// ==========================================
// SECURITY & DATA HANDLING
// ==========================================
void encryptData(const String& plaintext, uint8_t* output, size_t& outLen) {
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, MASTER_AES_KEY, 256);
    size_t len = plaintext.length();
    size_t paddedLen = len + (16 - (len % 16));
    outLen = paddedLen;
    uint8_t input[paddedLen];
    memset(input, (16 - (len % 16)), paddedLen); 
    memcpy(input, plaintext.c_str(), len);
    uint8_t iv[16] = {0}; 
    mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_ENCRYPT, paddedLen, iv, input, output);
    mbedtls_aes_free(&aes);
}

String decryptData(const uint8_t* ciphertext, size_t len) {
    if (len == 0 || len % 16 != 0) return "";
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_dec(&aes, MASTER_AES_KEY, 256);
    uint8_t iv[16] = {0};
    uint8_t output[len];
    mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_DECRYPT, len, iv, ciphertext, output);
    mbedtls_aes_free(&aes);
    uint8_t padVal = output[len - 1];
    if (padVal > 16) return "";
    size_t unpaddedLen = len - padVal;
    String result = "";
    for(size_t i = 0; i < unpaddedLen; i++) {
        result += (char)output[i];
    }
    return result;
}

void loadAccounts() {
    // CRITICAL: Decrypts NVM storage to Volatile RAM ONLY if Unlocked
    accounts.clear();
    int count = prefs.getInt("acc_count", 0);
    for (int i = 0; i < count; i++) {
        String prefix = "a" + String(i);
        Account acc;
        acc.id = i;
        
        size_t nLen = prefs.getBytesLength((prefix + "_n").c_str());
        if (nLen > 0) {
            uint8_t buf[nLen];
            prefs.getBytes((prefix + "_n").c_str(), buf, nLen);
            acc.name = decryptData(buf, nLen);
        }
        size_t uLen = prefs.getBytesLength((prefix + "_u").c_str());
        if (uLen > 0) {
            uint8_t buf[uLen];
            prefs.getBytes((prefix + "_u").c_str(), buf, uLen);
            acc.username = decryptData(buf, uLen);
        }
        size_t pLen = prefs.getBytesLength((prefix + "_p").c_str());
        if (pLen > 0) {
            uint8_t buf[pLen];
            prefs.getBytes((prefix + "_p").c_str(), buf, pLen);
            acc.password = decryptData(buf, pLen);
        }
        accounts.push_back(acc);
    }
}

void saveAccounts() {
    prefs.putInt("acc_count", accounts.size());
    for (size_t i = 0; i < accounts.size(); i++) {
        String prefix = "a" + String(i);
        uint8_t out[256];
        size_t outLen;
        encryptData(accounts[i].name, out, outLen);
        prefs.putBytes((prefix + "_n").c_str(), out, outLen);
        encryptData(accounts[i].username, out, outLen);
        prefs.putBytes((prefix + "_u").c_str(), out, outLen);
        encryptData(accounts[i].password, out, outLen);
        prefs.putBytes((prefix + "_p").c_str(), out, outLen);
    }
}

void clearRAM() {
    for(auto& acc : accounts) {
        acc.name = "";
        acc.username = "";
        acc.password = "";
        acc.totpSecret = "";
    }
    accounts.clear();
}

void lockDevice() {
    isUnlocked = false;
    currentScreen = SCREEN_LOCKED;
    clearRAM();
    finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
    Serial.println("{\"status\":\"event\",\"message\":\"BIOMETRIC_LOCKED\"}");
    drawMenu();
}

void unlockDevice() {
    isUnlocked = true;
    lastActivityTime = millis();
    finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_GREEN, 10);
    loadAccounts(); // Decrypt into RAM
    currentScreen = SCREEN_MAIN;
    selectedIndex = 0;
    Serial.println("{\"status\":\"event\",\"message\":\"BIOMETRIC_UNLOCKED\"}");
    delay(500); // Show green led briefly
    finger.LEDcontrol(FINGERPRINT_LED_OFF, 0, FINGERPRINT_LED_CYAN); // Turn off LED to save power
    drawMenu();
}

// ==========================================
// SYSTEM FLOW & NAVIGATION
// ==========================================
void handleEncoderAndFingerprint() {
    // 1. Biometric Check (if locked)
    if (!isUnlocked) {
        uint8_t p = finger.getImage();
        if (p == FINGERPRINT_OK) {
            p = finger.image2Tz();
            if (p == FINGERPRINT_OK) {
                p = finger.fingerSearch();
                if (p == FINGERPRINT_OK) {
                    unlockDevice();
                } else {
                    finger.LEDcontrol(FINGERPRINT_LED_FLASHING, 25, FINGERPRINT_LED_RED, 10);
                    delay(500);
                    finger.LEDcontrol(FINGERPRINT_LED_BREATHING, 100, FINGERPRINT_LED_CYAN);
                }
            }
        }
        return; // Don't process encoder if locked
    }

    // 2. Rotary Encoder Scroll
    long currentPos = encoder.getCount() / 2; // Adjust step resolution
    if (currentPos != lastEncoderPosition) {
        lastActivityTime = millis();
        int dir = (currentPos > lastEncoderPosition) ? 1 : -1;
        lastEncoderPosition = currentPos;

        if (currentScreen == SCREEN_MAIN) {
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
    if (swState == LOW && lastSwState == HIGH) { // Button Pressed
        lastActivityTime = millis();
        
        if (currentScreen == SCREEN_MAIN) {
            if (selectedIndex == 0) { currentScreen = SCREEN_PASSWORDS; selectedIndex = 0; }
        } else if (currentScreen == SCREEN_PASSWORDS) {
            if (accounts.size() > 0) {
                currentScreen = SCREEN_PASSWORD_ACTIONS;
                menuScrollOffset = 0;
            }
        } else if (currentScreen == SCREEN_PASSWORD_ACTIONS) {
            Account acc = accounts[selectedIndex];
            if (menuScrollOffset == 0) {
                Keyboard.print(acc.username);
            } else if (menuScrollOffset == 1) {
                Keyboard.print(acc.password);
            } else if (menuScrollOffset == 2) {
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
        
        // Commands that require unlock
        if (command == "add_account" || command == "delete_account" || command == "list_accounts") {
            if (!isUnlocked) {
                Serial.println("{\"status\":\"error\",\"message\":\"Device is locked. Scan Fingerprint first.\"}");
                return;
            }
            lastActivityTime = millis(); // Refresh idle timer
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
            Serial.println("{\"status\":\"success\",\"message\":\"Account added\"}");
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
    }
}

// ==========================================
// OFFLINE UI LOGIC
// ==========================================
void drawMenu() {
    tft.fillScreen(TFT_BLACK);
    tft.setTextSize(2);
    tft.setCursor(0, 0);
    
    if (currentScreen == SCREEN_LOCKED) {
        tft.setTextColor(TFT_ORANGE);
        tft.println("Mahfadha Pro");
        tft.println("");
        tft.setTextColor(TFT_CYAN);
        tft.println("Device Locked");
        tft.setTextColor(TFT_WHITE);
        tft.println("");
        tft.println("Scan Fingerprint");
        tft.println("to Unlock...");
    }
    else if (currentScreen == SCREEN_MAIN) {
        tft.setTextColor(TFT_ORANGE);
        tft.println("Mahfadha Pro (Unlocked)");
        tft.setTextColor(TFT_WHITE);
        tft.println("----------------");
        String items[] = {"Passwords", "TOTP Generator", "Settings"};
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
        String items[] = {"Type Username", "Type Password", "Auto-Login (U/T/P)", "Back"};
        for (int i = 0; i < 4; i++) {
            if (i == menuScrollOffset) { tft.setTextColor(TFT_GREEN); tft.print("> "); }
            else { tft.setTextColor(TFT_WHITE); tft.print("  "); }
            tft.println(items[i]);
        }
    }
}
