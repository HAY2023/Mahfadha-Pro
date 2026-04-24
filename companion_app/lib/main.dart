import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

void main() {
  runApp(const MahfadhaApp());
}

class MahfadhaApp extends StatelessWidget {
  const MahfadhaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mahfadha Pro Companion',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  SerialPort? _port;
  String _status = "Disconnected";

  void _connectDevice(String portName) {
    try {
      if (_port != null && _port!.isOpen) {
        _port!.close();
      }
      
      _port = SerialPort(portName);
      if (_port!.openReadWrite()) {
        setState(() {
          _status = "Connected to $portName (Awaiting Biometric Unlock)";
        });
        
        final reader = SerialPortReader(_port!);
        reader.stream.listen((data) {
          try {
            String message = utf8.decode(data).trim();
            if (message.isNotEmpty) {
              final json = jsonDecode(message);
              if (json['status'] == 'event') {
                if (json['message'] == 'BIOMETRIC_UNLOCKED') {
                  setState(() {
                    _status = "Connected & UNLOCKED 🟢";
                  });
                } else if (json['message'] == 'BIOMETRIC_LOCKED') {
                  setState(() {
                    _status = "Connected & LOCKED 🔴 (Scan Finger)";
                  });
                }
              } else if (json['status'] == 'error') {
                 print("Error from device: ${json['message']}");
                 // Could show a snackbar here using a global key, but print is fine for now
              }
            }
          } catch (e) {
            // Ignore non-json debug messages
            print("Serial Data: ${utf8.decode(data)}");
          }
        });
        
      } else {
        setState(() {
          _status = "Failed to open $portName";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Connection Error: $e";
      });
    }
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_port == null || !_port!.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to Mahfadha Pro first.')),
      );
      return;
    }
    
    try {
      String jsonString = jsonEncode(command) + "\n";
      _port!.write(Uint8List.fromList(utf8.encode(jsonString)));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Command sent: ${command["cmd"]}')),
      );
    } catch (e) {
      setState(() {
        _status = "Write Error: $e";
      });
    }
  }

  // --- COMPANION APP TO ESP32 COMMANDS ---

  void _syncTime() {
    int unixTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _sendCommand({
      "cmd": "sync_time",
      "time": unixTime,
    });
  }

  void _addAccount() {
    _sendCommand({
      "cmd": "add_account",
      "name": "Admin Portal",
      "username": "sysadmin@secure.mil",
      "password": "UltraSecurePassword99!!",
      "totp_secret": "JBSWY3DPEHPK3PXP" // Example Base32
    });
  }

  void _deleteAccount() {
    _sendCommand({
      "cmd": "delete_account",
      "id": 0
    });
  }

  void _listAccounts() {
    _sendCommand({
      "cmd": "list_accounts"
    });
  }

  @override
  void dispose() {
    if (_port != null && _port!.isOpen) {
      _port!.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<String> availablePorts = [];
    try {
      availablePorts = SerialPort.availablePorts;
    } catch (e) {
      // Handle platforms where serial port might not be supported (like web)
      print("Serial ports not available: $e");
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mahfadha Pro Command Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            tooltip: 'Refresh USB Ports',
            onPressed: () {
              setState(() {});
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    _status.contains("Connected") ? Icons.lock_outline : Icons.lock_open,
                    color: _status.contains("Connected") ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "Device Status: $_status",
                    style: TextStyle(
                      fontSize: 16,
                      color: _status.contains("Connected") ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.bold
                    )
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              "Available USB Devices:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)
            ),
            const SizedBox(height: 10),
            
            Expanded(
              flex: 1,
              child: availablePorts.isEmpty 
                ? const Center(child: Text("No USB devices found.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: availablePorts.length,
                    itemBuilder: (context, index) {
                      String port = availablePorts[index];
                      return Card(
                        color: const Color(0xFF2A2A2A),
                        child: ListTile(
                          leading: const Icon(Icons.usb, color: Colors.white54),
                          title: Text(port, style: const TextStyle(color: Colors.white)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[800],
                            ),
                            onPressed: () => _connectDevice(port),
                            child: const Text("Connect"),
                          ),
                        ),
                      );
                    },
                  ),
            ),
            
            const Divider(color: Colors.white24, height: 40),
            
            const Text(
              "Secure Operations:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)
            ),
            const SizedBox(height: 10),
            
            Expanded(
              flex: 2,
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 2.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildActionButton(
                    icon: Icons.sync,
                    label: "Sync Time (RTC)",
                    color: Colors.blue[700]!,
                    onPressed: _syncTime,
                  ),
                  _buildActionButton(
                    icon: Icons.add_moderator,
                    label: "Add Encrypted Entry",
                    color: Colors.green[700]!,
                    onPressed: _addAccount,
                  ),
                  _buildActionButton(
                    icon: Icons.list_alt,
                    label: "List Accounts",
                    color: Colors.purple[700]!,
                    onPressed: _listAccounts,
                  ),
                  _buildActionButton(
                    icon: Icons.delete_forever,
                    label: "Delete Entry (ID 0)",
                    color: Colors.red[700]!,
                    onPressed: _deleteAccount,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: const TextStyle(fontSize: 16, color: Colors.white)),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
