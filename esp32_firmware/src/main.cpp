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

// ==========================================
// CONFIGURATION & SECURE PARAMETERS
// ==========================================
#define BTN_OK_UP   0
#define BTN_DOWN    14
const unsigned long DEBOUNCE_MS = 180;
const int MAX_ACCOUNTS = 100;

// AES-256 Master Key (MUST be derived from a secure PIN/Hardware Secure Element in production)
// This is a 32-byte key for demonstration purposes.
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

struct Account {
    int id;
    String name;
    String username;
    String password;
    String totpSecret;
};

std::vector<Account> accounts;

enum MenuScreen { SCREEN_MAIN, SCREEN_PASSWORDS, SCREEN_PASSWORD_ACTIONS, SCREEN_TOTP, SCREEN_SETTINGS };
MenuScreen currentScreen = SCREEN_MAIN;
int selectedIndex = 0;
int menuScrollOffset = 0;

// ==========================================
// FUNCTION PROTOTYPES
// ==========================================
void encryptData(const String& plaintext, uint8_t* output, size_t& outLen);
String decryptData(const uint8_t* ciphertext, size_t len);
void loadAccounts();
void saveAccounts();
void handleSerialCommands();
void drawMenu();
void handleButtons();
String generateTOTPCode(String base32Secret);

// ==========================================
// SETUP
// ==========================================
void setup() {
    Serial.begin(115200); // 1. Secure USB Serial ONLY
    
    // UI Init
    tft.init();
    tft.setRotation(1);
    tft.fillScreen(TFT_BLACK);
    
    // Buttons
    pinMode(BTN_OK_UP, INPUT_PULLUP);
    pinMode(BTN_DOWN, INPUT_PULLUP);

    // Keyboard (USB HID)
    Keyboard.begin();
    USB.begin();
    
    // RTC (Hardware Time)
    if (!rtc.begin()) {
        Serial.println("{\"status\":\"error\",\"message\":\"RTC module not found\"}");
    }
    
    // Load Encrypted Data
    prefs.begin("mahfadha", false);
    loadAccounts();
    
    drawMenu();
}

// ==========================================
// MAIN LOOP
// ==========================================
void loop() {
    handleSerialCommands();
    handleButtons();
    delay(20);
}

// ==========================================
// MILITARY-GRADE ENCRYPTION (AES-256 CBC)
// ==========================================
void encryptData(const String& plaintext, uint8_t* output, size_t& outLen) {
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, MASTER_AES_KEY, 256);
    
    size_t len = plaintext.length();
    size_t paddedLen = len + (16 - (len % 16)); // PKCS7 Padding
    outLen = paddedLen;
    
    uint8_t input[paddedLen];
    memset(input, (16 - (len % 16)), paddedLen); 
    memcpy(input, plaintext.c_str(), len);
    
    uint8_t iv[16] = {0}; // Note: For production, generate random IV per encryption and store it with ciphertext
    
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
    if (padVal > 16) return ""; // Invalid padding
    
    size_t unpaddedLen = len - padVal;
    String result = "";
    for(size_t i = 0; i < unpaddedLen; i++) {
        result += (char)output[i];
    }
    return result;
}

// ==========================================
// DYNAMIC DATA HANDLING (NVM)
// ==========================================
void loadAccounts() {
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
        
        size_t tLen = prefs.getBytesLength((prefix + "_t").c_str());
        if (tLen > 0) {
            uint8_t buf[tLen];
            prefs.getBytes((prefix + "_t").c_str(), buf, tLen);
            acc.totpSecret = decryptData(buf, tLen);
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
        
        encryptData(accounts[i].totpSecret, out, outLen);
        prefs.putBytes((prefix + "_t").c_str(), out, outLen);
    }
}

// ==========================================
// USB SERIAL COMMUNICATION (COMPANION APP)
// ==========================================
void handleSerialCommands() {
    if (Serial.available()) {
        String payload = Serial.readStringUntil('\n');
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, payload);
        
        if (err) {
            Serial.println("{\"status\":\"error\",\"message\":\"Invalid JSON\"}");
            return;
        }
        
        String command = doc["cmd"].as<String>();
        
        // 1. Sync Time Command
        if (command == "sync_time") {
            uint32_t unixtime = doc["time"].as<uint32_t>();
            rtc.adjust(DateTime(unixtime));
            Serial.println("{\"status\":\"success\",\"message\":\"Hardware RTC time synced\"}");
        }
        // 2. Add Account Command
        else if (command == "add_account") {
            if (accounts.size() >= MAX_ACCOUNTS) {
                Serial.println("{\"status\":\"error\",\"message\":\"Max capacity reached (100)\"}");
                return;
            }
            Account newAcc;
            newAcc.id = accounts.size();
            newAcc.name = doc["name"].as<String>();
            newAcc.username = doc["username"].as<String>();
            newAcc.password = doc["password"].as<String>();
            newAcc.totpSecret = doc["totp_secret"].as<String>();
            
            accounts.push_back(newAcc);
            saveAccounts();
            Serial.println("{\"status\":\"success\",\"message\":\"Account securely encrypted and saved\"}");
            drawMenu();
        }
        // 3. Delete Account Command
        else if (command == "delete_account") {
            int id = doc["id"].as<int>();
            if (id >= 0 && id < accounts.size()) {
                accounts.erase(accounts.begin() + id);
                saveAccounts();
                Serial.println("{\"status\":\"success\",\"message\":\"Account deleted\"}");
                drawMenu();
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Invalid Account ID\"}");
            }
        }
        // 4. List Accounts Command
        else if (command == "list_accounts") {
            JsonDocument res;
            res["status"] = "success";
            JsonArray arr = res["accounts"].to<JsonArray>();
            for (size_t i = 0; i < accounts.size(); i++) {
                JsonObject obj = arr.add<JsonObject>();
                obj["id"] = i;
                obj["name"] = accounts[i].name; 
                // We DO NOT send passwords back to the PC to maintain zero-trust
            }
            serializeJson(res, Serial);
            Serial.println();
        }
    }
}

// ==========================================
// CORE USB HID & OFFLINE UI LOGIC
// ==========================================
void drawMenu() {
    tft.fillScreen(TFT_BLACK);
    tft.setTextSize(2);
    tft.setCursor(0, 0);
    
    if (currentScreen == SCREEN_MAIN) {
        tft.setTextColor(TFT_ORANGE);
        tft.println("Mahfadha Pro");
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

void handleButtons() {
    static unsigned long lastBtnTime = 0;
    if (millis() - lastBtnTime < DEBOUNCE_MS) return;
    
    bool okPressed = digitalRead(BTN_OK_UP) == LOW;
    bool downPressed = digitalRead(BTN_DOWN) == LOW;
    
    if (downPressed) {
        lastBtnTime = millis();
        if (currentScreen == SCREEN_MAIN) {
            selectedIndex = (selectedIndex + 1) % 3;
        } else if (currentScreen == SCREEN_PASSWORDS) {
            if (accounts.size() > 0) selectedIndex = (selectedIndex + 1) % accounts.size();
        } else if (currentScreen == SCREEN_PASSWORD_ACTIONS) {
            menuScrollOffset = (menuScrollOffset + 1) % 4;
        }
        drawMenu();
    }
    
    if (okPressed) {
        lastBtnTime = millis();
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
                Keyboard.print(acc.username); // Type Username
            } else if (menuScrollOffset == 1) {
                Keyboard.print(acc.password); // Type Password
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
}
