import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class HardwareService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  final String portName;
  final int baudRate;
  
  final _dataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onData => _dataController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get onStatus => _statusController.stream;

  bool _isReconnecting = false;
  Timer? _reconnectTimer;

  HardwareService({required this.portName, this.baudRate = 115200});

  void connect() {
    if (_port != null && _port!.isOpen) return;

    try {
      _port = SerialPort(portName);
      if (_port!.openReadWrite()) {
        final config = _port!.config;
        config.baudRate = baudRate;
        _port!.config = config;

        _statusController.add('connected');
        _isReconnecting = false;
        _reconnectTimer?.cancel();

        _reader = SerialPortReader(_port!);
        _subscription = _reader!.stream.listen(
          _handleData,
          onError: _handleError,
          onDone: _handleDisconnect,
        );
      } else {
        _statusController.add('error: Failed to open port');
        _scheduleReconnect();
      }
    } catch (e) {
      _statusController.add('error: $e');
      _scheduleReconnect();
    }
  }

  void sendCommand(Map<String, dynamic> command) {
    if (_port == null || !_port!.isOpen) return;
    try {
      final payload = '${jsonEncode(command)}\n';
      _port!.write(Uint8List.fromList(utf8.encode(payload)));
    } catch (e) {
      _statusController.add('error: Send failed ($e)');
      _scheduleReconnect();
    }
  }

  void _handleData(Uint8List data) async {
    try {
      final message = utf8.decode(data).trim();
      if (message.isEmpty) return;

      final parsedList = await compute(_parseJsonBursts, message);
      for (final json in parsedList) {
        _dataController.add(json);
      }
    } catch (e) {
      debugPrint('JSON Parse Error: $e');
    }
  }

  static List<Map<String, dynamic>> _parseJsonBursts(String payload) {
    final results = <Map<String, dynamic>>[];
    final lines = payload.split('\n');
    for (final line in lines) {
      final tLine = line.trim();
      if (tLine.isEmpty) continue;
      
      if (tLine.startsWith('FW:')) {
         results.add({'FW': tLine.substring(3)});
         continue;
      }
      
      if (tLine.startsWith('INJECT:')) {
         results.add({'INJECT': tLine.substring(7)});
         continue;
      }
      
      try {
        results.add(jsonDecode(tLine));
      } catch (_) {}
    }
    return results;
  }

  void _handleError(dynamic error) {
    _statusController.add('error: Connection lost ($error)');
    _scheduleReconnect();
  }

  void _handleDisconnect() {
    _statusController.add('disconnected');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    _cleanupPort();
    _statusController.add('reconnecting...');
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _isReconnecting = false;
      connect();
    });
  }

  void _cleanupPort() {
    _subscription?.cancel();
    _reader?.close();
    if (_port != null && _port!.isOpen) {
      try { _port!.close(); } catch (_) {}
    }
    _port?.dispose();
    _port = null;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _cleanupPort();
    _dataController.close();
    _statusController.close();
  }
}
