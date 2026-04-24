#!/usr/bin/env python3
"""
Mahfadha Pro Secure CLI Bridge
Version: 1.0 (2026)
Description: Zero-knowledge secure middleware for ESP32-S3 Hardware Wallet.
"""

import argparse
import serial
import time
import sys
import json
import hashlib
from getpass import getpass

# In production, this should be a dynamic salt derived from the ATECC608A serial number.
APP_SECRET_SALT = "MAHFADHA_GHOST_PROTOCOL_V1_2026"

def generate_handshake_token(master_password):
    """Generates a 64-character SHA-256 token."""
    raw = f"{master_password}:{APP_SECRET_SALT}"
    return hashlib.sha256(raw.encode()).hexdigest()

def connect_to_device(port, token):
    print(f"[*] Attempting Ghost Mode handshake on {port}...")
    try:
        # The ESP32 ignores all data unless the token is exactly correct.
        ser = serial.Serial(port, 115200, timeout=2)
        time.sleep(2) # Wait for serial port to stabilize
        
        # Send Handshake Protocol Initiation
        payload = json.dumps({"cmd": "handshake", "token": token}) + "\n"
        ser.write(payload.encode())
        
        # Await ESP32 Response
        response = ser.readline().decode('utf-8').strip()
        
        if not response:
            print("[!] Timeout. Device is ignoring us (Ghost Mode Active).")
            return None
            
        try:
            res_json = json.loads(response)
            if res_json.get("status") == "success":
                print("[+] Handshake ACCEPTED. Secure bridge established.")
                return ser
            elif res_json.get("status") == "error":
                print(f"[-] Handshake REJECTED. Error: {res_json.get('message')}")
                return None
        except json.JSONDecodeError:
             print("[-] Received garbage data. Handshake failed.")
             return None
             
    except serial.SerialException as e:
        print(f"[!] Serial connection error: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Mahfadha Pro Secure CLI Bridge")
    parser.add_argument("--connect", action="store_true", help="Connect to the device")
    parser.add_argument("--port", type=str, required=True, help="COM/TTY port")
    parser.add_argument("--session-auth", action="store_true", help="Authenticate session interactively")
    parser.add_argument("--token", type=str, help="64-character Token (Bypasses interactive prompt)")
    
    args = parser.parse_args()
    
    if args.connect:
        token = args.token
        if args.session_auth and not token:
            pwd = getpass("Enter Mahfadha Master Password: ")
            token = generate_handshake_token(pwd)
            
        if not token or len(token) != 64:
            print("[!] Error: A valid 64-character SHA-256 token is required.")
            sys.exit(1)
            
        ser = connect_to_device(args.port, token)
        if ser:
            print("[*] Bridge Active. Pipe commands (JSON format) from Flutter App...")
            print("[*] Type 'exit' to quit bridge.")
            
            # Simple REPL for testing or piping from Flutter
            while True:
                try:
                    cmd_in = input("bridge> ")
                    if cmd_in.lower() == 'exit':
                        break
                    if cmd_in.strip() == "":
                        continue
                        
                    ser.write((cmd_in + "\n").encode())
                    res = ser.readline().decode('utf-8').strip()
                    print(f"device: {res}")
                    
                except KeyboardInterrupt:
                    break
                except Exception as e:
                    print(f"[!] Connection lost: {e}")
                    break
            
            ser.close()
            print("[*] Bridge Closed.")

if __name__ == "__main__":
    main()
